import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAdmin, requireUid, roleOf} from "./access";
import {AUDIT_CATEGORIES, actorName, writeAuditBatch} from "./audit";
import {
  AcademicCatalogIndex, CatalogPlan, CatalogRow, CatalogRowResult, CatalogValidation, ExistingRecord,
  PlannedRecord, validateCatalogRows,
} from "./academic_import_domain";

if (!getApps().length) initializeApp();

const MAX_ROWS = 1000;
const batchLimit = 450;
const LEVELS = ["colleges", "departments", "courses"] as const;
type Level = typeof LEVELS[number];

/** Test seam only: shrink batches and run code before each batch commit. */
export const academicImportTestHooks: {
  batchLimit?: number;
  beforeCommit?: (level: Level, chunk: number) => Promise<void>;
} = {};

/** The wire shape Task 5 parses. An unmapped column is absent from the row; a blank cell arrives as "". */
export type CatalogRowWire = {index: number; kind: "create" | "exists" | "error"; errors: string[];
  warnings: string[]; inventedDepartment?: string};

const ROW_FIELDS = ["college", "collegeCode", "department", "departmentCode", "course", "courseCode"] as const;

function database(): FirebaseFirestore.Firestore {
  return getFirestore();
}

function wireRow(result: CatalogRowResult): CatalogRowWire {
  if (!result.ok) return {index: result.index, kind: "error", errors: result.errors, warnings: []};
  return {index: result.index, kind: result.kind, errors: [], warnings: result.warnings,
    ...(result.invented ? {inventedDepartment: result.invented.department} : {})};
}

type Input = {fileName: string; sheetName: string; rows: CatalogRow[]};

function readInput(data: unknown): Input {
  const payload = (data ?? {}) as {fileName?: unknown; sheetName?: unknown; rows?: unknown};
  const rows = payload.rows;
  if (!Array.isArray(rows)) throw new HttpsError("invalid-argument", "Rows must be a list.");
  if (rows.length < 1) throw new HttpsError("invalid-argument", "The catalogue file has no rows.");
  if (rows.length > MAX_ROWS) {
    throw new HttpsError("invalid-argument", `A catalogue file may hold at most ${MAX_ROWS} rows. Split the file and import it in parts.`);
  }
  return {
    fileName: String(payload.fileName ?? "").slice(0, 200),
    sheetName: String(payload.sheetName ?? "").slice(0, 200),
    // Only the mapped roles are carried over, and an absent role stays absent: the domain tells an
    // unmapped column from a blank cell by the key's presence.
    rows: rows.map((raw) => {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
      const source = raw as Record<string, unknown>;
      const row: CatalogRow = {};
      for (const field of ROW_FIELDS) {
        if (Object.prototype.hasOwnProperty.call(source, field) && source[field] !== undefined) {
          row[field] = source[field];
        }
      }
      return row;
    }),
  };
}

function record(snapshot: FirebaseFirestore.QueryDocumentSnapshot, parent?: string): ExistingRecord {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    name: String(data.name ?? ""),
    code: String(data.code ?? ""),
    active: data.active === true || String(data.status ?? "").toUpperCase() === "ACTIVE",
    ...(parent ? {parentId: String(data[parent] ?? "")} : {}),
  };
}

async function loadIndex(): Promise<AcademicCatalogIndex> {
  const db = database();
  // Archived records are loaded too: naming one is an error row, and its code stays reserved.
  const [colleges, departments, courses] = await Promise.all(LEVELS.map((level) => db.collection(level).get()));
  return {
    colleges: colleges.docs.map((d) => record(d)),
    departments: departments.docs.map((d) => record(d, "collegeId")),
    courses: courses.docs.map((d) => record(d, "departmentId")),
  };
}

async function validate(input: Input): Promise<CatalogValidation> {
  return validateCatalogRows(input.rows, await loadIndex());
}

export const previewAcademicCatalogImport = onCall(async (request) => {
  const actorId = requireUid(request);
  await requireAdmin(actorId);
  const {results, counts} = await validate(readInput(request.data));
  return {rows: results.map(wireRow), counts};
});

type Allocated = {ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown>};

function resolveRef(reference: string, ids: Map<string, string>): string {
  return reference.startsWith("id:") ? reference.slice(3) : ids.get(reference.slice(4)) ?? "";
}

