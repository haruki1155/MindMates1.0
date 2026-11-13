// Pure catalogue-import domain logic: no Firestore access.
//
// Rules enforced here (see the feature's global constraints):
//  - names are unique within their parent (colleges are global, departments within a college,
//    courses within a department); codes stay unique collection-wide;
//  - a name match means ALREADY EXISTS: the row is skipped, never updated, so re-running a file is a no-op;
//  - codes given by the file are used as given and are reserved before any code is derived, so a sparse
//    Code column reads the same whatever order the rows arrive in;
//  - an unmapped Department column (absent key) invents one department per college, while a mapped but
//    blank cell is an error row.

const NAME_MIN = 2;
const NAME_MAX = 120;
const CODE_MIN = 1;
const CODE_MAX = 30;
const ACRONYM_MAX = 4;
const SHORT_NAME_CODE = 4;
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

/**
 * Initials of the significant words, uppercased (`College of Pharmacy` → `CP`).
 * A short word already written as an acronym inside a mixed-case name is kept whole, which is what makes
 * `BS Information Technology` → `BSIT`. A name written entirely in capitals carries no such signal — a
 * registrar export is often all upper case — so it is read as initials like any other name.
 * A name of one significant word would yield a single letter, which makes a useless code, so it falls
 * back to the name's first four characters (`NURSING` → `NURS`).
 */
export function deriveCode(name: string): string {
  const clean = cleanText(name);
  const shouting = clean === clean.toUpperCase();
  const words = clean.split(/[^A-Za-z0-9]+/).filter(Boolean)
    .filter((word) => !STOP_WORDS.has(word.toLowerCase()));
  const acronym = (word: string) =>
    !shouting && word.length > 1 && word.length <= ACRONYM_MAX && word === word.toUpperCase();
  const code = words.map((word) => (acronym(word) ? word : word[0])).join("").toUpperCase();
  const letters = clean.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
  return (code.length >= 2 ? code : letters.slice(0, SHORT_NAME_CODE) || code || "X").slice(0, CODE_MAX);
}

type LevelName = "colleges" | "departments" | "courses";

/** One mention of a name in the file: the row that named it and the code that row gave, if any. */
type Mention = {row: number; code: string};

type Group = {
  key: string;
  name: string;
  nameKey: string;
  parent: string;
  mentions: Mention[];
  code: string;
  blocked: boolean;
  used: boolean;
};

type Level = {
  label: "College" | "Department" | "Course";
  prefix: string;
  /** `${parentRef}\u0000${nameKey}` -> stored record. */
  storedByName: Map<string, ExistingRecord>;
  /**
   * normalized code -> the record that will actually hold it: a stored record under its stored code, or
   * a planned group. Only an owner can be blamed for a collision.
   */
  codeOwner: Map<string, {id: string; name: string}>;
  /**
   * Codes derivation must stay away from although nobody will write them — a code the file gave for a
   * record that already exists. Such a code is never persisted (the stored code is kept and the row only
   * warns), so it must never be attributed to anyone either.
   */
  reserved: Set<string>;
  /** `${parentRef}\u0000${nameKey}` -> planned group. */
  groups: Map<string, Group>;
  order: Group[];
};

function buildLevel(label: Level["label"], prefix: string, records: ExistingRecord[], parented: boolean): Level {
  const level: Level = {label, prefix, storedByName: new Map(), codeOwner: new Map(), reserved: new Set(),
    groups: new Map(), order: []};
  for (const stored of records) {
    const parent = parented ? `id:${stored.parentId ?? ""}` : "";
    level.storedByName.set(`${parent}\u0000${normalizeKey(stored.name)}`, stored);
    const code = normalizeKey(stored.code);
    // Archived records keep their code too, so a new record can never shadow one.
    if (code && !level.codeOwner.has(code)) level.codeOwner.set(code, {id: stored.id, name: stored.name});
  }
  return level;
}

function taken(level: Level, code: string): boolean {
  const codeKey = normalizeKey(code);
  return level.codeOwner.has(codeKey) || level.reserved.has(codeKey);
}

