import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp, WriteBatch} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAdmin, requireUid, roleOf} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAuditBatch} from "./audit";
import {
  AcademicIndex, OfficialFields, RosterRowInput, StoredActivationCode, generateActivationCode, hashActivationCode,
  normalizeName, validateRosterRows,
} from "./student_roster_domain";

if (!getApps().length) initializeApp();

const MAX_ROWS = 1000;
const GET_ALL_CHUNK = 300;
const batchLimit = 450;

/** Test seam only: shrink batches and run code after classification. */
export const rosterTestHooks: {batchLimit?: number; afterClassify?: () => Promise<void>} = {};

export type IssuedCode = {studentNo: string; name: string; college: string; course: string; yearLevel: string;
  code: string; expiresAt: string};
export type PreviewRow = {index: number; studentNo: string; kind: "new" | "update" | "link" | "error";
  changes?: Record<string, {from: string; to: string}>; errors?: string[]};

type Doc = FirebaseFirestore.DocumentData;
type Classified = {
  index: number;
  studentNo: string;
  kind: PreviewRow["kind"];
  value?: OfficialFields;
  existing?: Doc;
  linkUid?: string;
  linkUser?: Doc;
  personalInfoExists?: boolean;
  changes?: Record<string, {from: string; to: string}>;
  errors?: string[];
};

function database(): FirebaseFirestore.Firestore {
  return getFirestore();
}

async function getAllChunked(refs: FirebaseFirestore.DocumentReference[]): Promise<FirebaseFirestore.DocumentSnapshot[]> {
  const out: FirebaseFirestore.DocumentSnapshot[] = [];
  for (let i = 0; i < refs.length; i += GET_ALL_CHUNK) {
    out.push(...await database().getAll(...refs.slice(i, i + GET_ALL_CHUNK)));
  }
  return out;
}

export async function loadAcademicIndex(): Promise<AcademicIndex> {
  const db = database();
  const [colleges, departments, courses] = await Promise.all([
    db.collection("colleges").where("active", "==", true).get(),
    db.collection("departments").where("active", "==", true).get(),
    db.collection("courses").where("active", "==", true).get(),
  ]);
  const departmentNames = new Map(departments.docs.map((d) => [d.id, String(d.data().name ?? "")]));
  return {
    colleges: colleges.docs.map((d) => ({id: d.id, name: String(d.data().name ?? ""), code: String(d.data().code ?? "")})),
    courses: courses.docs.map((d) => ({
      id: d.id, name: String(d.data().name ?? ""), code: String(d.data().code ?? ""),
      collegeId: String(d.data().collegeId ?? ""), departmentId: String(d.data().departmentId ?? ""),
      departmentName: departmentNames.get(String(d.data().departmentId ?? "")) ?? "",
    })),
  };
}

function readRows(data: unknown): RosterRowInput[] {
  const rows = (data as {rows?: unknown} | null)?.rows;
  if (!Array.isArray(rows)) throw new HttpsError("invalid-argument", "Rows must be a list.");
  if (rows.length < 1) throw new HttpsError("invalid-argument", "The roster file has no rows.");
  if (rows.length > MAX_ROWS) throw new HttpsError("invalid-argument", `Import at most ${MAX_ROWS} rows at a time.`);
  return rows.map((r) => (r && typeof r === "object" && !Array.isArray(r) ? r as RosterRowInput : {}));
}

const DIFF_FIELDS: [string, (v: OfficialFields) => string, (d: Doc) => string][] = [
  ["surname", (v) => v.surname, (d) => String(d.surname ?? "")],
  ["firstName", (v) => v.firstName, (d) => String(d.firstName ?? "")],
  ["middleName", (v) => v.middleName, (d) => String(d.middleName ?? "")],
  ["dateOfBirth", (v) => v.dateOfBirthKey, (d) => String(d.dateOfBirthKey ?? "")],
  ["college", (v) => v.college, (d) => String(d.college ?? "")],
  ["course", (v) => v.course, (d) => String(d.course ?? "")],
  ["yearLevel", (v) => v.yearLevel, (d) => String(d.yearLevel ?? "")],
];