/** Doc ids for every planned record, so a child can carry its parent's id before anything is written. */
function allocate(plan: CatalogPlan, actorId: string, importId: string): Record<Level, Allocated[]> {
  const db = database();
  const ids = new Map<string, string>();
  const collegeOf = new Map<string, string>();
  const base = {active: true, status: "ACTIVE", createdBy: actorId, updatedBy: actorId, importId,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()};
  const common = (planned: PlannedRecord) => ({
    name: planned.name, code: planned.code,
    normalizedName: planned.name.toLowerCase(), normalizedCode: planned.code.toLowerCase(), ...base,
  });
  const out: Record<Level, Allocated[]> = {colleges: [], departments: [], courses: []};
  for (const level of LEVELS) {
    for (const planned of plan[level]) {
      const ref = db.collection(level).doc();
      ids.set(planned.key, ref.id);
      if (level === "colleges") {
        out.colleges.push({ref, data: common(planned)});
        continue;
      }
      if (level === "departments") {
        const collegeId = resolveRef(planned.parent, ids);
        collegeOf.set(`new:${planned.key}`, collegeId);
        out.departments.push({ref, data: {...common(planned), collegeId}});
        continue;
      }
      const departmentId = resolveRef(planned.parent, ids);
      out.courses.push({ref, data: {...common(planned),
        collegeId: collegeOf.get(planned.parent) ?? "", departmentId}});
    }
  }
  return out;
}

/** Existing departments keep their stored collegeId, which the plan does not carry. */
function fillStoredColleges(allocated: Record<Level, Allocated[]>, plan: CatalogPlan,
  index: AcademicCatalogIndex): void {
  const stored = new Map(index.departments.map((d) => [d.id, d.parentId ?? ""]));
  plan.courses.forEach((planned, position) => {
    const course = allocated.courses[position];
    if (course.data.collegeId) return;
    course.data.collegeId = stored.get(String(course.data.departmentId)) ?? "";
  });
}

export const importAcademicCatalog = onCall(async (request) => {
  const actorId = requireUid(request);
  const actor = await requireAdmin(actorId);
  const input = readInput(request.data);
  const index = await loadIndex();
  const {results, plan, counts} = validateCatalogRows(input.rows, index);
  const bad = results.flatMap((r) => (r.ok ? [] : [r]));
  if (bad.length) {
    throw new HttpsError("invalid-argument", `${bad.length} row(s) have errors. Fix them and try again.`,
      {rows: bad.map(wireRow)});
  }

  const db = database();
  const importRef = db.collection("academic_catalogue_imports").doc();
  const planned = {colleges: plan.colleges.length, departments: plan.departments.length, courses: plan.courses.length};
  await importRef.create({fileName: input.fileName, sheetName: input.sheetName, status: "pending",
    rowCount: input.rows.length, actorId, planned, counts: {colleges: 0, departments: 0, courses: 0},
    createdAt: FieldValue.serverTimestamp()});

  const allocated = allocate(plan, actorId, importRef.id);
  fillStoredColleges(allocated, plan, index);

  // Parents before children, so a child is never written against a college or department that is missing.
  const limit = academicImportTestHooks.batchLimit ?? batchLimit;
  const committed = {colleges: 0, departments: 0, courses: 0};
  let failed = false;
  for (const level of LEVELS) {
    if (failed) break;
    const writes = allocated[level];
    for (let start = 0; start < writes.length; start += limit) {
      const chunk = writes.slice(start, start + limit);
      const batch = db.batch();
      for (const write of chunk) batch.create(write.ref, write.data);
      try {
        if (academicImportTestHooks.beforeCommit) await academicImportTestHooks.beforeCommit(level, start / limit);
        await batch.commit();
      } catch {
        failed = true;
        break;
      }
      committed[level] += chunk.length;
    }
  }

  const final = db.batch();
  final.update(importRef, {status: failed ? "partial" : "complete", counts: committed,
    completedAt: FieldValue.serverTimestamp()});
  writeAuditBatch(final, db, {
    actorId, actorNameSnapshot: actorName(actor), actorRoleSnapshot: roleOf(actor) || "admin",
    action: "ACADEMIC_CATALOGUE_IMPORTED", category: AUDIT_CATEGORIES.userManagement,
    targetType: "academic_catalogue_import", targetId: importRef.id,
    metadata: {fileName: input.fileName, sheetName: input.sheetName, counts: committed, planned,
      rowCount: input.rows.length, rows: counts, ...(failed ? {partial: true} : {})},
  });
  await final.commit();

  if (failed) {
    return {importId: importRef.id, counts: committed, status: "partial",
      message: "The import stopped partway. The records committed so far are counted above; re-import the file to finish the rest."};
  }
  return {importId: importRef.id, counts: committed, status: "complete"};
});