function freeDerivedCode(level: Level, name: string): string {
  const base = deriveCode(name);
  if (!taken(level, base)) return base;
  for (let suffix = 2; ; suffix++) {
    const tail = String(suffix);
    const candidate = `${base.slice(0, CODE_MAX - tail.length)}${tail}`;
    if (!taken(level, candidate)) return candidate;
  }
}

/** Where one of a row's three names landed: a stored record, or a group of rows planning a new one. */
type Resolution = {ref: string; level: Level; code: string; stored?: ExistingRecord; group?: Group};

/**
 * Resolves one name under `parent` to a stored record or a planned group, without touching codes:
 * codes are assigned only once every row has been read. `duplicateInFile` makes a second mention of the
 * same name under the same parent an error, which is how a repeated course is caught while a repeated
 * college or department is simply reused.
 */
function resolveName(level: Level, parent: string, name: string, code: string, row: number,
  duplicateInFile: boolean, errors: string[]): Resolution | null {
  const nameKey = normalizeKey(name);
  const mapKey = `${parent}\u0000${nameKey}`;
  const stored = level.storedByName.get(mapKey);
  if (stored) {
    if (!stored.active) {
      errors.push(`${level.label} “${stored.name}” is archived — restore it first.`);
      return null;
    }
    return {ref: `id:${stored.id}`, level, code, stored};
  }
  const existing = level.groups.get(mapKey);
  if (existing) {
    if (duplicateInFile) {
      errors.push(`${level.label} “${name}” appears more than once under the same parent in this file.`);
      return null;
    }
    existing.mentions.push({row, code});
    return {ref: `new:${existing.key}`, level, code, group: existing};
  }
  const group: Group = {key: `${level.prefix}${level.order.length + 1}`, name, nameKey, parent,
    mentions: [{row, code}], code: "", blocked: false, used: false};
  level.groups.set(mapKey, group);
  level.order.push(group);
  return {ref: `new:${group.key}`, level, code, group};
}

/**
 * Pass two, step one: the codes the file gave for records it is creating. Those are the only file codes
 * anybody will write, so they are the only ones that take ownership — and the only ones that can be
 * blamed when two names claim the same code.
 */
function claimGivenCodes(level: Level, rowErrors: string[][]): void {
  for (const group of level.order) {
    const given = group.mentions.filter((mention) => mention.code);
    if (!given.length) continue;
    const first = given[0];
    for (const mention of given.slice(1)) {
      if (normalizeKey(mention.code) !== normalizeKey(first.code)) {
        rowErrors[mention.row].push(`${level.label} “${group.name}” is given two different codes in this file.`);
      }
    }
    const codeKey = normalizeKey(first.code);
    const owner = level.codeOwner.get(codeKey);
    if (owner) {
      group.blocked = true;
      for (const mention of group.mentions) {
        rowErrors[mention.row].push(`${level.label} code “${first.code}” is already used by “${owner.name}”.`);
      }
      continue;
    }
    group.code = first.code;
    level.codeOwner.set(codeKey, {id: group.key, name: group.name});
  }
}

/**
 * Pass two, step two: derivation. Every code the file named — for a new record or for a stored one — is
 * already off the table by now, so an invented code can never take a code the file spoke for.
 */
function deriveMissingCodes(level: Level): void {
  for (const group of level.order) {
    if (group.code || group.blocked) continue;
    group.code = freeDerivedCode(level, group.name);
    level.codeOwner.set(normalizeKey(group.code), {id: group.key, name: group.name});
  }
}

function checkName(label: string, value: string, errors: string[]): void {
  if (value.length < NAME_MIN || value.length > NAME_MAX) {
    errors.push(`${label} name must be ${NAME_MIN} to ${NAME_MAX} characters.`);
  }
}

function checkCode(label: string, value: string, errors: string[]): void {
  if (value && (value.length < CODE_MIN || value.length > CODE_MAX)) {
    errors.push(`${label} code must be ${CODE_MIN} to ${CODE_MAX} characters.`);
  }
}