async function classify(rows: RosterRowInput[]): Promise<Classified[]> {
  const db = database();
  const results = validateRosterRows(rows, await loadAcademicIndex());
  const valid = results.flatMap((r) => (r.ok ? [r] : []));
  const rosterSnaps = await getAllChunked(valid.map((r) => db.collection("student_roster").doc(r.value.studentKey)));
  const reservationSnaps = await getAllChunked(valid.map((r) => db.collection("student_id_reservations").doc(r.value.studentKey)));
  const reservedUids = reservationSnaps.map((s) => (s.exists ? String(s.data()?.userId ?? "") : ""));
  const userRefs = reservedUids.filter(Boolean).map((uid) => db.collection("users").doc(uid));
  const infoRefs = reservedUids.filter(Boolean).map((uid) => db.collection("student_personal_info").doc(uid));
  const userSnaps = new Map((await getAllChunked(userRefs)).map((s) => [s.id, s]));
  const infoSnaps = new Map((await getAllChunked(infoRefs)).map((s) => [s.id, s]));

  const byIndex = new Map<number, Classified>();
  valid.forEach((r, i) => {
    const {value} = r;
    const existing = rosterSnaps[i].exists ? rosterSnaps[i].data() : undefined;
    const reserved = reservationSnaps[i].exists;
    const uid = reservedUids[i];
    const base = {index: r.index, studentNo: value.studentNo, value, existing};
    if (existing && existing.activated === true) {
      byIndex.set(r.index, {...base, kind: "update", changes: diff(value, existing)});
    } else if (reserved) {
      if (!uid || !userSnaps.get(uid)?.exists) {
        byIndex.set(r.index, {...base, kind: "error", errors: ["Student No. is reserved by an account that cannot be linked."]});
      } else {
        byIndex.set(r.index, {...base, kind: "link", linkUid: uid, linkUser: userSnaps.get(uid)?.data() ?? {},
          personalInfoExists: infoSnaps.get(uid)?.exists === true});
      }
    } else if (existing) {
      byIndex.set(r.index, {...base, kind: "update", changes: diff(value, existing)});
    } else {
      byIndex.set(r.index, {...base, kind: "new"});
    }
  });
  return results.map((r) => {
    if (!r.ok) {
      const raw = (rows[r.index]?.studentNo);
      return {index: r.index, studentNo: typeof raw === "string" ? raw.trim() : "", kind: "error", errors: r.errors};
    }
    return byIndex.get(r.index) as Classified;
  });
}

function diff(value: OfficialFields, existing: Doc): Record<string, {from: string; to: string}> {
  const changes: Record<string, {from: string; to: string}> = {};
  for (const [field, next, prev] of DIFF_FIELDS) {
    if (next(value) !== prev(existing)) changes[field] = {from: prev(existing), to: next(value)};
  }
  return changes;
}

export const previewStudentRosterImport = onCall(async (request) => {
  const actorId = requireUid(request);
  await requireAdmin(actorId);
  const classified = await classify(readRows(request.data));
  const counts = {new: 0, update: 0, link: 0, error: 0};
  const out: PreviewRow[] = classified.map((c) => {
    counts[c.kind] += 1;
    return {index: c.index, studentNo: c.studentNo, kind: c.kind,
      ...(c.kind === "update" ? {changes: c.changes} : {}), ...(c.kind === "error" ? {errors: c.errors} : {})};
  });
  return {rows: out, counts};
});

// ------------------------------------------------------------------ codes

type MintedCode = {plain: string; stored: StoredActivationCode};

async function mintCode(): Promise<MintedCode> {
  const plain = generateActivationCode();
  return {plain, stored: await hashActivationCode(plain)};
}

function issued(info: Doc, minted: MintedCode): IssuedCode {
  return {
    studentNo: String(info.studentNo ?? ""),
    name: [info.firstName, info.middleName, info.surname].filter(Boolean).join(" "),
    college: String(info.college ?? ""), course: String(info.course ?? ""), yearLevel: String(info.yearLevel ?? ""),
    code: minted.plain, expiresAt: minted.stored.expiresAt.toISOString(),
  };
}

function storedCodeField(stored: StoredActivationCode): Record<string, unknown> {
  return {
    hash: stored.hash, salt: stored.salt,
    issuedAt: Timestamp.fromDate(stored.issuedAt), expiresAt: Timestamp.fromDate(stored.expiresAt),
  };
}

