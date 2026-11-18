import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  configuredSuperAdminUid,
  requireClinical,
  requireSuperAdmin,
  requireUid,
  roleOf,
} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAuditBatch} from "./audit";

if (!getApps().length) initializeApp();
const db = getFirestore();

type ImportRow = {
  fullName?: unknown;
  studentId?: unknown;
  department?: unknown;
  course?: unknown;
  yearLevel?: unknown;
  loggedAt?: unknown;
};

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";

const academicYearFor = (date: Date) => {
  const start = date.getUTCMonth() >= 5 ? date.getUTCFullYear() : date.getUTCFullYear() - 1;
  return `${start}-${start + 1}`;
};

function parseDate(value: unknown): Date {
  if (typeof value !== "string" || !value.trim()) return new Date();
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", `Invalid log-in date: ${value}`);
  }
  return date;
}

type CollegeIndex = {
  byKey: Map<string, string>;
};

async function loadCollegeIndex(): Promise<CollegeIndex> {
  const snapshot = await db.collection("colleges").get();
  const byKey = new Map<string, string>();
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.active === false) continue;
    const keys = [
      doc.id,
      text(data.name),
      text(data.code),
      text(data.normalizedName),
      text(data.normalizedCode),
    ];
    for (const key of keys) {
      const normalized = key.toLocaleLowerCase("en-US");
      if (normalized) byKey.set(normalized, doc.id);
    }
  }
  return {byKey};
}

function resolveCollegeId(index: CollegeIndex, department: string): string {
  return index.byKey.get(department.toLocaleLowerCase("en-US")) ?? "";
}

export const importWalkInAppointments = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireClinical(uid);
  const role = roleOf(actor);
  const isSuperAdmin = role === "admin" && uid === configuredSuperAdminUid();
  if (role === "admin" && !isSuperAdmin) {
    throw new HttpsError("permission-denied", "Super-administrator access is required.");
  }
  const assignedCollegeIds = new Set(
    Array.isArray(actor.assignedCollegeIds)
      ? actor.assignedCollegeIds.filter((id): id is string => typeof id === "string" && id.trim().length > 0)
      : [],
  );
  if (role === "counselor" && assignedCollegeIds.size === 0) {
    throw new HttpsError("permission-denied", "Your counselor account does not have any assigned colleges.");
  }

  const rawRows = request.data?.rows;
  if (!Array.isArray(rawRows) || rawRows.length < 1 || rawRows.length > 500) {
    throw new HttpsError("invalid-argument", "Import between 1 and 500 rows.");
  }

  const collegeIndex = await loadCollegeIndex();
  const rows = rawRows.map((raw: ImportRow, index: number) => {
    const fullName = text(raw.fullName);
    const studentId = text(raw.studentId);
    const department = text(raw.department);
    const course = text(raw.course);
    const yearLevel = text(raw.yearLevel);
    if (!fullName || !studentId || !department || !course || !yearLevel) {
      throw new HttpsError("invalid-argument", `Row ${index + 1} is missing a required field.`);
    }
    if ([fullName, studentId, department, course, yearLevel].some((value) => value.length > 160)) {
      throw new HttpsError("invalid-argument", `Row ${index + 1} contains a value that is too long.`);
    }
    const collegeId = resolveCollegeId(collegeIndex, department);
    if (role === "counselor" && (!collegeId || !assignedCollegeIds.has(collegeId))) {
      throw new HttpsError("permission-denied", "You can only import walk-in appointments for your assigned colleges.");
    }
    const loggedAt = parseDate(raw.loggedAt);
    return {
      fullName,
      studentId,
      department,
      collegeId,
      course,
      yearLevel,
      loggedAt,
    };
  });

  const fileName = text(request.data?.fileName) || "Manual walk-in entries";
  const importReference = db.collection("walk_in_imports").doc();
  const chunkSize = 400;
  const headerBatch = db.batch();
  headerBatch.set(importReference, {
    fileName: fileName.slice(0, 180),
    rowCount: rows.length,
    importedBy: uid,
    importedAt: FieldValue.serverTimestamp(),
  });
  writeAuditBatch(headerBatch, db, {
    actorId: uid,
    actorNameSnapshot: actorName(actor),
    actorRoleSnapshot: role,
    action: "WALK_IN_APPOINTMENTS_IMPORTED",
    category: AUDIT_CATEGORIES.appointments,
    targetType: "walk_in_import",
    targetId: importReference.id,
    metadata: {rowCount: rows.length, collegeScoped: role === "counselor"},
  });
  await headerBatch.commit();

  for (let i = 0; i < rows.length; i += chunkSize) {
    const batch = db.batch();
    for (const row of rows.slice(i, i + chunkSize)) {
      const reference = db.collection("appointments").doc();
      batch.set(reference, {
        userId: "",
        fullName: row.fullName,
        studentId: row.studentId,
        department: row.department,
        ...(row.collegeId ? {collegeId: row.collegeId} : {}),
        course: row.course,
        yearLevel: row.yearLevel,
        scheduledAt: row.loggedAt,
        academicYearId: academicYearFor(row.loggedAt),
        scheduledTime: "",
        location: "Counseling office walk-in",
        status: "completed",
        concern: "Office walk-in counseling appointment",
        contactNumber: "",
        email: "",
        preferredContactMethod: "",
        createdAt: row.loggedAt,
        source: "walk_in_import",
        importId: importReference.id,
        importFileName: fileName.slice(0, 180),
        importedBy: uid,
        importedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  return {imported: rows.length};
});

export const listWalkInImports = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireSuperAdmin(uid);
  const snapshot = await db.collection("walk_in_imports")
    .orderBy("importedAt", "desc")
    .limit(100)
    .get();
  const auditBatch = db.batch();
  writeAuditBatch(auditBatch, db, {
    actorId: uid,
    actorNameSnapshot: actorName(actor),
    actorRoleSnapshot: roleOf(actor),
    action: "WALK_IN_IMPORTS_VIEWED",
    category: AUDIT_CATEGORIES.security,
    targetType: "walk_in_import",
    targetId: "list",
    metadata: {count: snapshot.size},
  });
  await auditBatch.commit();
  return {
    files: snapshot.docs.map((doc) => {
      const data = doc.data();
      const importedAt = data.importedAt as FirebaseFirestore.Timestamp | undefined;
      return {
        id: doc.id,
        fileName: text(data.fileName) || "Imported walk-in entries",
        rowCount: Number(data.rowCount ?? 0),
        importedAtMillis: importedAt?.toMillis() ?? Date.now(),
        archived: data.archived === true,
      };
    }),
  };
});

