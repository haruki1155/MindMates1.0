import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldPath, FieldValue, getFirestore, Timestamp, WriteBatch} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAdmin, requireUid, roleOf} from "./access";
import {canonicalLoginId} from "./account_recovery";
import {AUDIT_CATEGORIES, actorName, writeAudit, writeAuditBatch} from "./audit";
import {
  AcademicIndex, OfficialFields, RosterRowInput, StoredActivationCode, generateActivationCode, hashActivationCode,
  normalizeName, normalizeYearLevel, validateRosterRows,
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
  changes?: Record<string, {from: string; to: string}>; errors?: string[]; warnings?: string[]};

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
  warnings?: string[];
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
        const linkUser = userSnaps.get(uid)?.data() ?? {};
        byIndex.set(r.index, {...base, kind: "link", linkUid: uid, linkUser,
          personalInfoExists: infoSnaps.get(uid)?.exists === true, warnings: linkWarnings(value, linkUser)});
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

/**
 * A reservation only proves that someone typed this Student No. into their profile. When the account's
 * own name or date of birth disagrees with the registrar row, linking hands the row to a possibly
 * different person — so the preview says so. It stays a warning, never an error: linking must proceed.
 */
function linkWarnings(value: OfficialFields, user: Doc): string[] {
  const accountName = [user.firstName, user.middleName, user.lastName].map((v) => String(v ?? "").trim())
    .filter(Boolean).join(" ") || String(user.name ?? "").trim();
  const rosterName = [value.firstName, value.middleName, value.surname].filter(Boolean).join(" ");
  const nameDiffers = normalizeName(String(user.lastName ?? "")) !== normalizeName(value.surname) ||
    normalizeName(String(user.firstName ?? "")) !== normalizeName(value.firstName);
  const accountDob = String(user.dateOfBirthKey ?? "");
  const dobDiffers = accountDob !== "" && accountDob !== value.dateOfBirthKey;
  if (!nameDiffers && !dobDiffers) return [];
  const parts: string[] = [];
  if (nameDiffers) parts.push(`name "${accountName || "(blank)"}" (roster: "${rosterName}")`);
  if (dobDiffers) parts.push(`date of birth ${accountDob} (roster: ${value.dateOfBirthKey})`);
  return [`The existing account reserving this Student No. has a different ${parts.join(" and ")}. ` +
    "Confirm this is the same student before importing."];
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
      ...(c.kind === "update" ? {changes: c.changes} : {}), ...(c.kind === "error" ? {errors: c.errors} : {}),
      ...(c.warnings?.length ? {warnings: c.warnings} : {})};
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

// The linked account's own values, snapshotted before the roster row takes over. The identity fields
// (name, date of birth) are kept alongside the academic ones so a wrongful link is reconstructable.
const PREVIOUS_FIELDS = ["schoolId", "firstName", "middleName", "lastName", "name", "dateOfBirthKey", "collegeId", "courseId",
  "departmentId", "department", "course", "yearLevel", "populationRole"];

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

// ------------------------------------------------------------------ management

const PAGE_SIZE = 50;
const INFO_SCAN_CHUNK = 100;
const INFO_SCAN_LIMIT = 1000;
const MAX_REASON = 500;
const LIST_STATUSES = ["notActivated", "activated", "infoIncomplete", "deactivated"] as const;
type ListStatus = typeof LIST_STATUSES[number];
const EDITABLE_FIELDS = ["surname", "firstName", "middleName", "dateOfBirth", "college", "course", "yearLevel"] as const;

export type RosterRowView = {studentNo: string; name: string; college: string; course: string; yearLevel: string;
  activated: boolean; status: string; personalInfoComplete: boolean; userId: string | null};

function payload(data: unknown): Record<string, unknown> {
  return data && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : {};
}

function optionalString(raw: Record<string, unknown>, key: string, max = 200): string {
  const value = raw[key];
  if (value === undefined || value === null || value === "") return "";
  if (typeof value !== "string" || value.trim().length > max) throw new HttpsError("invalid-argument", `${key} is invalid.`);
  return value.trim();
}

