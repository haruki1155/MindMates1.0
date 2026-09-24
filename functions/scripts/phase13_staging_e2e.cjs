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
    if (slots.length >= 7) return {date, slots};
  }
  throw new Error('No future PACC date exposes the seven slots required for Phase 13.');
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

async function cancel(student, id) {
  const result = await callable('respondToAppointment', student.token, {
    appointmentId: id, action: 'cancel', reason: 'E2E cleanup.',
  });
  assert.equal(result.ok, true, `Cancellation failed: ${functionError(result)}`);
}

async function waitForArchived(student, id) {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const current = await appointment(student, id);
    if (current.fields?.archivedAt) return current;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error('Terminal appointment was not archived by the deployed trigger.');
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
  assert.equal(result.ok, true, `${collectionId} query failed: ${functionError(result)}`);
  return (Array.isArray(result.body) ? result.body : []).filter((item) => item.document).length;
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
    const [normalSlot, rescheduleOld, rescheduleNew, conflictOld, conflictProposed, concurrentSlot, terminalSlot] = slots;

    const normal = await book(student1, normalSlot.start, 'normal'); report.created.push(normal);
    await confirm(counselor1, normal);
    const normalRead = await appointment(student1, normal);
    assert.equal(stringField(normalRead, 'status'), 'confirmed');
    report.checks.studentSeesConfirmed = true;
    const adminRead = await document(admin.token, `appointments/${normal}`);
    assert.equal(adminRead.ok, true, `Admin cannot read appointment: ${functionError(adminRead)}`);
    report.checks.adminSensitiveAccess = true;

    const studentTwoRead = await document(student2.token, `appointments/${normal}`);
    assert.equal(studentTwoRead.ok, false, 'Student 2 read Student 1 appointment.');
    report.checks.studentPrivacyStatus = studentTwoRead.status;
    const studentTwoAction = await callable('respondToAppointment', student2.token, {appointmentId: normal, action: 'cancel', reason: 'forbidden'});
    assert.equal(studentTwoAction.ok, false, 'Student 2 changed Student 1 appointment.');
    report.checks.studentUnauthorizedAction = functionError(studentTwoAction);
    const counselorTwoRead = await document(counselor2.token, `appointments/${normal}`);
    assert.equal(counselorTwoRead.ok, false, 'Unassigned Counselor 2 read Counselor 1 caseload.');
    const counselorTwoAction = await callable('reviewAppointment', counselor2.token, {appointmentId: normal, action: 'completed', reply: 'forbidden'});
    assert.equal(counselorTwoAction.ok, false, 'Unassigned Counselor 2 changed Counselor 1 caseload.');
    report.checks.counselorAssignmentRestriction = functionError(counselorTwoAction);
    await cancel(student1, normal);
    assert.ok((await getSlots(student1, date)).some((slot) => slot.start === normalSlot.start), 'Cancellation did not release capacity.');
    report.checks.cancellationReleasedCapacity = true;

    const reschedule = await book(student1, rescheduleOld.start, 'reschedule'); report.created.push(reschedule);
    await confirm(counselor1, reschedule);
    const proposal = await callable('reviewAppointment', counselor1.token, {appointmentId: reschedule, action: 'reschedule_proposed', reply: 'E2E reschedule.', proposedScheduledAt: rescheduleNew.start});
    assert.equal(proposal.ok, true, `Counselor proposal failed: ${functionError(proposal)}`);
    const accepted = await callable('respondToAppointment', student1.token, {appointmentId: reschedule, action: 'accept_reschedule'});
    assert.equal(accepted.ok, true, `Student acceptance failed: ${functionError(accepted)}`);
    const moved = await appointment(student1, reschedule);
    assert.equal(stringField(moved, 'status'), 'confirmed');
    assert.equal(timestampField(moved, 'scheduledAt'), rescheduleNew.start);
    const slotsAfterMove = await getSlots(student1, date);
    assert.ok(slotsAfterMove.some((slot) => slot.start === rescheduleOld.start));
    assert.ok(!slotsAfterMove.some((slot) => slot.start === rescheduleNew.start));
    report.checks.transactionalReschedule = true;
    await cancel(student1, reschedule);

    const conflict = await book(student1, conflictOld.start, 'proposal-conflict'); report.created.push(conflict);
    await confirm(counselor1, conflict);
    const conflictProposal = await callable('reviewAppointment', counselor1.token, {appointmentId: conflict, action: 'reschedule_proposed', reply: 'E2E conflict proposal.', proposedScheduledAt: conflictProposed.start});
    assert.equal(conflictProposal.ok, true, `Conflict proposal failed: ${functionError(conflictProposal)}`);
    const occupying = await book(student2, conflictProposed.start, 'proposal-conflict-occupier'); report.created.push(occupying);
    const failedAcceptance = await callable('respondToAppointment', student1.token, {appointmentId: conflict, action: 'accept_reschedule'});
    assert.equal(failedAcceptance.ok, false, 'Conflicted proposal was accepted.');
    const intact = await appointment(student1, conflict);
    assert.equal(stringField(intact, 'status'), 'reschedule_proposed');
    assert.equal(timestampField(intact, 'scheduledAt'), conflictOld.start);
    report.checks.proposalConflictPreservesOriginal = functionError(failedAcceptance);
    await cancel(student1, conflict);
    await cancel(student2, occupying);

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
    await cancel(winnerIsStudent1 ? student1 : student2, winnerId);

    const terminal = await book(student1, terminalSlot.start, 'terminal'); report.created.push(terminal);
    await confirm(counselor1, terminal);
    const complete = await callable('reviewAppointment', counselor1.token, {appointmentId: terminal, action: 'completed', reply: 'E2E completion.'});
    assert.equal(complete.ok, true, `Terminal completion failed: ${functionError(complete)}`);
    const archived = await waitForArchived(student1, terminal);
    assert.equal(stringField(archived, 'status'), 'completed');
    assert.ok(archived.fields?.archivedAt, 'Completed appointment lacks archivedAt.');
    const history = await document(student1.token, `appointments/${terminal}/history`);
    assert.equal(history.ok, true, `Terminal history is not visible to its owner: ${functionError(history)}`);
    const historyCount = (history.body.documents || []).length;
    assert.ok(historyCount >= 2, 'Terminal workflow history is incomplete.');
    const notificationCount = await countByAppointment(student1.token, 'notifications', terminal, 'appointmentId', student1.uid);
    assert.ok(notificationCount >= 1, 'Terminal workflow created no student notification.');
    const auditCount = await countByAppointment(admin.token, 'admin_audit_logs', terminal, 'targetId');
    assert.ok(auditCount >= 1, 'Terminal workflow created no audit record.');
    report.checks.terminalHistoryNotificationAudit = {archived: true, historyCount, notificationCount, auditCount};
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
