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
  isValidIsoDate,
  manilaCurrentSchoolStartYear,
  manilaTodayIso,
  parseAcademicYearInput,
  parseOptionalExpectedRevision,
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
    exists: snapshot.exists,
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

function sanitizePopulationsMap(raw: unknown): Record<string, number> {
  const populations: Record<string, number> = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return populations;
  }
  for (const department of REPORT_DEPARTMENTS) {
    const value = (raw as Record<string, unknown>)[department];
    if (typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 1000000) {
      populations[department] = value;
    }
  }
  return populations;
}

function manilaBounds(startDate: string, endDate: string): {start: Timestamp; endExclusive: Timestamp} {
  if (!isValidIsoDate(startDate) || !isValidIsoDate(endDate) || startDate > endDate) {
    throw new AcademicYearError("failed-precondition", "Stored academic year dates are invalid.");
  }
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
  return {
    years: await listAcademicYears({includeVoided}),
    extendedLifecycleEnabled: resolveRuntimeOptions().extendedLifecycleEnabled,
  };
});

function parseOptionalReinstateReason(value: unknown): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new AcademicYearError("invalid-argument", "reinstateReason must be a string.");
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  if (trimmed.length > 500) {
    throw new AcademicYearError("invalid-argument", "Reinstatement reason must be 500 characters or fewer.");
  }
  return trimmed;
}

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
  const expectedRevision = parseOptionalExpectedRevision(data.expectedRevision);
  const reinstateReason = parseOptionalReinstateReason(data.reinstateReason);
  const sourceYearRaw = text(data.copyFrom);
  const copyPopulation = data.copyPopulation === true;
  const sourceYear = copyPopulation
    ? parseSchoolYear(sourceYearRaw).schoolYear
    : "";
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(db.collection("counseling_population"));
    const existing = snapshot.docs.map((doc) => toAcademicYearRecord(doc.id, doc.data()));
    const decision = decideAcademicYearCreate({
      candidate,
      existing,
      todayManila,
      extendedLifecycleEnabled,
      expectedRevision,
    });
    let copiedPopulations: Record<string, number> = {};
    if (copyPopulation) {
      const sourceSnap = snapshot.docs.find((doc) => doc.id === sourceYear);
      if (!sourceSnap) {
        throw new AcademicYearError("not-found", `Source academic year ${sourceYear} was not found.`);
      }
      const sourceStatus = parseStoredAcademicYearStatus(sourceSnap.data().status);
      if (sourceStatus === "voided" || sourceStatus === "unknown") {
        throw new AcademicYearError(
          "failed-precondition",
          `Cannot copy populations from academic year ${sourceYear} (${sourceStatus}).`,
        );
      }
      copiedPopulations = sanitizePopulationsMap(sourceSnap.data().populations);
    }
    const targetRef = config(candidate.schoolYear);
    if (decision.kind === "reinstate") {
      const priorSnap = snapshot.docs.find((doc) => doc.id === candidate.schoolYear);
      const priorData = priorSnap?.data() ?? {};
      const voidRev = decision.previousVoidRevision ?? 0;
      // Append-only reinstatement record; never overwrite prior void_history/rev_<N> snapshots.
      tx.set(targetRef.collection("reinstate_history").doc(`rev_${decision.nextRevision}`), {
        schoolYear: candidate.schoolYear,
        reinstateRevision: decision.nextRevision,
        priorVoidRevision: voidRev,
        reinstateReason,
        priorVoidReason: priorData.voidReason ?? null,
        priorVoidedAt: priorData.voidedAt ?? null,
        priorVoidedBy: priorData.voidedBy ?? null,
        reinstatedAt: FieldValue.serverTimestamp(),
        reinstatedBy: uid,
      });
      tx.update(targetRef, {
        schoolYear: candidate.schoolYear,
        startDate: candidate.startDate,
        endDate: candidate.endDate,
        status: decision.initialStatus,
        populations: copiedPopulations,
        revision: decision.nextRevision,
        reinstatedFromVoidRevision: voidRev,
        lastReinstateReason: reinstateReason ?? FieldValue.delete(),
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
          reinstateReason,
          revision: decision.nextRevision,
          copiedFrom: copyPopulation ? sourceYear : null,
        },
      });
      return;
    }

    tx.set(targetRef, {
      schoolYear: candidate.schoolYear,
      startDate: candidate.startDate,
      endDate: candidate.endDate,
      status: decision.initialStatus,
      populations: copiedPopulations,
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
        copiedFrom: copyPopulation ? sourceYear : null,
      },
    });
  });
  return {
    years: await listAcademicYears({includeVoided: data.includeVoided === true}),
    extendedLifecycleEnabled,
  };
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
  const expectedRevision = parseOptionalExpectedRevision(data.expectedRevision);
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
  return {
    years: await listAcademicYears({includeVoided: data.includeVoided === true}),
    extendedLifecycleEnabled,
  };
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

export async function closeAcademicYearForActor(
  uid: string,
  actor: FirebaseFirestore.DocumentData,
  data: Record<string, unknown>,
  options?: AcademicYearRuntimeOptions,
) {
  const {now, extendedLifecycleEnabled} = resolveRuntimeOptions(options);
  const {schoolYear} = parseSchoolYear(data.schoolYear);
  const todayManila = manilaTodayIso(now);
  const reference = config(schoolYear);
  await db.runTransaction(async (tx) => {
    const [snapshot, taggedAppointments] = await Promise.all([
      tx.get(reference),
      tx.get(db.collection("appointments").where("academicYearId", "==", schoolYear).limit(500)),
    ]);
    const raw = snapshot.exists ? snapshot.data() ?? {} : null;
    const record = raw ? toAcademicYearRecord(snapshot.id, raw) : null;
    const {nextRevision} = validateAcademicYearClose({
      target: record,
      todayManila,
      confirmation: data.confirmation,
      expectedRevision: data.expectedRevision,
    });
    const popMap = raw?.populations && typeof raw.populations === "object" ? raw.populations : {};
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
        closedOnManila: todayManila,
        historicalAppointmentsCount: taggedAppointments.size,
        populationDepartmentsConfigured: Object.keys(popMap).length,
      },
    });
  });
  return {
    years: await listAcademicYears({includeVoided: data.includeVoided === true}),
    extendedLifecycleEnabled,
  };
}

export const closeAcademicYear = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireActiveAdmin(uid);
  try {
    return await closeAcademicYearForActor(uid, actor, (request.data ?? {}) as Record<string, unknown>);
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
  return {
    years: await listAcademicYears({includeVoided: data.includeVoided === true}),
    extendedLifecycleEnabled,
  };
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