/** True when the role was mapped to a column at all: an unmapped role is absent from the row. */
function mapped(row: CatalogRow, field: keyof CatalogRow): boolean {
  return Object.prototype.hasOwnProperty.call(row, field) && row[field] !== undefined && row[field] !== null;
}

type RowState = {index: number; refs: Resolution[]; invented: string; resolved: boolean};

export function validateCatalogRows(rows: CatalogRow[], index: AcademicCatalogIndex): CatalogValidation {
  const levels: Record<LevelName, Level> = {
    colleges: buildLevel("College", "c", index.colleges, false),
    departments: buildLevel("Department", "d", index.departments, true),
    courses: buildLevel("Course", "k", index.courses, true),
  };
  const rowErrors: string[][] = rows.map(() => []);

  // Pass one: field checks and name resolution only.
  const states: RowState[] = rows.map((raw, position) => {
    const row = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
    const errors = rowErrors[position];
    const state: RowState = {index: position, refs: [], invented: "", resolved: false};
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
    if (errors.length) return state;

    const college = resolveName(levels.colleges, "", collegeName, collegeCode, position, false, errors);
    if (!college) return state;
    // With no Department column, every college gets one department of its own name.
    state.invented = departmentMapped ? "" : (college.stored?.name ?? collegeName);
    const department = resolveName(levels.departments, college.ref, departmentMapped ? departmentName : state.invented,
      departmentCode, position, false, errors);
    if (!department) return state;
    const course = resolveName(levels.courses, department.ref, courseName, courseCode, position, true, errors);
    if (!course) return state;
    state.refs = [college, department, course];
    state.resolved = true;
    return state;
  });

  // Pass two: codes. Every code the file gave is settled before a single one is derived, so a derived
  // code can never outrank a code the file wrote further down.
  const allLevels = [levels.colleges, levels.departments, levels.courses];
  for (const level of allLevels) claimGivenCodes(level, rowErrors);
  // A code named for a record that already exists is held out of derivation but owned by nobody: it is
  // never written. Claims from a row that has already failed are ignored, so a doomed row cannot deny a
  // code to a row that succeeds.
  for (const state of states) {
    if (rowErrors[state.index].length) continue;
    for (const ref of state.refs) {
      if (ref.stored && ref.code) ref.level.reserved.add(normalizeKey(ref.code));
    }
  }
  for (const level of allLevels) deriveMissingCodes(level);

  // Pass three: a row's outcome, now that every code is settled.
  const results: CatalogRowResult[] = states.map((state) => {
    const errors = rowErrors[state.index];
    const warnings: string[] = [];
    // A code the file gives for a record that already exists is never written, so it cannot collide with
    // anything: the stored code is kept and the row is told so. Only a code somebody will write — a
    // planned record's — can be a collision, and that is settled in pass two.
    for (const ref of state.refs) {
      if (!ref.stored || !ref.code) continue;
      if (normalizeKey(ref.code) !== normalizeKey(ref.stored.code)) {
        warnings.push(`${ref.level.label} code “${ref.code}” differs from the stored code ` +
          `“${ref.stored.code}”; the stored code was kept.`);
      }
    }
    if (!state.resolved || errors.length) return {index: state.index, ok: false, errors};
    // Only a row that came through keeps its records in the plan.
    for (const ref of state.refs) if (ref.group) ref.group.used = true;
    const created = state.refs[2].group !== undefined;
    return {index: state.index, ok: true, kind: created ? "create" : "exists", warnings,
      ...(state.invented ? {invented: {department: state.invented}} : {})};
  });

  const planned = (level: Level): PlannedRecord[] => level.order.filter((group) => group.used)
    .map((group) => ({key: group.key, name: group.name, code: group.code, parent: group.parent}));
  const plan = {colleges: planned(levels.colleges), departments: planned(levels.departments),
    courses: planned(levels.courses)};
  const counts = {create: 0, exists: 0, error: 0,
    colleges: plan.colleges.length, departments: plan.departments.length, courses: plan.courses.length};
  for (const result of results) {
    if (!result.ok) counts.error += 1;
    else if (result.kind === "create") counts.create += 1;
    else counts.exists += 1;
  }
  return {results, plan, counts};
}