async function actorSnapshot(actorId: string): Promise<{actorNameSnapshot: string; actorRoleSnapshot: string}> {
  const profile = (await database().collection("users").doc(actorId).get()).data() ?? {};
  return {actorNameSnapshot: actorName(profile), actorRoleSnapshot: roleOf(profile) || "admin"};
}

/** Overwrites the activation code of every active, unactivated roster row among `keys`. Returns plain codes once. */
export async function issueCodesFor(keys: string[], actorId: string): Promise<IssuedCode[]> {
  const db = database();
  const unique = [...new Set(keys)];
  const snaps = await getAllChunked(unique.map((k) => db.collection("student_roster").doc(k)));
  const eligible = snaps.filter((s) => s.exists && s.data()?.status === "active" && s.data()?.activated !== true);
  const minted = await Promise.all(eligible.map(() => mintCode()));
  const codes = eligible.map((s, i) => issued(s.data() as Doc, minted[i]));
  if (!eligible.length) return codes;
  const actor = await actorSnapshot(actorId);
  const ops: ((b: WriteBatch) => void)[] = eligible.map((s, i) => (b) =>
    b.update(s.ref, {activationCode: storedCodeField(minted[i].stored), updatedAt: FieldValue.serverTimestamp()}));
  ops.push((b) => writeAuditBatch(b, db, {
    actorId, ...actor, action: "STUDENT_ACTIVATION_CODES_ISSUED", category: AUDIT_CATEGORIES.userManagement,
    targetType: "student_roster", metadata: {count: eligible.length},
  }));
  await commitOps(ops);
  return codes;
}

async function commitOps(ops: ((b: WriteBatch) => void)[]): Promise<void> {
  const db = database();
  for (let i = 0; i < ops.length; i += batchLimit) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + batchLimit)) op(batch);
    await batch.commit();
  }
}

// ------------------------------------------------------------------ import

function officialFields(v: OfficialFields): Record<string, unknown> {
  return {
    studentNo: v.studentNo, studentKey: v.studentKey, surname: v.surname, surnameNormalized: normalizeName(v.surname),
    firstName: v.firstName, middleName: v.middleName,
    dateOfBirth: Timestamp.fromDate(new Date(`${v.dateOfBirthKey}T00:00:00Z`)), dateOfBirthKey: v.dateOfBirthKey,
    collegeId: v.collegeId, college: v.college, courseId: v.courseId, course: v.course,
    departmentId: v.departmentId, department: v.department, yearLevel: v.yearLevel,
  };
}

function userAcademicFields(v: OfficialFields): Record<string, unknown> {
  return {
    schoolId: v.studentNo,
    dateOfBirth: Timestamp.fromDate(new Date(`${v.dateOfBirthKey}T00:00:00Z`)), dateOfBirthKey: v.dateOfBirthKey,
    collegeId: v.collegeId, courseId: v.courseId, departmentId: v.departmentId,
    department: v.department, course: v.course, yearLevel: v.yearLevel,
    populationRole: "student", updatedAt: FieldValue.serverTimestamp(),
  };
}

const PREVIOUS_FIELDS = ["schoolId", "dateOfBirthKey", "collegeId", "courseId", "departmentId", "department", "course", "yearLevel",
  "populationRole"];

type Unit = {ops: ((b: WriteBatch) => void)[]; kind: "new" | "updated" | "linked"; index: number; studentNo: string;
  code?: IssuedCode; previous?: Record<string, unknown>};