function canonicalOrNull(value: unknown): string | null {
  try {
    return canonicalLoginId(value);
  } catch {
    return null;
  }
}

function requireStudentKey(raw: Record<string, unknown>): string {
  const key = canonicalOrNull(raw.studentNo);
  if (!key) throw new HttpsError("invalid-argument", "Enter a valid Student No.");
  return key;
}

function adminMeta(actor: Doc): {actorNameSnapshot: string; actorRoleSnapshot: string} {
  return {actorNameSnapshot: actorName(actor), actorRoleSnapshot: roleOf(actor) || "admin"};
}

function isoOf(value: unknown): string {
  return value instanceof Timestamp ? value.toDate().toISOString() : "";
}

function rowView(data: Doc, user: Doc | undefined): RosterRowView {
  const userId = typeof data.userId === "string" && data.userId ? data.userId : null;
  const activated = data.activated === true;
  return {
    studentNo: String(data.studentNo ?? ""),
    name: [data.firstName, data.middleName, data.surname].map((v) => String(v ?? "").trim()).filter(Boolean).join(" "),
    college: String(data.college ?? ""), course: String(data.course ?? ""), yearLevel: String(data.yearLevel ?? ""),
    activated, status: String(data.status ?? ""),
    personalInfoComplete: Boolean(activated && userId && user && user.personalInfoRequired !== true),
    userId,
  };
}

async function linkedUsers(rows: Doc[]): Promise<Map<string, Doc>> {
  const db = database();
  const uids = [...new Set(rows.map((r) => (r.activated === true && typeof r.userId === "string" ? r.userId : "")).filter(Boolean))];
  const snaps = await getAllChunked(uids.map((uid) => db.collection("users").doc(uid)));
  return new Map(snaps.filter((s) => s.exists).map((s) => [s.id, s.data() as Doc]));
}

type ListFilters = {collegeId: string; courseId: string; yearLevel: string; status: ListStatus | ""};

function matchesFilters(data: Doc, f: ListFilters): boolean {
  if (f.collegeId && data.collegeId !== f.collegeId) return false;
  if (f.courseId && data.courseId !== f.courseId) return false;
  if (f.yearLevel && data.yearLevel !== f.yearLevel) return false;
  if (f.status === "notActivated") return data.status === "active" && data.activated !== true;
  if (f.status === "activated" || f.status === "infoIncomplete") return data.status === "active" && data.activated === true;
  if (f.status === "deactivated") return data.status === "deactivated";
  return true;
}

function encodeToken(values: string[]): string {
  return Buffer.from(JSON.stringify(values), "utf8").toString("base64url");
}

function decodeToken(token: string, length: number): string[] {
  try {
    const values = JSON.parse(Buffer.from(token, "base64url").toString("utf8")) as unknown;
    if (Array.isArray(values) && values.length === length && values.every((v) => typeof v === "string")) return values;
  } catch {
    // fall through
  }
  throw new HttpsError("invalid-argument", "The page token is invalid.");
}

