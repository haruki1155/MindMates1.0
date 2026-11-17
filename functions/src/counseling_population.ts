import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {defineBoolean} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireStaff, requireSuperAdmin, requireUid, roleOf} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAudit} from "./audit";
import {
  AcademicYearError,
  AcademicYearSummary,
  decideAcademicYearCreate,
  manilaCurrentSchoolStartYear,
  manilaTodayIso,
  parseAcademicYearInput,
  parseSchoolYear,
  parseStoredAcademicYearStatus,
  revisionOfAcademicYear,
  validateAcademicYearActivation,
  validateAcademicYearClose,
  validateAcademicYearVoid,
} from "./academic_year";

if (!getApps().length) initializeApp();
const db = getFirestore();

// Disabled by default until Batch B2 (getReportAnalytics) and updated Web Admin
// are deployed, preventing older reporting readers from misclassifying
// "planned" or "voided" docs as "current".
export const academicYearExtendedLifecycleEnabled = defineBoolean(
  "ACADEMIC_YEAR_EXTENDED_LIFECYCLE_ENABLED",
  {default: false},
);

// Keep this list aligned with the registration organization catalog. Population
// settings are keyed by school year, so the next school year can be entered
// without overwriting historical totals.
export const REPORT_DEPARTMENTS = [
  "College of Accountancy and Business Administration",
  "College of Arts and Sciences / College of Arts and Languages",
  "College of Information and Technology Education / College of Computer Studies",
  "College of Criminology",
  "College of Education / College of Teacher Education",
  "College of Engineering and Architecture",
  "College of Law",
  "College of Nursing",
  "College of Pharmacy",
  "College of Science and Mathematics",
  "College of Social Work",
  "Graduate School / Institute of Graduate and Advanced Studies",
  "School of Hotel and Restaurant Services and Tourism Management",
  "School of Midwifery",
] as const;

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";
const config = (schoolYear: string) => db.collection("counseling_population").doc(schoolYear);

export type AcademicYearRecord = AcademicYearSummary;

function toAcademicYearRecord(id: string, data: FirebaseFirestore.DocumentData): AcademicYearRecord {
  const schoolYear = text(data.schoolYear) || id;
  const startDate = text(data.startDate) || `${schoolYear.slice(0, 4)}-06-01`;
  const endDate = text(data.endDate) || `${Number(schoolYear.slice(5, 9))}-05-31`;
  return {
    schoolYear,
    startDate,
    endDate,
    status: parseStoredAcademicYearStatus(data.status),
    revision: revisionOfAcademicYear(data),
    voidReason: text(data.voidReason) || null,
  };
}

export async function listAcademicYears(options: {includeVoided?: boolean; includeUnknown?: boolean} = {}): Promise<AcademicYearRecord[]> {
  const includeVoided = options.includeVoided === true;
  const includeUnknown = options.includeUnknown === true;
  const snapshot = await db.collection("counseling_population").get();
  return snapshot.docs
    .map((doc) => toAcademicYearRecord(doc.id, doc.data()))
    .filter((record) => {
      if (record.status === "voided" && !includeVoided) return false;
      if (record.status === "unknown" && !includeUnknown) return false;
      return true;
    })
    .sort((a, b) => b.schoolYear.localeCompare(a.schoolYear));
}