export const deleteWalkInImport = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireSuperAdmin(uid);
  const importId = text(request.data?.importId);
  if (!importId || importId.length > 120) {
    throw new HttpsError("invalid-argument", "A valid imported file is required.");
  }
  const importReference = db.collection("walk_in_imports").doc(importId);
  const importSnapshot = await importReference.get();
  if (!importSnapshot.exists) {
    throw new HttpsError("not-found", "This imported file no longer exists.");
  }
  const appointments = await db.collection("appointments")
    .where("importId", "==", importId)
    .limit(500)
    .get();
  const chunkSize = 400;
  for (let i = 0; i < appointments.docs.length; i += chunkSize) {
    const batch = db.batch();
    appointments.docs.slice(i, i + chunkSize).forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  const tailBatch = db.batch();
  tailBatch.delete(importReference);
  writeAuditBatch(tailBatch, db, {
    actorId: uid,
    actorNameSnapshot: actorName(actor),
    actorRoleSnapshot: roleOf(actor),
    action: "WALK_IN_IMPORT_DELETED",
    category: AUDIT_CATEGORIES.appointments,
    targetType: "walk_in_import",
    targetId: importId,
    metadata: {deletedRows: appointments.size},
  });
  await tailBatch.commit();
  console.info("Deleted walk-in import", {
    importId,
    deletedRows: appointments.size,
    actorId: uid,
    actorName: actorName(actor),
  });
  return {deleted: appointments.size};
});

export const archiveWalkInImport = onCall(async (request) => {
  const uid = requireUid(request);
  const actor = await requireSuperAdmin(uid);
  const importId = text(request.data?.importId);
  const archived = request.data?.archived === true;
  if (!importId || importId.length > 120) {
    throw new HttpsError("invalid-argument", "A valid imported file is required.");
  }
  const reference = db.collection("walk_in_imports").doc(importId);
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "This imported file no longer exists.");
  }
  const batch = db.batch();
  batch.update(reference, {
    archived,
    ...(archived
      ? {archivedAt: FieldValue.serverTimestamp()}
      : {archivedAt: FieldValue.delete()}),
    archivedBy: archived ? uid : FieldValue.delete(),
  });
  writeAuditBatch(batch, db, {
    actorId: uid,
    actorNameSnapshot: actorName(actor),
    actorRoleSnapshot: roleOf(actor),
    action: archived ? "WALK_IN_IMPORT_ARCHIVED" : "WALK_IN_IMPORT_RESTORED",
    category: AUDIT_CATEGORIES.appointments,
    targetType: "walk_in_import",
    targetId: importId,
    metadata: {archived},
  });
  await batch.commit();
  return {archived};
});