export const listStudentRoster = onCall(async (request) => {
  await requireAdmin(requireUid(request));
  const raw = payload(request.data);
  const search = optionalString(raw, "search", 100);
  const rawYear = optionalString(raw, "yearLevel", 40);
  const yearLevel = rawYear ? normalizeYearLevel(rawYear) : "";
  if (yearLevel === null) throw new HttpsError("invalid-argument", "yearLevel is invalid.");
  const status = optionalString(raw, "status", 40);
  if (status && !(LIST_STATUSES as readonly string[]).includes(status)) {
    throw new HttpsError("invalid-argument", "status is invalid.");
  }
  const filters: ListFilters = {collegeId: optionalString(raw, "collegeId"), courseId: optionalString(raw, "courseId"),
    yearLevel, status: status as ListStatus | ""};
  const pageToken = optionalString(raw, "pageToken", 2000);
  const db = database();
  const collection = db.collection("student_roster");

  // An exact Student No. hit wins over a surname search.
  const exactKey = search ? canonicalOrNull(search) : null;
  if (exactKey && !pageToken) {
    const snap = await collection.doc(exactKey).get();
    if (snap.exists) {
      const data = snap.data() as Doc;
      if (!matchesFilters(data, filters)) return {rows: [], nextPageToken: null};
      const users = await linkedUsers([data]);
      const view = rowView(data, users.get(String(data.userId ?? "")));
      if (filters.status === "infoIncomplete" && view.personalInfoComplete) return {rows: [], nextPageToken: null};
      return {rows: [view], nextPageToken: null};
    }
  }

  let query: FirebaseFirestore.Query = collection;
  if (filters.collegeId) query = query.where("collegeId", "==", filters.collegeId);
  if (filters.courseId) query = query.where("courseId", "==", filters.courseId);
  if (filters.yearLevel) query = query.where("yearLevel", "==", filters.yearLevel);
  if (filters.status === "notActivated") query = query.where("status", "==", "active").where("activated", "==", false);
  if (filters.status === "activated" || filters.status === "infoIncomplete") {
    query = query.where("status", "==", "active").where("activated", "==", true);
  }
  if (filters.status === "deactivated") query = query.where("status", "==", "deactivated");

  const prefix = search ? normalizeName(search) : "";
  let cursorOf: (snap: FirebaseFirestore.QueryDocumentSnapshot) => string[];
  if (prefix) {
    query = query.where("surnameNormalized", ">=", prefix).where("surnameNormalized", "<", `${prefix}\uf8ff`)
      .orderBy("surnameNormalized").orderBy(FieldPath.documentId());
    cursorOf = (s) => [String(s.data().surnameNormalized ?? ""), s.id];
  } else {
    query = query.orderBy(FieldPath.documentId());
    cursorOf = (s) => [s.id];
  }
  let cursor = pageToken ? decodeToken(pageToken, prefix ? 2 : 1) : null;

  if (filters.status !== "infoIncomplete") {
    const page = await (cursor ? query.startAfter(...cursor) : query).limit(PAGE_SIZE + 1).get();
    const docs = page.docs.slice(0, PAGE_SIZE);
    const users = await linkedUsers(docs.map((d) => d.data()));
    return {
      rows: docs.map((d) => rowView(d.data(), users.get(String(d.data().userId ?? "")))),
      nextPageToken: page.docs.length > PAGE_SIZE ? encodeToken(cursorOf(docs[docs.length - 1])) : null,
    };
  }

  // infoIncomplete depends on the linked user, so scan activated rows in bounded chunks.
  const matches: {view: RosterRowView; cursor: string[]}[] = [];
  let scanned = 0;
  let exhausted = false;
  while (matches.length <= PAGE_SIZE && scanned < INFO_SCAN_LIMIT) {
    const chunk = await (cursor ? query.startAfter(...cursor) : query).limit(INFO_SCAN_CHUNK).get();
    const users = await linkedUsers(chunk.docs.map((d) => d.data()));
    for (const d of chunk.docs) {
      scanned += 1;
      cursor = cursorOf(d);
      const user = users.get(String(d.data().userId ?? ""));
      if (user?.personalInfoRequired === true) {
        matches.push({view: rowView(d.data(), user), cursor});
        if (matches.length > PAGE_SIZE) break;
      }
    }
    if (chunk.docs.length < INFO_SCAN_CHUNK) {
      exhausted = matches.length <= PAGE_SIZE;
      break;
    }
  }
  if (matches.length > PAGE_SIZE) {
    return {rows: matches.slice(0, PAGE_SIZE).map((m) => m.view), nextPageToken: encodeToken(matches[PAGE_SIZE - 1].cursor)};
  }
  return {rows: matches.map((m) => m.view), nextPageToken: exhausted || !cursor ? null : encodeToken(cursor)};
});

