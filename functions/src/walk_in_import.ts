import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {actorName} from "./audit";

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

async function requireClinicalAccess(uid: string): Promise<void> {
  const data = (await db.collection("users").doc(uid).get()).data() ?? {};
  const role = text(data.accessRole) || text(data.role);
  if (role !== "counselor" && role !== "admin") {
    throw new HttpsError("permission-denied", "Counselor or administrator access is required.");
  }
}

export const importWalkInAppointments = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireClinicalAccess(uid);
  const rawRows = request.data?.rows;
  if (!Array.isArray(rawRows) || rawRows.length < 1 || rawRows.length > 500) {
    throw new HttpsError("invalid-argument", "Import between 1 and 500 rows.");
  }

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
    const loggedAt = parseDate(raw.loggedAt);
    return {
      fullName,
      studentId,
      department,
      course,
      yearLevel,
      loggedAt,
    };
  });

  const fileName = text(request.data?.fileName) || "Manual walk-in entries";
  const importReference = db.collection("walk_in_imports").doc();
  const batch = db.batch();
  batch.set(importReference, {
    fileName: fileName.slice(0, 180),
    rowCount: rows.length,
    importedBy: uid,
    importedAt: FieldValue.serverTimestamp(),
  });
  for (const row of rows) {
    const reference = db.collection("appointments").doc();
    batch.set(reference, {
      userId: "",
      fullName: row.fullName,
      studentId: row.studentId,
      department: row.department,
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
  return {imported: rows.length};
});

async function requireAdmin(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const snapshot = await db.collection("users").doc(uid).get();
  const data = snapshot.data() ?? {};
  const role = text(data.accessRole) || text(data.role);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  return data;
}

export const listWalkInImports = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
  const snapshot = await db.collection("walk_in_imports")
    .orderBy("importedAt", "desc")
    .limit(100)
    .get();
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
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  const actor = await requireAdmin(uid);
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
  const batch = db.batch();
  appointments.docs.forEach((doc) => batch.delete(doc.ref));
  batch.delete(importReference);
  await batch.commit();
  console.info("Deleted walk-in import", {
    importId,
    deletedRows: appointments.size,
    actorId: uid,
    actorName: actorName(actor),
  });
  return {deleted: appointments.size};
});

export const archiveWalkInImport = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  await requireAdmin(uid);
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
  await reference.update({
    archived,
    ...(archived
      ? {archivedAt: FieldValue.serverTimestamp()}
      : {archivedAt: FieldValue.delete()}),
    archivedBy: archived ? uid : FieldValue.delete(),
  });
  return {archived};
});