export const importStudentRoster = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const rows = readRows(request.data);
  const fileName = String((request.data as {fileName?: unknown})?.fileName ?? "").slice(0, 200);
  const classified = await classify(rows);
  const bad = classified.filter((c) => c.kind === "error");
  if (bad.length) {
    throw new HttpsError("invalid-argument", `${bad.length} row(s) have errors. Fix them and try again.`,
      {rows: bad.map((c) => ({index: c.index, studentNo: c.studentNo, errors: c.errors}))});
  }
  if (rosterTestHooks.afterClassify) await rosterTestHooks.afterClassify();

  const db = database();
  const importRef = db.collection("student_roster_imports").doc();
  const newRows = classified.filter((c) => c.kind === "new");
  const minted = await Promise.all(newRows.map(() => mintCode()));
  const actorMeta = {actorNameSnapshot: String(actor.name ?? "") || (await actorSnapshot(actorId)).actorNameSnapshot,
    actorRoleSnapshot: roleOf(actor) || "admin"};

  const units: Unit[] = classified.map((c) => {
    const v = c.value as OfficialFields;
    const rosterRef = db.collection("student_roster").doc(v.studentKey);
    const base = {index: c.index, studentNo: v.studentNo};
    if (c.kind === "new") {
      const m = minted[newRows.indexOf(c)];
      return {...base, kind: "new", code: issued(v as unknown as Doc, m), ops: [(b: WriteBatch) => b.create(rosterRef, {
        ...officialFields(v), status: "active", activated: false, userId: null,
        activationCode: storedCodeField(m.stored), importId: importRef.id,
        createdBy: actorId, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      })]};
    }
    if (c.kind === "link") {
      const uid = c.linkUid as string;
      const prev = c.linkUser ?? {};
      return {...base, kind: "linked", previous: {studentNo: v.studentNo, userId: uid,
        previous: Object.fromEntries(PREVIOUS_FIELDS.map((f) => [f, prev[f] === undefined ? null : prev[f]]))},
      ops: [
        (b: WriteBatch) => b.set(rosterRef, {
          ...officialFields(v), status: c.existing?.status ?? "active", activated: true, userId: uid, activationCode: null,
          linkedAt: FieldValue.serverTimestamp(), importId: importRef.id,
          ...(c.existing ? {} : {createdBy: actorId, createdAt: FieldValue.serverTimestamp()}),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true}),
        (b: WriteBatch) => b.set(db.collection("users").doc(uid), {
          ...userAcademicFields(v), rosterLinked: true, personalInfoRequired: !c.personalInfoExists,
        }, {merge: true}),
      ]};
    }
    const uid = c.existing?.activated === true ? String(c.existing.userId ?? "") : "";
    return {...base, kind: "updated", ops: [
      (b: WriteBatch) => b.update(rosterRef, {...officialFields(v), importId: importRef.id, updatedAt: FieldValue.serverTimestamp()}),
      ...(uid ? [(b: WriteBatch) => b.set(db.collection("users").doc(uid), userAcademicFields(v), {merge: true})] : []),
    ]};
  });

  // Never split a row across batches.
  const limit = rosterTestHooks.batchLimit ?? batchLimit;
  const groups: Unit[][] = [];
  let size = 0;
  for (const u of units) {
    if (!groups.length || size + u.ops.length > limit) {
      groups.push([]);
      size = 0;
    }
    groups[groups.length - 1].push(u);
    size += u.ops.length;
  }

  await importRef.create({fileName, status: "pending", rowCount: rows.length, actorId,
    counts: {new: 0, updated: 0, linked: 0}, createdAt: FieldValue.serverTimestamp()});

  const counts = {new: 0, updated: 0, linked: 0};
  const codes: IssuedCode[] = [];
  const previous: Record<string, unknown>[] = [];
  let failedRows: {index: number; studentNo: string}[] = [];
  for (let g = 0; g < groups.length; g++) {
    const batch = db.batch();
    for (const u of groups[g]) for (const op of u.ops) op(batch);
    try {
      await batch.commit();
    } catch {
      failedRows = groups.slice(g).flat().map((u) => ({index: u.index, studentNo: u.studentNo}));
      break;
    }
    for (const u of groups[g]) {
      counts[u.kind] += 1;
      if (u.code) codes.push(u.code);
      if (u.previous) previous.push(u.previous);
    }
  }

  const partial = failedRows.length > 0;
  const final = db.batch();
  final.update(importRef, {status: partial ? "partial" : "complete", counts, ...(partial ? {failedRows} : {}),
    completedAt: FieldValue.serverTimestamp()});
  writeAuditBatch(final, db, {
    actorId, ...actorMeta, action: "STUDENT_ROSTER_IMPORTED", category: AUDIT_CATEGORIES.userManagement,
    targetType: "student_roster_import", targetId: importRef.id,
    metadata: {fileName, counts, rowCount: rows.length, linkedPreviousValues: previous, ...(partial ? {partial: true} : {})},
  });
  await final.commit();
  if (partial) {
    return {status: "partial", importId: importRef.id, counts, codes, failedRows,
      message: "Import stopped partway. Rows saved so far are listed; fix the file and re-import the rest."};
  }
  return {status: "complete", importId: importRef.id, counts, codes};
});