export const listLegacyStudentsNotInRoster = onCall(async (request) => {
  await requireAdmin(requireUid(request));
  const snap = await database().collection("users").where("populationRole", "==", "student")
    .select("schoolId", "name", "firstName", "lastName", "rosterLinked", "accountStatus").get();
  const rows = snap.docs
    .filter((d) => d.data().rosterLinked !== true && d.data().accountStatus !== "revoked")
    .map((d) => {
      const data = d.data();
      const name = String(data.name ?? "").trim() ||
        [data.firstName, data.lastName].map((v) => String(v ?? "").trim()).filter(Boolean).join(" ");
      return {userId: d.id, schoolId: String(data.schoolId ?? ""), name};
    })
    .sort((a, b) => a.schoolId.localeCompare(b.schoolId));
  return {rows};
});

export const updateStudentRosterRecord = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const raw = payload(request.data);
  const key = requireStudentKey(raw);
  const fields = payload(raw.fields);
  const names = Object.keys(fields);
  if (!names.length || names.some((n) => !(EDITABLE_FIELDS as readonly string[]).includes(n))) {
    throw new HttpsError("invalid-argument", `Only ${EDITABLE_FIELDS.join(", ")} can be edited.`);
  }
  const db = database();
  const rosterRef = db.collection("student_roster").doc(key);
  const index = await loadAcademicIndex();

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(rosterRef);
    if (!snap.exists) throw new HttpsError("not-found", "That Student No. is not in the roster.");
    const live = snap.data() as Doc;
    const merged: RosterRowInput = {
      studentNo: live.studentNo, surname: live.surname, firstName: live.firstName, middleName: live.middleName,
      dateOfBirth: live.dateOfBirthKey, college: live.college, course: live.course, yearLevel: live.yearLevel,
      ...fields,
    };
    const [result] = validateRosterRows([merged], index);
    if (!result.ok) throw new HttpsError("invalid-argument", "Please correct the record.", {errors: result.errors});
    const v = result.value;
    const uid = live.activated === true && typeof live.userId === "string" ? live.userId : "";
    const userRef = uid ? db.collection("users").doc(uid) : null;
    const user = userRef ? await transaction.get(userRef) : null;
    const changes = diff(v, live);
    transaction.update(rosterRef, {...officialFields(v), updatedAt: FieldValue.serverTimestamp(), updatedBy: actorId});
    if (userRef && user?.exists) transaction.set(userRef, userAcademicFields(v), {merge: true});
    writeAudit(transaction, db, {
      actorId, ...adminMeta(actor), action: "STUDENT_ROSTER_RECORD_UPDATED", category: AUDIT_CATEGORIES.userManagement,
      targetType: "student_roster", targetId: key, metadata: {studentNo: v.studentNo, userId: uid || null, changes},
    });
  });
  return {ok: true};
});

function authErrorCode(error: unknown): string {
  return String((error as {code?: string})?.code ?? "");
}

/** Disables or enables an Auth user; returns false when the user does not exist. */
async function setAuthDisabled(uid: string, disabled: boolean): Promise<boolean> {
  try {
    await getAuth().updateUser(uid, {disabled});
    if (disabled) await getAuth().revokeRefreshTokens(uid);
    return true;
  } catch (error) {
    if (authErrorCode(error) === "auth/user-not-found") return false;
    throw error;
  }
}

export const setStudentRosterStatus = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const raw = payload(request.data);
  const key = requireStudentKey(raw);
  const status = raw.status;
  if (status !== "active" && status !== "deactivated") throw new HttpsError("invalid-argument", "status is invalid.");
  const db = database();
  const rosterRef = db.collection("student_roster").doc(key);
  const uid = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(rosterRef);
    if (!snap.exists) throw new HttpsError("not-found", "That Student No. is not in the roster.");
    const live = snap.data() as Doc;
    const linked = live.activated === true && typeof live.userId === "string" ? live.userId : "";
    transaction.update(rosterRef, {status, updatedAt: FieldValue.serverTimestamp(), updatedBy: actorId});
    writeAudit(transaction, db, {
      actorId, ...adminMeta(actor), action: "STUDENT_ROSTER_STATUS_CHANGED", category: AUDIT_CATEGORIES.userManagement,
      targetType: "student_roster", targetId: key,
      metadata: {studentNo: String(live.studentNo ?? key), from: String(live.status ?? ""), to: status, userId: linked || null},
    });
    return linked;
  });
  if (uid) await setAuthDisabled(uid, status === "deactivated");
  return {ok: true};
});

