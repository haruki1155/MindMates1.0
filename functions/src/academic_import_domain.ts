// Pure catalogue-import domain logic: no Firestore access.
//
// Rules enforced here (see the feature's global constraints):
//  - names are unique within their parent (colleges are global, departments within a college,
//    courses within a department); codes stay unique collection-wide;
//  - a name match means ALREADY EXISTS: the row is skipped, never updated, so re-running a file is a no-op;
//  - codes given by the file are used as given; only derived codes get a digit appended;
//  - an unmapped Department column (absent key) invents one department per college, while a mapped but
//    blank cell is an error row.

const NAME_MIN = 2;
const NAME_MAX = 120;
const CODE_MIN = 1;
const CODE_MAX = 30;
const STOP_WORDS = new Set(["of", "and", "in", "the"]);

export type CatalogRow = {
  college?: unknown; collegeCode?: unknown;
  department?: unknown; departmentCode?: unknown;
  course?: unknown; courseCode?: unknown;
};

export type CatalogRowResult =
  | {index: number; ok: true; kind: "create" | "exists"; warnings: string[]; invented?: {department: string}}
  | {index: number; ok: false; errors: string[]};

/** A stored record. `parentId` is the collegeId of a department and the departmentId of a course. */
export type ExistingRecord = {id: string; name: string; code: string; active: boolean; parentId?: string};

export type AcademicCatalogIndex = {
  colleges: ExistingRecord[];
  departments: ExistingRecord[];
  courses: ExistingRecord[];
};

/** A record to create. `parent` is a reference: `id:<docId>` for a stored parent, `new:<key>` for a planned one. */
export type PlannedRecord = {key: string; name: string; code: string; parent: string};

export type CatalogPlan = {colleges: PlannedRecord[]; departments: PlannedRecord[]; courses: PlannedRecord[]};

export type CatalogValidation = {
  results: CatalogRowResult[];
  plan: CatalogPlan;
  counts: {create: number; exists: number; error: number; colleges: number; departments: number; courses: number};
};

/** Case- and whitespace-insensitive comparison key for names and codes. */
export function normalizeKey(value: string): string {
  return String(value ?? "").trim().replace(/\s+/g, " ").toLowerCase();
}

function cleanText(value: unknown): string {
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
}

/** Initials of the significant words, uppercased; words already written as acronyms are kept whole. */
export function deriveCode(name: string): string {
  const words = cleanText(name).split(/[^A-Za-z0-9]+/).filter(Boolean)
    .filter((word) => !STOP_WORDS.has(word.toLowerCase()));
  const code = words.map((word) => (word.length > 1 && word === word.toUpperCase() ? word : word[0])).join("").toUpperCase();
  const fallback = cleanText(name).replace(/[^A-Za-z0-9]/g, "").toUpperCase().slice(0, 3);
  return (code || fallback || "X").slice(0, CODE_MAX);
}

type Level = {
  label: "College" | "Department" | "Course";
  prefix: string;
  /** `${parentRef}\u0000${nameKey}` -> stored record. */
  byName: Map<string, ExistingRecord>;
  /** normalized code -> the record that owns it. */
  byCode: Map<string, {nameKey: string; name: string}>;
  /** `${parentRef}\u0000${nameKey}` -> planned record. */
  pending: Map<string, PlannedRecord>;
  plan: PlannedRecord[];
};

function buildLevel(label: Level["label"], prefix: string, records: ExistingRecord[], parented: boolean): Level {
  const level: Level = {label, prefix, byName: new Map(), byCode: new Map(), pending: new Map(), plan: []};
  for (const record of records) {
    const parent = parented ? `id:${record.parentId ?? ""}` : "";
    level.byName.set(`${parent}\u0000${normalizeKey(record.name)}`, record);
    const code = normalizeKey(record.code);
    // Archived records keep their code reserved, so a new record can never shadow one.
    if (code && !level.byCode.has(code)) level.byCode.set(code, {nameKey: normalizeKey(record.name), name: record.name});
  }
  return level;
}

function uniqueDerivedCode(level: Level, name: string): string {
  const base = deriveCode(name);
  if (!level.byCode.has(normalizeKey(base))) return base;
  for (let suffix = 2; ; suffix++) {
    const tail = String(suffix);
    const candidate = `${base.slice(0, CODE_MAX - tail.length)}${tail}`;
    if (!level.byCode.has(normalizeKey(candidate))) return candidate;
  }
}

type Resolution = {ref: string; created: boolean} | null;

/**
 * Resolves one name under `parent` to a stored or planned record, appending to `errors`/`warnings`.
 * `duplicateInFile` makes a second mention of the same name under the same parent an error, which is how
 * a repeated course is caught while a repeated college or department is simply reused.
 */
