import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {createHash} from "node:crypto";
import {validateAppointmentTimestamp, AppointmentSchedulingValidationError} from "./appointment_scheduling";
import {validatePaccAppointmentAvailability, AppointmentAvailabilityValidationError} from "./appointment_availability";
import {appointmentBookingPolicy, bookingPolicyViolation} from "./appointment_policy";
import {boundedText} from "./appointment_intake";
import {AUDIT_CATEGORIES, writeAudit} from "./audit";
import {canonicalAppointmentStatus} from "./appointment_lifecycle";

type StaffAuthorizer = (uid: string) => Promise<FirebaseFirestore.DocumentData>;
export async function handleAppointmentAgreement(uid: string, input: Record<string, unknown>, authorizeStaff: StaffAuthorizer) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  const id = String(input.appointmentId ?? "");
  const requestId = String(input.requestId ?? "");
  const action = String(input.action ?? "");
  const expected = input.expectedScheduledAt;
  const expectedRevision = input.expectedScheduleRevision;
  const expectedProposal = input.expectedProposalRevision ?? 0;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id) || !/^[A-Za-z0-9_-]{8,100}$/.test(requestId) || !["propose", "accept", "cancel"].includes(action) || !Number.isSafeInteger(expected) || !Number.isSafeInteger(expectedRevision) || Number(expectedRevision) < 0 || !Number.isSafeInteger(expectedProposal) || Number(expectedProposal) < 0) throw new HttpsError("invalid-argument", "Refresh the appointment and try again.");
  const reason = boundedText(input.reason ?? (action === "propose" ? input.rescheduleReason : undefined), "Appointment reason", action === "cancel" ? 500 : 1000);
  let proposed: ReturnType<typeof validateAppointmentTimestamp> | undefined;
  if (action === "propose") {
    try { proposed = validateAppointmentTimestamp(input.scheduledAt); }
    catch (e) { if (e instanceof AppointmentSchedulingValidationError) throw new HttpsError("invalid-argument", e.message); throw e; }
  }
  const db = getFirestore();
  const ref = db.doc(`appointments/${id}`);
  const opened = (await ref.get()).data();
  if (!opened) throw new HttpsError("not-found", "Appointment unavailable.");
  const owner = String(opened.userId ?? "");
  const isStudent = owner === uid;
  const actor = isStudent ? undefined : await authorizeStaff(uid);
  if (action === "cancel" && !isStudent) throw new HttpsError("permission-denied", "Only the student can use this cancellation action.");
  const recipients = isStudent ? (await db.collection("users").where("accessRole", "in", ["portalStaff", "admin", "counselor"]).get()).docs.map(d => d.id) : [owner];
  const fingerprint = createHash("sha256").update(JSON.stringify([uid, action, expected, expectedRevision, expectedProposal, proposed?.millis ?? null, reason])).digest("hex");
  return db.runTransaction(async tx => {
    const replay = ref.collection("agreement_requests").doc(requestId);
    const [snap, prior] = await Promise.all([tx.get(ref), tx.get(replay)]);
    const data = snap.data();
    if (!data || data.userId !== owner) throw new HttpsError("permission-denied", "Appointment unavailable.");
    if (prior.exists) {
      if (prior.data()?.fingerprint !== fingerprint) throw new HttpsError("already-exists", "Request ID already used.");
      return {ok: true, idempotentReplay: true};
    }
    const revision = data.scheduleRevision;
    const proposalRevision = data.proposalRevision ?? 0;
    const status = canonicalAppointmentStatus(data.status);
    const currentAt = data.scheduledAt instanceof Timestamp ? data.scheduledAt.toMillis() : 0;
    if (!Number.isSafeInteger(revision) || !Number.isSafeInteger(proposalRevision) || revision < 0 || proposalRevision < 0 || revision >= Number.MAX_SAFE_INTEGER || proposalRevision >= Number.MAX_SAFE_INTEGER) throw new HttpsError("failed-precondition", "Appointment revision requires review.");
    if (currentAt !== expected || revision !== expectedRevision || proposalRevision !== expectedProposal) throw new HttpsError("aborted", "The appointment changed. Reopen it before trying again.");
    if (data.archivedAt || currentAt <= Date.now() || !["requested", "confirmed", "reschedule_proposed"].includes(status)) throw new HttpsError("failed-precondition", "This appointment is no longer eligible for this action.");
    const oldSlot = db.doc(`appointment_slots/pacc_${currentAt}`);
    const lock = db.doc(`appointment_user_locks/${owner}`);
    const [old, active] = await Promise.all([tx.get(oldSlot), tx.get(lock)]);
    if (old.data()?.appointmentId !== id || active.data()?.appointmentId !== id) throw new HttpsError("failed-precondition", "The existing reservation needs PACC review.");
    const pending = data.proposalStatus === "pending" && data.proposedScheduledAt instanceof Timestamp;
    if (action === "accept") {
      if (!pending || (data.proposedBy !== "student" && data.proposedBy !== "counselor")) throw new HttpsError("failed-precondition", "There is no current proposal to accept.");
      if ((isStudent && data.proposedBy === "student") || (!isStudent && data.proposedBy === "counselor")) throw new HttpsError("permission-denied", "The other side must accept this proposal.");
      try { proposed = validateAppointmentTimestamp(data.proposedScheduledAt.toMillis()); }
      catch (e) { if (e instanceof AppointmentSchedulingValidationError) throw new HttpsError("failed-precondition", e.message); throw e; }
    }
    if (action === "propose" && proposed!.millis === currentAt) {
      if (pending) throw new HttpsError("failed-precondition", "Choose another time or resolve the current proposal.");
      tx.create(replay, {fingerprint, createdAt: FieldValue.serverTimestamp()});
      return {ok: true, unchanged: true};
    }
    let destination: FirebaseFirestore.DocumentReference | undefined;
    if (proposed) {
      destination = db.doc(`appointment_slots/pacc_${proposed.millis}`);
      const [occupied, availability, policy] = await Promise.all([tx.get(destination), tx.get(db.doc("pacc_availability/current")), tx.get(db.doc("appointment_policy/current"))]);
      if (proposed.millis !== currentAt && occupied.exists) throw new HttpsError("already-exists", "That time is no longer available. Your current reservation has been kept.");
      try { validatePaccAppointmentAvailability(proposed.millis, availability.exists ? availability.data() : null); }
      catch (e) { if (e instanceof AppointmentAvailabilityValidationError) throw new HttpsError("failed-precondition", e.message); throw e; }
      const violation = bookingPolicyViolation(appointmentBookingPolicy(policy.exists ? policy.data() : null), proposed.millis);
      if (violation) throw new HttpsError("failed-precondition", violation);
    }
    const patch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {updatedAt: FieldValue.serverTimestamp(), proposalRevision: proposalRevision + 1, actionBy: uid, agreementRequestId: requestId};
    let event: string;
    if (action === "propose") {
      Object.assign(patch, {proposedScheduledAt: Timestamp.fromMillis(proposed!.millis), proposedScheduledTime: proposed!.scheduledTime, proposedBy: isStudent ? "student" : "counselor", proposalStatus: "pending", proposalRequestId: requestId});
      event = "appointment_schedule_proposed";
    } else if (action === "accept") {
      if (proposed!.millis !== currentAt) {
        tx.create(destination!, {appointmentId: id, scheduledAt: Timestamp.fromMillis(proposed!.millis), createdAt: FieldValue.serverTimestamp()});
        tx.delete(oldSlot);
      }
      Object.assign(patch, {scheduledAt: Timestamp.fromMillis(proposed!.millis), scheduledTime: proposed!.scheduledTime, scheduleRevision: proposed!.millis === currentAt ? revision : revision + 1, status: "confirmed", proposalStatus: "accepted", reviewedAt: FieldValue.serverTimestamp(), reminders: {}});
      event = "appointment_schedule_agreed";
    } else {
      tx.delete(oldSlot);
      tx.delete(lock);
      Object.assign(patch, {status: "cancelled", scheduleRevision: revision + 1, proposalStatus: "cancelled", cancelledAt: FieldValue.serverTimestamp(), cancelledBy: uid, reminders: {}});
      event = "appointment_cancelled";
    }
    tx.update(ref, patch);
    tx.create(replay, {fingerprint, createdAt: FieldValue.serverTimestamp()});
    tx.create(ref.collection("history").doc(), {type: event, performedBy: uid, performedByRole: isStudent ? "student" : "staff", previousStatus: status, newStatus: patch.status ?? status, previousScheduledAt: data.scheduledAt, scheduledAt: patch.scheduledAt ?? data.scheduledAt, ...(reason ? {reason} : {}), ...(action === "propose" ? {proposedScheduledAt: Timestamp.fromMillis(proposed!.millis), proposedScheduledTime: proposed!.scheduledTime, proposedBy: isStudent ? "student" : "counselor"} : {}), proposalRevision: proposalRevision + 1, createdAt: FieldValue.serverTimestamp()});
    writeAudit(tx, db, {actorId: uid, actorNameSnapshot: isStudent ? "Student" : String(actor?.name ?? "PACC staff"), actorRoleSnapshot: isStudent ? "appUser" : String(actor?.accessRole ?? ""), action: action === "propose" ? "APPOINTMENT_SCHEDULE_PROPOSED" : action === "accept" ? "APPOINTMENT_SCHEDULE_AGREED" : "APPOINTMENT_CANCELLED", category: AUDIT_CATEGORIES.appointments, targetType: "appointment", targetId: id, metadata: {before: {status}, after: {status: patch.status ?? status, proposalRevision: proposalRevision + 1}}});
    for (const recipient of recipients) tx.create(db.doc(`notifications/agreement_${id}_${requestId}_${recipient}`), {
      userId: recipient, appointmentId: id, type: recipient === owner ? event : "appointment", agreementEvent: event,
      audience: recipient === owner ? "app" : "portal",
      studentScheduleRequestId: data.studentScheduleRequestId ?? null,
      title: action === "propose" ? "Appointment time proposed" : action === "accept" ? "Appointment time agreed" : "Appointment cancelled",
      body: action === "propose" ? "A new preferred time needs your review. The current time remains reserved." : action === "accept" ? "Both sides have agreed to the appointment time." : "The student cancelled this appointment.",
      expectedStatus: patch.status ?? status, scheduleRevision: patch.scheduleRevision ?? revision, proposalRevision: proposalRevision + 1, scheduledAt: patch.scheduledAt ?? data.scheduledAt,
      createdAt: FieldValue.serverTimestamp(), readAt: null,
    });
    return {ok: true, idempotentReplay: false};
  });
}