async function requireActiveAdmin(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const staff = await requireStaff(uid);
  if (staff.accessRole !== "admin") {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  return staff;
}

function rethrowAcademicYearError(error: unknown): never {
  if (error instanceof AcademicYearError) {
    throw new HttpsError(error.code, error.message);
  }
  throw error;
}

export function defaultSchoolYear(now = new Date()): string {
  const start = manilaCurrentSchoolStartYear(manilaTodayIso(now));
  return `${start}-${start + 1}`;
}

export async function readPopulationConfig(schoolYear: string) {
  const snapshot = await config(schoolYear).get();
  const data = snapshot.data();
  const raw = data?.populations;
  const populations: Record<string, number> = {};
  if (raw && typeof raw === "object") {
    for (const department of REPORT_DEPARTMENTS) {
      const value = (raw as Record<string, unknown>)[department];
      if (typeof value === "number" && Number.isInteger(value) && value > 0) {
        populations[department] = value;
      }
    }
  }
  return {
    schoolYear,
    startDate: text(data?.startDate) || `${schoolYear.slice(0, 4)}-06-01`,
    endDate: text(data?.endDate) || `${Number(schoolYear.slice(5, 9))}-05-31`,
    status: snapshot.exists ? parseStoredAcademicYearStatus(data?.status) : ("unknown" as const),
    revision: snapshot.exists ? revisionOfAcademicYear(data) : 0,
    departments: [...REPORT_DEPARTMENTS],
    populations,
    configured: REPORT_DEPARTMENTS.every((department) => populations[department] != null),
    totalPopulation: Object.values(populations).reduce((total, value) => total + value, 0),
  };
}

export type AcademicYearRuntimeOptions = {
  now?: Date;
  extendedLifecycleEnabled?: boolean;
};

function resolveRuntimeOptions(options?: AcademicYearRuntimeOptions) {
  let extended = options?.extendedLifecycleEnabled;
  if (extended === undefined) {
    try {
      extended = academicYearExtendedLifecycleEnabled.value();
    } catch {
      extended = false;
    }
  }
  return {
    now: options?.now ?? new Date(),
    extendedLifecycleEnabled: Boolean(extended),
  };
}

function manilaBounds(startDate: string, endDate: string): {start: Timestamp; endExclusive: Timestamp} {
  const startMs = new Date(`${startDate}T00:00:00+08:00`).getTime();
  const endMs = new Date(`${endDate}T00:00:00+08:00`).getTime() + 86_400_000;
  return {
    start: Timestamp.fromMillis(startMs),
    endExclusive: Timestamp.fromMillis(endMs),
  };
}

export const getCounselingPopulation = onCall(async (request) => {
  const uid = requireUid(request);
  await requireActiveAdmin(uid);
  try {
    const {schoolYear} = parseSchoolYear(request.data?.schoolYear);
    return {...await readPopulationConfig(schoolYear), years: await listAcademicYears()};
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export const getAcademicYears = onCall(async (request) => {
  const uid = requireUid(request);
  await requireActiveAdmin(uid);
  const includeVoided = request.data?.includeVoided === true;
  return {years: await listAcademicYears({includeVoided})};
});

export async function createAcademicYearForActor(
  uid: string,
  actor: FirebaseFirestore.DocumentData,
  data: Record<string, unknown>,
  options?: AcademicYearRuntimeOptions,
) {
  const {now, extendedLifecycleEnabled} = resolveRuntimeOptions(options);
  const todayManila = manilaTodayIso(now);
  const candidate = parseAcademicYearInput({
    schoolYear: data.schoolYear,
    startDate: data.startDate,
    endDate: data.endDate,
  });
  const sourceYear = text(data.copyFrom);
  const copyPopulation = data.copyPopulation === true;
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(db.collection("counseling_population"));
    const existing = snapshot.docs.map((doc) => toAcademicYearRecord(doc.id, doc.data()));
    const decision = decideAcademicYearCreate({
      candidate,
      existing,
      todayManila,
      extendedLifecycleEnabled,
    });
    const sourceSnap = sourceYear ? snapshot.docs.find((doc) => doc.id === sourceYear) : undefined;
    const sourceDoc = sourceSnap && parseStoredAcademicYearStatus(sourceSnap.data().status) !== "voided"
      ? sourceSnap.data()
      : undefined;
    const targetRef = config(candidate.schoolYear);
    if (decision.kind === "reinstate") {
      const priorSnap = snapshot.docs.find((doc) => doc.id === candidate.schoolYear);
      const priorData = priorSnap?.data() ?? {};
      const voidRev = decision.previousVoidRevision ?? 0;
      tx.set(targetRef.collection("void_history").doc(`rev_${voidRev}`), {
        schoolYear: candidate.schoolYear,
        voidRevision: voidRev,
        status: priorData.status ?? "voided",
        voidedAt: priorData.voidedAt ?? null,
        voidedBy: priorData.voidedBy ?? null,
        voidReason: priorData.voidReason ?? null,
        voidedSnapshot: priorData.voidedSnapshot ?? null,
        archivedBeforeReinstateAt: FieldValue.serverTimestamp(),
        archivedBeforeReinstateBy: uid,
      });
      tx.update(targetRef, {
        schoolYear: candidate.schoolYear,
        startDate: candidate.startDate,
        endDate: candidate.endDate,
        status: decision.initialStatus,
        populations: copyPopulation && sourceDoc?.populations ? sourceDoc.populations : {},
        revision: decision.nextRevision,
        reinstatedFromVoidRevision: voidRev,
        reinstatedAt: FieldValue.serverTimestamp(),
        reinstatedBy: uid,
        voidedAt: FieldValue.delete(),
        voidedBy: FieldValue.delete(),
        voidReason: FieldValue.delete(),
        voidedSnapshot: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      });
      writeAudit(tx, db, {
        actorId: uid,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "ACADEMIC_YEAR_REINSTATED",
        category: AUDIT_CATEGORIES.system,
        targetType: "academic_year",
        targetId: candidate.schoolYear,
        metadata: {
          academicYearId: candidate.schoolYear,
          initialStatus: decision.initialStatus,
          startDate: candidate.startDate,
          endDate: candidate.endDate,
          reinstatedFromVoidRevision: voidRev,
          revision: decision.nextRevision,
          copiedFrom: copyPopulation && sourceDoc ? sourceYear : null,
        },
      });
      return;
    }

    tx.set(targetRef, {
      schoolYear: candidate.schoolYear,
      startDate: candidate.startDate,
      endDate: candidate.endDate,
      status: decision.initialStatus,
      populations: copyPopulation && sourceDoc?.populations ? sourceDoc.populations : {},
      revision: decision.nextRevision,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: uid,
    });
    writeAudit(tx, db, {
      actorId: uid,
      actorNameSnapshot: actorName(actor),
      actorRoleSnapshot: roleOf(actor),
      action: "ACADEMIC_YEAR_CREATED",
      category: AUDIT_CATEGORIES.system,
      targetType: "academic_year",
      targetId: candidate.schoolYear,
      metadata: {
        academicYearId: candidate.schoolYear,
        initialStatus: decision.initialStatus,
        startDate: candidate.startDate,
        endDate: candidate.endDate,
        revision: decision.nextRevision,
        copiedFrom: copyPopulation && sourceDoc ? sourceYear : null,
      },
    });
  });
  return {years: await listAcademicYears({includeVoided: data.includeVoided === true})};
}

export const createAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  try {
    return await createAcademicYearForActor(uid, actor, (request.data ?? {}) as Record<string, unknown>);
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export async function activateAcademicYearForActor(
  uid: string,
  actor: FirebaseFirestore.DocumentData,
  data: Record<string, unknown>,
  options?: AcademicYearRuntimeOptions,
) {
  const {now, extendedLifecycleEnabled} = resolveRuntimeOptions(options);
  if (!extendedLifecycleEnabled) {
    throw new HttpsError(
      "failed-precondition",
      "Extended academic year lifecycle activation is disabled until updated report analytics are deployed.",
    );
  }
  const {schoolYear} = parseSchoolYear(data.schoolYear);
  const expectedRevision = typeof data.expectedRevision === "number" ? data.expectedRevision : undefined;
  const todayManila = manilaTodayIso(now);
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(db.collection("counseling_population"));
    const existing = snapshot.docs.map((doc) => toAcademicYearRecord(doc.id, doc.data()));
    const target = existing.find((item) => item.schoolYear === schoolYear) ?? null;
    const {nextRevision} = validateAcademicYearActivation({
      target,
      existing,
      todayManila,
      expectedRevision,
    });
    tx.update(config(schoolYear), {
      status: "current",
      activatedAt: FieldValue.serverTimestamp(),
      activatedBy: uid,
      revision: nextRevision,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: uid,
    });
    writeAudit(tx, db, {
      actorId: uid,
      actorNameSnapshot: actorName(actor),
      actorRoleSnapshot: roleOf(actor),
      action: "ACADEMIC_YEAR_ACTIVATED",
      category: AUDIT_CATEGORIES.system,
      targetType: "academic_year",
      targetId: schoolYear,
      metadata: {academicYearId: schoolYear, revision: nextRevision, activatedOnManila: todayManila},
    });
  });
  return {years: await listAcademicYears({includeVoided: data.includeVoided === true})};
}

export const activateAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  try {
    return await activateAcademicYearForActor(uid, actor, (request.data ?? {}) as Record<string, unknown>);
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export const closeAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  try {
    const {schoolYear} = parseSchoolYear(request.data?.schoolYear);
    const expectedRevision = typeof request.data?.expectedRevision === "number"
      ? request.data.expectedRevision
      : undefined;
    const reference = config(schoolYear);
    await db.runTransaction(async (tx) => {
      const [snapshot, taggedAppointments] = await Promise.all([
        tx.get(reference),
        tx.get(db.collection("appointments").where("academicYearId", "==", schoolYear).limit(500)),
      ]);
      const data = snapshot.exists ? snapshot.data() ?? {} : null;
      const {nextRevision} = validateAcademicYearClose(data, expectedRevision);
      const popMap = data?.populations && typeof data.populations === "object" ? data.populations : {};
      tx.update(reference, {
        status: "closed",
        closedAt: FieldValue.serverTimestamp(),
        closedBy: uid,
        revision: nextRevision,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      });
      writeAudit(tx, db, {
        actorId: uid,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "ACADEMIC_YEAR_CLOSED",
        category: AUDIT_CATEGORIES.system,
        targetType: "academic_year",
        targetId: schoolYear,
        metadata: {
          academicYearId: schoolYear,
          revision: nextRevision,
          historicalAppointmentsCount: taggedAppointments.size,
          populationDepartmentsConfigured: Object.keys(popMap).length,
        },
      });
    });
    return {years: await listAcademicYears({includeVoided: request.data?.includeVoided === true})};
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export async function voidAcademicYearForActor(
  uid: string,
  actor: FirebaseFirestore.DocumentData,
  data: Record<string, unknown>,
  options?: AcademicYearRuntimeOptions,
) {
  const {extendedLifecycleEnabled} = resolveRuntimeOptions(options);
  if (!extendedLifecycleEnabled) {
    throw new HttpsError(
      "failed-precondition",
      "Voiding academic years is disabled until updated report analytics (Batch B2) are deployed, so legacy reports cannot misclassify voided years.",
    );
  }
  const {schoolYear} = parseSchoolYear(data.schoolYear);
  const reference = config(schoolYear);
  await db.runTransaction(async (tx) => {
    const preSnap = await tx.get(reference);
    if (!preSnap.exists) {
      throw new AcademicYearError("not-found", "Academic year not found.");
    }
    const raw = preSnap.data() ?? {};
    const record = toAcademicYearRecord(preSnap.id, raw);
    const bounds = manilaBounds(record.startDate, record.endDate);

    const [
      taggedAppts,
      scheduledInRangeAppts,
      createdInRangeAppts,
      taggedWalkIns,
      taggedReports,
    ] = await Promise.all([
      tx.get(db.collection("appointments").where("academicYearId", "==", schoolYear).limit(1)),
      tx.get(
        db.collection("appointments")
          .where("scheduledAt", ">=", bounds.start)
          .where("scheduledAt", "<", bounds.endExclusive)
          .limit(1),
      ),
      tx.get(
        db.collection("appointments")
          .where("createdAt", ">=", bounds.start)
          .where("createdAt", "<", bounds.endExclusive)
          .limit(1),
      ),
      tx.get(db.collection("walk_in_imports").where("academicYearId", "==", schoolYear).limit(1)),
      tx.get(db.collection("reports").where("academicYearId", "==", schoolYear).limit(1)),
    ]);

    const appointmentRefCount = taggedAppts.size + scheduledInRangeAppts.size + createdInRangeAppts.size;
    const {reason, nextRevision} = validateAcademicYearVoid({
      target: {...record, populations: raw.populations},
      confirmation: data.confirmation,
      reason: data.reason,
      expectedRevision: data.expectedRevision,
      appointmentRefCount,
      walkInImportRefCount: taggedWalkIns.size,
      reportRefCount: taggedReports.size,
    });

    const snapshotPayload = {
      schoolYear: record.schoolYear,
      startDate: record.startDate,
      endDate: record.endDate,
      status: record.status,
      revision: revisionOfAcademicYear(raw),
      populations: raw.populations ?? {},
      createdAt: raw.createdAt ?? null,
      createdBy: raw.createdBy ?? null,
    };

    tx.set(reference.collection("void_history").doc(`rev_${nextRevision}`), {
      ...snapshotPayload,
      voidRevision: nextRevision,
      voidReason: reason,
      voidedBy: uid,
      voidedAt: FieldValue.serverTimestamp(),
    });
    tx.update(reference, {
      status: "voided",
      voidedAt: FieldValue.serverTimestamp(),
      voidedBy: uid,
      voidReason: reason,
      voidedSnapshot: snapshotPayload,
      revision: nextRevision,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: uid,
    });
    writeAudit(tx, db, {
      actorId: uid,
      actorNameSnapshot: actorName(actor),
      actorRoleSnapshot: roleOf(actor),
      action: "ACADEMIC_YEAR_VOIDED",
      category: AUDIT_CATEGORIES.system,
      targetType: "academic_year",
      targetId: schoolYear,
      metadata: {
        academicYearId: schoolYear,
        previousStatus: record.status,
        revision: nextRevision,
        reason,
        hasSnapshot: true,
      },
    });
  });
  return {years: await listAcademicYears({includeVoided: data.includeVoided === true})};
}

export const voidAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireSuperAdmin(uid);
  try {
    return await voidAcademicYearForActor(uid, actor, (request.data ?? {}) as Record<string, unknown>);
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});

export const saveCounselingPopulation = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  const raw = request.data?.populations;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "Department populations are required.");
  }
  const populations: Record<string, number> = {};
  for (const department of REPORT_DEPARTMENTS) {
    const value = (raw as Record<string, unknown>)[department];
    if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 1000000) {
      throw new HttpsError("invalid-argument", `Enter a valid population for ${department}.`);
    }
    populations[department] = value as number;
  }
  try {
    const {schoolYear} = parseSchoolYear(request.data?.schoolYear);
    const ref = config(schoolYear);
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (!existing.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Create the academic year in Academic Year Management before saving department populations.",
        );
      }
      const status = parseStoredAcademicYearStatus(existing.data()?.status);
      if (status === "closed") {
        throw new HttpsError("failed-precondition", "Closed academic years are read-only.");
      }
      if (status === "voided") {
        throw new HttpsError("failed-precondition", "Voided academic years cannot be modified.");
      }
      if (status === "unknown") {
        throw new HttpsError("failed-precondition", "Academic year has an unrecognized status and cannot be modified.");
      }
      const nextRevision = revisionOfAcademicYear(existing.data()) + 1;
      tx.update(ref, {
        populations,
        revision: nextRevision,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      });
      writeAudit(tx, db, {
        actorId: uid,
        actorNameSnapshot: actorName(actor),
        actorRoleSnapshot: roleOf(actor),
        action: "ACADEMIC_YEAR_POPULATION_UPDATED",
        category: AUDIT_CATEGORIES.system,
        targetType: "academic_year",
        targetId: schoolYear,
        metadata: {academicYearId: schoolYear, revision: nextRevision},
      });
    });
    return readPopulationConfig(schoolYear);
  } catch (error) {
    rethrowAcademicYearError(error);
  }
});