function resolve(level: Level, parent: string, name: string, code: string, duplicateInFile: boolean,
  errors: string[], warnings: string[]): Resolution {
  const label = level.label;
  const nameKey = normalizeKey(name);
  const mapKey = `${parent}\u0000${nameKey}`;
  const codeKey = normalizeKey(code);
  const stored = level.byName.get(mapKey);
  if (stored) {
    if (!stored.active) {
      errors.push(`${label} “${stored.name}” is archived — restore it first.`);
      return null;
    }
    if (codeKey) {
      const owner = level.byCode.get(codeKey);
      if (owner && owner.nameKey !== nameKey) {
        errors.push(`${label} code “${code}” is already used by “${owner.name}”.`);
        return null;
      }
      if (codeKey !== normalizeKey(stored.code)) {
        warnings.push(`${label} code “${code}” differs from the stored code “${stored.code}”; the stored code was kept.`);
      }
    }
    return {ref: `id:${stored.id}`, created: false};
  }
  const pending = level.pending.get(mapKey);
  if (pending) {
    if (duplicateInFile) {
      errors.push(`${label} “${name}” appears more than once under the same parent in this file.`);
      return null;
    }
    if (codeKey && codeKey !== normalizeKey(pending.code)) {
      errors.push(`${label} “${name}” is given two different codes in this file.`);
      return null;
    }
    return {ref: `new:${pending.key}`, created: false};
  }
  let finalCode = code;
  if (codeKey) {
    const owner = level.byCode.get(codeKey);
    if (owner) {
      errors.push(`${label} code “${code}” is already used by “${owner.name}”.`);
      return null;
    }
  } else {
    finalCode = uniqueDerivedCode(level, name);
  }
  const record: PlannedRecord = {key: `${level.prefix}${level.plan.length + 1}`, name, code: finalCode, parent};
  level.byCode.set(normalizeKey(finalCode), {nameKey, name});
  level.pending.set(mapKey, record);
  level.plan.push(record);
  return {ref: `new:${record.key}`, created: true};
}

function checkName(label: string, value: string, errors: string[]): boolean {
  if (value.length < NAME_MIN || value.length > NAME_MAX) {
    errors.push(`${label} name must be ${NAME_MIN} to ${NAME_MAX} characters.`);
    return false;
  }
  return true;
}

function checkCode(label: string, value: string, errors: string[]): boolean {
  if (!value) return true;
  if (value.length < CODE_MIN || value.length > CODE_MAX) {
    errors.push(`${label} code must be ${CODE_MIN} to ${CODE_MAX} characters.`);
    return false;
  }
  return true;
}

/** True when the role was mapped to a column at all: an unmapped role is absent from the row. */
function mapped(row: CatalogRow, field: keyof CatalogRow): boolean {
  return Object.prototype.hasOwnProperty.call(row, field) && row[field] !== undefined && row[field] !== null;
}

export function validateCatalogRows(rows: CatalogRow[], index: AcademicCatalogIndex): CatalogValidation {
  const colleges = buildLevel("College", "c", index.colleges, false);
  const departments = buildLevel("Department", "d", index.departments, true);
  const courses = buildLevel("Course", "k", index.courses, true);
  const counts = {create: 0, exists: 0, error: 0, colleges: 0, departments: 0, courses: 0};
  const results: CatalogRowResult[] = rows.map((raw, position) => {
    const row = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
    const errors: string[] = [];
    const warnings: string[] = [];
    const collegeName = cleanText(row.college);
    const courseName = cleanText(row.course);
    const departmentMapped = mapped(row, "department");
    const departmentName = cleanText(row.department);
    const collegeCode = cleanText(row.collegeCode);
    const departmentCode = cleanText(row.departmentCode);
    const courseCode = cleanText(row.courseCode);

    if (!collegeName) errors.push("College is required.");
    else checkName("College", collegeName, errors);
    if (!courseName) errors.push("Course is required.");
    else checkName("Course", courseName, errors);
    if (departmentMapped && !departmentName) {
      errors.push("Department is blank. Fill the cell in, or unmap the Department column to create " +
        "one department per college.");
    } else if (departmentName) {
      checkName("Department", departmentName, errors);
    }
    checkCode("College", collegeCode, errors);
    checkCode("Department", departmentCode, errors);
    checkCode("Course", courseCode, errors);
    if (errors.length) return {index: position, ok: false, errors};

    const college = resolve(colleges, "", collegeName, collegeCode, false, errors, warnings);
    if (!college) return {index: position, ok: false, errors};
    // With no Department column, every college gets one department of its own name.
    const invented = departmentMapped ? "" :
      (colleges.byName.get(`\u0000${normalizeKey(collegeName)}`)?.name ?? collegeName);
    const department = resolve(departments, college.ref, departmentMapped ? departmentName : invented,
      departmentCode, false, errors, warnings);
    if (!department) return {index: position, ok: false, errors};
    const course = resolve(courses, department.ref, courseName, courseCode, true, errors, warnings);
    if (!course) return {index: position, ok: false, errors};

    return {index: position, ok: true, kind: course.created ? "create" : "exists", warnings,
      ...(invented ? {invented: {department: invented}} : {})};
  });
  for (const result of results) {
    if (!result.ok) counts.error += 1;
    else if (result.kind === "create") counts.create += 1;
    else counts.exists += 1;
  }
  counts.colleges = colleges.plan.length;
  counts.departments = departments.plan.length;
  counts.courses = courses.plan.length;
  return {results, plan: {colleges: colleges.plan, departments: departments.plan, courses: courses.plan}, counts};
}
