/*
 * Phase 13 appointment workflow validation for mindmate-staging.
 *
 * Credentials are intentionally supplied only through the environment; this
 * script must never be aimed at production.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');

const project = process.env.MM_E2E_PROJECT || 'mindmate-staging';
if (project !== 'mindmate-staging') throw new Error('Phase 13 runner is staging-only.');
const apiKey = 'AIzaSyCR2rylEQKFT5C0EzaF-daPlf5hkTr_w2w';
const functionBase = `https://us-central1-${project}.cloudfunctions.net`;

const required = [
  'MM_E2E_STUDENT1_ID', 'MM_E2E_STUDENT1_PASSWORD',
  'MM_E2E_STUDENT2_ID', 'MM_E2E_STUDENT2_PASSWORD',
  'MM_E2E_COUNSELOR1_EMAIL', 'MM_E2E_COUNSELOR1_PASSWORD',
  'MM_E2E_COUNSELOR2_EMAIL', 'MM_E2E_COUNSELOR2_PASSWORD',
  'MM_E2E_ADMIN_EMAIL', 'MM_E2E_ADMIN_PASSWORD',
];
for (const name of required) if (!process.env[name]) throw new Error(`Missing ${name}.`);

async function jsonRequest(url, {method = 'POST', token, body} = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(body === undefined ? {} : {'content-type': 'application/json'}),
      ...(token ? {authorization: `Bearer ${token}`} : {}),
    },
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
  });
  return {ok: response.ok, status: response.status, body: await response.json().catch(() => ({}))};
}

function callable(name, token, data) {
  return jsonRequest(`${functionBase}/${name}`, {token, body: {data}});
}

function functionError(result) {
  return result.body?.error?.status || result.body?.error?.message || `HTTP_${result.status}`;
}

async function resolveStudentEmail(schoolId) {
  const result = await callable('resolveSchoolIdAuthEmailDev', null, {schoolId});
  assert.equal(result.ok, true, `Could not resolve ${schoolId}: ${functionError(result)}`);
  const email = result.body?.result?.data?.email || result.body?.result?.email;
  assert.ok(email, `No Firebase Auth email resolved for ${schoolId}.`);
  return email;
}

async function signIn(label, email, password) {
  const result = await jsonRequest(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
    {body: {email, password, returnSecureToken: true}},
  );
  assert.equal(result.ok, true, `${label} authentication failed: ${functionError(result)}`);
  return {label, uid: result.body.localId, token: result.body.idToken};
}

async function document(token, path) {
  return jsonRequest(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${path}`,
    {method: 'GET', token},
  );
}

async function query(token, structuredQuery) {
  return jsonRequest(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery`,
    {token, body: {structuredQuery}},
  );
}

function stringField(document, name) {
  return document?.fields?.[name]?.stringValue ?? null;
}

function timestampField(document, name) {
  const value = document?.fields?.[name]?.timestampValue;
  return value ? Date.parse(value) : null;
}

function availabilityFrom(document) {
  const fields = document.fields || {};
  return {
    openDays: (fields.openDays?.arrayValue?.values || []).map((value) => Number(value.integerValue)),
    opensAt: fields.opensAt?.stringValue || '',
    closesAt: fields.closesAt?.stringValue || '',
    presence: fields.presence?.stringValue || '',
    acceptsWalkIns: fields.acceptsWalkIns?.booleanValue === true,
    notice: fields.notice?.stringValue || '',
    blackoutDates: (fields.blackoutDates?.arrayValue?.values || []).map((value) => value.stringValue),
  };
}

async function getSlots(student, date) {
  const result = await callable('getAvailableAppointmentSlots', student.token, {date});
  assert.equal(result.ok, true, `Availability failed for ${date}: ${functionError(result)}`);
  return result.body?.result?.slots || result.body?.result?.data?.slots || [];
}

async function chooseSlots(student, openDays) {
  for (let offset = 1; offset <= 14; offset += 1) {
    const date = new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
    const weekday = new Date(`${date}T00:00:00.000Z`).getUTCDay() || 7;
    if (!openDays.includes(weekday)) continue;
    const slots = await getSlots(student, date);
    if (slots.length >= 6) return {date, slots};
  }
  throw new Error('No future PACC date exposes the six slots required for revised Phase 13 validation.');
}

async function book(student, start, suffix) {
  const result = await callable('createAppointmentRequest', student.token, {
    scheduledAt: start,
    concern: `E2E Phase 13 ${suffix}`,
    contactNumber: '09171234567',
    preferredContactMethod: 'Email',
    bestTime: 'Morning',
    location: 'PACC Office, 2nd Floor, Main Building',
  });
  assert.equal(result.ok, true, `Booking ${suffix} failed: ${functionError(result)}`);
  const appointmentId = result.body?.result?.appointmentId || result.body?.result?.data?.appointmentId;
  assert.ok(appointmentId, `Booking ${suffix} returned no appointment ID.`);
  return appointmentId;
}

async function appointment(actor, id) {
  const result = await document(actor.token, `appointments/${id}`);
  assert.equal(result.ok, true, `${actor.label} cannot read expected appointment: ${functionError(result)}`);
  return result.body;
}

async function confirm(counselor, id) {
  const result = await callable('reviewAppointment', counselor.token, {
    appointmentId: id, action: 'confirmed', reply: 'E2E confirmation.',
  });
  assert.equal(result.ok, true, `Confirmation failed: ${functionError(result)}`);
}

async function expectDeniedAction(actor, name, data, description) {
  const result = await callable(name, actor.token, data);
  assert.equal(result.ok, false, `${description} unexpectedly succeeded.`);
  return functionError(result);
}

async function markDidNotAttend(counselor, id, reply = 'E2E unattended session.') {
  const result = await callable('reviewAppointment', counselor.token, {
    appointmentId: id, action: 'no_show', reply,
  });
  assert.equal(result.ok, true, `Did Not Attend action failed: ${functionError(result)}`);
}

function documentsFromQuery(result) {
  assert.equal(result.ok, true, `Firestore query failed: ${functionError(result)}`);
  return (Array.isArray(result.body) ? result.body : [])
    .map((item) => item.document)
    .filter(Boolean);
}

async function countByAppointment(token, collectionId, appointmentId, fieldPath = 'appointmentId', ownerId = null) {
  const appointmentFilter = {
    field: {fieldPath}, op: 'EQUAL', value: {stringValue: appointmentId},
  };
  const where = ownerId ? {
    compositeFilter: {
      op: 'AND',
      filters: [
        {fieldFilter: {field: {fieldPath: 'userId'}, op: 'EQUAL', value: {stringValue: ownerId}}},
        {fieldFilter: appointmentFilter},
      ],
    },
  } : {fieldFilter: appointmentFilter};
  const result = await query(token, {
    from: [{collectionId}],
    where,
  });
  return documentsFromQuery(result).length;
}

async function documentsByAppointment(token, collectionId, appointmentId, fieldPath = 'appointmentId', ownerId = null) {
  const appointmentFilter = {
    field: {fieldPath}, op: 'EQUAL', value: {stringValue: appointmentId},
  };
  const where = ownerId ? {
    compositeFilter: {
      op: 'AND',
      filters: [
        {fieldFilter: {field: {fieldPath: 'userId'}, op: 'EQUAL', value: {stringValue: ownerId}}},
        {fieldFilter: appointmentFilter},
      ],
    },
  } : {fieldFilter: appointmentFilter};
  const result = await query(token, {from: [{collectionId}], where});
  return documentsFromQuery(result);
}

async function main() {
  const report = {project, checks: {}, created: []};
  const [student1Email, student2Email] = await Promise.all([
    resolveStudentEmail(process.env.MM_E2E_STUDENT1_ID),
    resolveStudentEmail(process.env.MM_E2E_STUDENT2_ID),
  ]);
  const [student1, student2, counselor1, counselor2, admin] = await Promise.all([
    signIn('student-1', student1Email, process.env.MM_E2E_STUDENT1_PASSWORD),
    signIn('student-2', student2Email, process.env.MM_E2E_STUDENT2_PASSWORD),
    signIn('counselor-1', process.env.MM_E2E_COUNSELOR1_EMAIL, process.env.MM_E2E_COUNSELOR1_PASSWORD),
    signIn('counselor-2', process.env.MM_E2E_COUNSELOR2_EMAIL, process.env.MM_E2E_COUNSELOR2_PASSWORD),
    signIn('admin', process.env.MM_E2E_ADMIN_EMAIL, process.env.MM_E2E_ADMIN_PASSWORD),
  ]);

  const actors = [student1, student2, counselor1, counselor2, admin];
  for (const actor of actors) {
    const profile = await document(actor.token, `users/${actor.uid}`);
    assert.equal(profile.ok, true, `${actor.label} cannot read own profile.`);
    report.checks[`${actor.label}-role`] = stringField(profile.body, 'accessRole') || stringField(profile.body, 'role');
  }
  assert.equal(report.checks['student-1-role'], 'appUser');
  assert.equal(report.checks['student-2-role'], 'appUser');
  assert.equal(report.checks['counselor-1-role'], 'counselor');
  assert.equal(report.checks['counselor-2-role'], 'counselor');
  assert.equal(report.checks['admin-role'], 'admin');
  report.checks['counselor-1-status'] = stringField((await document(counselor1.token, `users/${counselor1.uid}`)).body, 'accountStatus');
  report.checks['counselor-2-status'] = stringField((await document(counselor2.token, `users/${counselor2.uid}`)).body, 'accountStatus');
  assert.equal(report.checks['counselor-1-status'], 'active');
  assert.equal(report.checks['counselor-2-status'], 'active');

  const availabilityRead = await document(student1.token, 'pacc_availability/current');
  assert.equal(availabilityRead.ok, true, 'Authenticated student cannot read published availability.');
  const originalAvailability = availabilityFrom(availabilityRead.body);
  assert.ok(originalAvailability.openDays.length > 0, 'Published availability has no open days.');
  const temporaryAvailability = {...originalAvailability, presence: 'in_office'};
  let restored = false;

  try {
    const directAvailabilityWrite = await jsonRequest(
      `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/pacc_availability/current?updateMask.fieldPaths=notice`,
      {method: 'PATCH', token: student1.token, body: {fields: {notice: {stringValue: 'forbidden'}}}},
    );
    assert.equal(directAvailabilityWrite.ok, false, 'Student directly changed PACC availability.');
    report.checks.unauthorizedAvailabilityDirectWrite = directAvailabilityWrite.status;

    const unauthorizedAvailabilityCallable = await callable('savePaccAvailability', student1.token, temporaryAvailability);
    assert.equal(unauthorizedAvailabilityCallable.ok, false, 'Student changed PACC availability through callable.');
    report.checks.unauthorizedAvailabilityCallable = functionError(unauthorizedAvailabilityCallable);

    const publish = await callable('savePaccAvailability', admin.token, temporaryAvailability);
    assert.equal(publish.ok, true, `Admin availability publish failed: ${functionError(publish)}`);
    report.checks.adminAvailabilityCallable = true;

    const {date, slots} = await chooseSlots(student1, temporaryAvailability.openDays);
    report.checks.selectedDate = date;
    const [oneActiveSlot, rescheduleOld, rescheduleNew, followUpParentSlot, followUpChildSlot, concurrentSlot] = slots;

    const oneActive = await book(student1, oneActiveSlot.start, 'one-active'); report.created.push(oneActive);
    await confirm(counselor1, oneActive);
    const normalRead = await appointment(student1, oneActive);
    assert.equal(stringField(normalRead, 'status'), 'confirmed');
    report.checks.studentSeesConfirmed = true;
    const secondBooking = await callable('createAppointmentRequest', student1.token, {
      scheduledAt: rescheduleOld.start,
      concern: 'E2E second active appointment.',
      contactNumber: '09171234567', preferredContactMethod: 'Email', bestTime: 'Morning',
      location: 'PACC Office, 2nd Floor, Main Building',
    });
    assert.equal(secondBooking.ok, false, 'Student created a second active appointment.');
    report.checks.oneActiveAppointmentLimit = functionError(secondBooking);
    const adminRead = await document(admin.token, `appointments/${oneActive}`);
    assert.equal(adminRead.ok, true, `Admin cannot read appointment: ${functionError(adminRead)}`);
    report.checks.adminSensitiveAccess = true;

    const studentTwoRead = await document(student2.token, `appointments/${oneActive}`);
    assert.equal(studentTwoRead.ok, false, 'Student 2 read Student 1 appointment.');
    report.checks.studentPrivacyStatus = studentTwoRead.status;
    report.checks.studentUnauthorizedAction = await expectDeniedAction(
      student2, 'respondToAppointment', {appointmentId: oneActive, action: 'accept_reschedule'},
      'Student 2 changed Student 1 appointment',
    );
    const counselorTwoRead = await document(counselor2.token, `appointments/${oneActive}`);
    assert.equal(counselorTwoRead.ok, false, 'Unassigned Counselor 2 read Counselor 1 caseload.');
    report.checks.counselorAssignmentRestriction = await expectDeniedAction(
      counselor2, 'reviewAppointment', {appointmentId: oneActive, action: 'completed', reply: 'forbidden', sessionSummary: 'forbidden'},
      'Unassigned Counselor 2 changed Counselor 1 appointment',
    );
    report.checks.studentCannotCancel = await expectDeniedAction(
      student1, 'respondToAppointment', {appointmentId: oneActive, action: 'cancel'},
      'Student cancellation',
    );
    report.checks.studentCannotProposeSchedule = await expectDeniedAction(
      student1, 'reviewAppointment', {appointmentId: oneActive, action: 'reschedule_proposed', proposedScheduledAt: rescheduleNew.start, rescheduleReason: 'Counselor availability'},
      'Student schedule proposal',
    );
    report.checks.staffCannotCancel = await expectDeniedAction(
      counselor1, 'reviewAppointment', {appointmentId: oneActive, action: 'cancel'},
      'Staff cancellation',
    );
    report.checks.staffCannotDecline = await expectDeniedAction(
      counselor1, 'reviewAppointment', {appointmentId: oneActive, action: 'declined'},
      'Staff decline',
    );
    await markDidNotAttend(counselor1, oneActive);
    const unattended = await appointment(student1, oneActive);
    assert.equal(stringField(unattended, 'status'), 'no_show');
    const unattendedNotifications = await documentsByAppointment(student1.token, 'notifications', oneActive, 'appointmentId', student1.uid);
    assert.ok(unattendedNotifications.some((item) => JSON.stringify(item).includes('Did Not Attend')), 'Did Not Attend notification was not client-visible.');
    report.checks.didNotAttendClientTerminology = true;

    const reschedule = await book(student1, rescheduleOld.start, 'reschedule'); report.created.push(reschedule);
    await confirm(counselor1, reschedule);
    const proposal = await callable('reviewAppointment', counselor1.token, {
      appointmentId: reschedule, action: 'reschedule_proposed', reply: 'E2E reschedule.',
      proposedScheduledAt: rescheduleNew.start, rescheduleReason: 'Counselor availability',
    });
    assert.equal(proposal.ok, true, `Counselor proposal failed: ${functionError(proposal)}`);
    const proposed = await appointment(student1, reschedule);
    assert.equal(stringField(proposed, 'status'), 'reschedule_proposed');
    assert.equal(stringField(proposed, 'rescheduleReason'), 'Counselor availability');
    const accepted = await callable('respondToAppointment', student1.token, {appointmentId: reschedule, action: 'accept_reschedule'});
    assert.equal(accepted.ok, true, `Student acceptance failed: ${functionError(accepted)}`);
    const moved = await appointment(student1, reschedule);
    assert.equal(stringField(moved, 'status'), 'confirmed');
    assert.equal(timestampField(moved, 'scheduledAt'), rescheduleNew.start);
    const slotsAfterMove = await getSlots(student1, date);
    assert.ok(slotsAfterMove.some((slot) => slot.start === rescheduleOld.start));
    assert.ok(!slotsAfterMove.some((slot) => slot.start === rescheduleNew.start));
    report.checks.transactionalReschedule = true;
    await markDidNotAttend(counselor1, reschedule, 'E2E rescheduled session unattended.');

    const followUpParent = await book(student1, followUpParentSlot.start, 'follow-up-parent'); report.created.push(followUpParent);
    await confirm(counselor1, followUpParent);
    const privateSummary = 'E2E private clinical summary must stay protected.';
    const followUpMessage = 'Please book your recommended follow-up session.';
    const complete = await callable('reviewAppointment', counselor1.token, {
      appointmentId: followUpParent, action: 'completed', reply: 'E2E completion.', sessionSummary: privateSummary,
      offerFollowUp: true, followUpMessage,
    });
    assert.equal(complete.ok, true, `Follow-up parent completion failed: ${functionError(complete)}`);
    const completedParent = await appointment(student1, followUpParent);
    assert.equal(stringField(completedParent, 'status'), 'completed');
    assert.equal(stringField(completedParent, 'followUpMessage'), followUpMessage);
    assert.equal(JSON.stringify(completedParent).includes(privateSummary), false, 'Private summary leaked into the client appointment.');
    const clientClinicalRead = await document(student1.token, `appointments/${followUpParent}/clinical_notes/session`);
    assert.equal(clientClinicalRead.ok, false, 'Student read a protected clinical note.');
    const followUpNotifications = await documentsByAppointment(student1.token, 'notifications', followUpParent, 'appointmentId', student1.uid);
    assert.ok(followUpNotifications.some((item) => JSON.stringify(item).includes(followUpMessage)), 'Follow-up notification did not contain the client message.');
    assert.equal(followUpNotifications.some((item) => JSON.stringify(item).includes(privateSummary)), false, 'Private summary leaked into a client notification.');
    const followUp = await callable('createAppointmentRequest', student1.token, {
      scheduledAt: followUpChildSlot.start,
      concern: 'E2E follow-up with updated concern.', contactNumber: '09171234567',
      preferredContactMethod: 'Email', bestTime: 'Afternoon', location: 'PACC Office, 2nd Floor, Main Building',
      parentAppointmentId: followUpParent,
    });
    assert.equal(followUp.ok, true, `Follow-up booking failed: ${functionError(followUp)}`);
    const followUpId = followUp.body?.result?.appointmentId || followUp.body?.result?.data?.appointmentId;
    assert.ok(followUpId, 'Follow-up booking returned no appointment ID.');
    report.created.push(followUpId);
    const linkedFollowUp = await appointment(student1, followUpId);
    const parentAfterFollowUp = await appointment(student1, followUpParent);
    assert.equal(stringField(linkedFollowUp, 'parentAppointmentId'), followUpParent);
    assert.equal(stringField(parentAfterFollowUp, 'followUpStatus'), 'booked');
    assert.equal(stringField(parentAfterFollowUp, 'followUpAppointmentId'), followUpId);
    report.checks.followUpClientSafeAndLinked = true;
    await confirm(counselor1, followUpId);
    await markDidNotAttend(counselor1, followUpId, 'E2E follow-up session unattended.');

    const concurrent = await Promise.allSettled([
      book(student1, concurrentSlot.start, 'concurrent-student-1'),
      book(student2, concurrentSlot.start, 'concurrent-student-2'),
    ]);
    const winners = concurrent.filter((entry) => entry.status === 'fulfilled');
    const losers = concurrent.filter((entry) => entry.status === 'rejected');
    assert.equal(winners.length, 1, 'Same-slot booking did not have exactly one winner.');
    assert.equal(losers.length, 1, 'Same-slot booking did not have exactly one rejection.');
    assert.match(String(losers[0].reason), /already[-_]exists|no longer available/i);
    const winnerId = winners[0].value;
    report.created.push(winnerId);
    report.checks.sameSlotConcurrency = 'one reservation';
    const winnerIsStudent1 = concurrent[0].status === 'fulfilled';
    const winner = winnerIsStudent1 ? student1 : student2;
    await confirm(counselor1, winnerId);
    await markDidNotAttend(counselor1, winnerId, 'E2E concurrent winner unattended.');
    const history = await document(winner.token, `appointments/${winnerId}/history`);
    assert.equal(history.ok, true, `Terminal history is not visible to its owner: ${functionError(history)}`);
    const historyCount = (history.body.documents || []).length;
    assert.ok(historyCount >= 2, 'Terminal workflow history is incomplete.');
    const notificationCount = await countByAppointment(winner.token, 'notifications', winnerId, 'appointmentId', winner.uid);
    assert.ok(notificationCount >= 1, 'Terminal workflow created no student notification.');
    const auditCount = await countByAppointment(admin.token, 'admin_audit_logs', winnerId, 'targetId');
    assert.ok(auditCount >= 1, 'Terminal workflow created no audit record.');
    report.checks.terminalHistoryNotificationAudit = {historyCount, notificationCount, auditCount};
  } finally {
    const restore = await callable('savePaccAvailability', admin.token, originalAvailability);
    restored = restore.ok;
    report.checks.availabilityRestored = restored;
    if (!restored) throw new Error(`Could not restore original staging availability: ${functionError(restore)}`);
  }

  const rendered = JSON.stringify(report, null, 2);
  if (process.env.MM_E2E_REPORT_PATH) fs.writeFileSync(process.env.MM_E2E_REPORT_PATH, rendered);
  console.log(rendered);
}

main().catch((error) => {
  if (process.env.MM_E2E_REPORT_PATH) {
    fs.writeFileSync(`${process.env.MM_E2E_REPORT_PATH}.error.txt`, String(error.stack || error));
  }
  console.error(error.stack || error);
  process.exitCode = 1;
});