export const resetStudentActivationLock = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const key = requireStudentKey(payload(request.data));
  const db = database();
  const batch = db.batch();
  batch.delete(db.collection("student_activation_attempts").doc(key));
  writeAuditBatch(batch, db, {
    actorId, ...adminMeta(actor), action: "STUDENT_ACTIVATION_LOCK_RESET", category: AUDIT_CATEGORIES.userManagement,
    targetType: "student_roster", targetId: key, metadata: {studentKey: key},
  });
  await batch.commit();
  return {ok: true};
});

export const listStudentRosterImports = onCall(async (request) => {
  await requireAdmin(requireUid(request));
  const db = database();
  const snap = await db.collection("student_roster_imports").orderBy("createdAt", "desc").limit(100).get();
  const actorIds = [...new Set(snap.docs.map((d) => String(d.data().actorId ?? "")).filter(Boolean))];
  const actors = new Map((await getAllChunked(actorIds.map((id) => db.collection("users").doc(id))))
    .map((s) => [s.id, s.exists ? actorName(s.data() as Doc) : "Administrator"]));
  return {imports: snap.docs.map((d) => {
    const data = d.data();
    const counts = (data.counts ?? {}) as Record<string, unknown>;
    return {
      id: d.id, fileName: String(data.fileName ?? ""),
      counts: {new: Number(counts.new ?? 0), updated: Number(counts.updated ?? 0), linked: Number(counts.linked ?? 0)},
      importedByName: actors.get(String(data.actorId ?? "")) ?? "Administrator",
      importedAt: isoOf(data.createdAt),
    };
  })};
});

export const backfillStudentInfoRequirement = onCall({timeoutSeconds: 540}, async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const db = database();
  const students = (await db.collection("users").where("populationRole", "==", "student")
    .select("personalInfoRequired", "rosterLinked", "accountStatus").get()).docs
    .filter((d) => d.data().accountStatus !== "revoked");
  const candidates = students.filter((d) => d.data().personalInfoRequired !== true);
  const infos = await getAllChunked(candidates.map((d) => db.collection("student_personal_info").doc(d.id)));
  const toFlag = candidates.filter((_, i) => !infos[i].exists);
  const counts = {flagged: toFlag.length, notInRoster: students.filter((d) => d.data().rosterLinked !== true).length};
  const ops: ((b: WriteBatch) => void)[] = toFlag.map((d) => (b: WriteBatch) =>
    b.update(d.ref, {personalInfoRequired: true, updatedAt: FieldValue.serverTimestamp()}));
  // One audit per call, written even when nothing was flagged; it lands in the last batch.
  ops.push((b) => writeAuditBatch(b, db, {
    actorId, ...adminMeta(actor), action: "STUDENT_INFO_REQUIREMENT_BACKFILLED", category: AUDIT_CATEGORIES.userManagement,
    targetType: "student_roster", metadata: counts,
  }));
  await commitOps(ops);
  return counts;
});

export const issueStudentActivationCodes = onCall(async (request) => {
  const actorId = requireUid(request);
  await requireAdmin(actorId);
  const list = payload(request.data).studentNos;
  if (!Array.isArray(list) || list.length < 1 || list.length > MAX_ROWS) {
    throw new HttpsError("invalid-argument", `Choose 1 to ${MAX_ROWS} Student Nos.`);
  }
  const db = database();
  const skipped: {studentNo: string; reason: string}[] = [];
  const keyed = new Map<string, string>();
  for (const entry of list) {
    const key = canonicalOrNull(entry);
    if (!key) skipped.push({studentNo: typeof entry === "string" ? entry.trim().slice(0, 60) : "", reason: "Invalid Student No."});
    else if (!keyed.has(key)) keyed.set(key, String(entry).trim());
  }
  const keys = [...keyed.keys()];
  const snaps = await getAllChunked(keys.map((k) => db.collection("student_roster").doc(k)));
  const eligible: string[] = [];
  snaps.forEach((s, i) => {
    const data = s.data();
    if (!s.exists || !data) skipped.push({studentNo: keyed.get(keys[i]) ?? keys[i], reason: "Not in the roster."});
    else if (data.activated === true) skipped.push({studentNo: String(data.studentNo ?? keys[i]), reason: "Already activated."});
    else if (data.status !== "active") skipped.push({studentNo: String(data.studentNo ?? keys[i]), reason: "Deactivated."});
    else eligible.push(keys[i]);
  });
  const codes = eligible.length ? await issueCodesFor(eligible, actorId) : [];
  // Rows that changed between the check and the write.
  const issuedNos = new Set(codes.map((c) => canonicalOrNull(c.studentNo)));
  for (const key of eligible) {
    if (!issuedNos.has(key)) skipped.push({studentNo: keyed.get(key) ?? key, reason: "No longer eligible."});
  }
  return {codes, skipped};
});

export const revokeStudentActivation = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const raw = payload(request.data);
  const key = requireStudentKey(raw);
  const reason = typeof raw.reason === "string" ? raw.reason.trim() : "";
  if (!reason || reason.length > MAX_REASON) {
    throw new HttpsError("invalid-argument", `A reason of at most ${MAX_REASON} characters is required.`);
  }
  const db = database();
  const rosterRef = db.collection("student_roster").doc(key);
  const reservationRef = db.collection("student_id_reservations").doc(key);
  const pre = (await rosterRef.get()).data();
  if (!pre) throw new HttpsError("not-found", "That Student No. is not in the roster.");
  if (pre.activated !== true) throw new HttpsError("failed-precondition", "This Student No. has not been activated.");
  const uid = typeof pre.userId === "string" ? pre.userId : "";

  // Cut off the claimant first so a failure later never leaves them signed in.
  let wasEnabled = false;
  if (uid) {
    try {
      wasEnabled = !(await getAuth().getUser(uid)).disabled;
    } catch (error) {
      if (authErrorCode(error) !== "auth/user-not-found") throw error;
    }
    await setAuthDisabled(uid, true);
  }

  const minted = await mintCode();
  try {
    await db.runTransaction(async (transaction) => {
      const userRef = uid ? db.collection("users").doc(uid) : null;
      const [snap, reservation, user] = await Promise.all([
        transaction.get(rosterRef), transaction.get(reservationRef), userRef ? transaction.get(userRef) : Promise.resolve(null),
      ]);
      const live = snap.data();
      if (!live || live.activated !== true || String(live.userId ?? "") !== uid) {
        throw new HttpsError("failed-precondition", "The roster row changed. Refresh and try again.");
      }
      transaction.update(rosterRef, {
        activated: false, userId: null, consumedActivationCode: null, activationCode: storedCodeField(minted.stored),
        ...(uid ? {revokedUserIds: FieldValue.arrayUnion(uid)} : {}),
        revokedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), updatedBy: actorId,
      });
      if (uid && reservation.exists && reservation.data()?.userId === uid) transaction.delete(reservationRef);
      if (userRef && user?.exists) {
        transaction.update(userRef, {accountStatus: "revoked", rosterLinked: false,
          revokedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
      }
      writeAudit(transaction, db, {
        actorId, ...adminMeta(actor), action: "STUDENT_ACTIVATION_REVOKED", category: AUDIT_CATEGORIES.userManagement,
        targetType: "student_roster", targetId: key,
        metadata: {studentNo: String(live.studentNo ?? key), userId: uid || null, reason},
      });
    });
  } catch (error) {
    if (uid && wasEnabled) await setAuthDisabled(uid, false).catch(() => undefined);
    throw error;
  }
  return {code: issued(pre, minted)};
});
