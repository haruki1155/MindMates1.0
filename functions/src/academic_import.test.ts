import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

import {importAcademicCatalog, previewAcademicCatalogImport} from "./index";
import {academicImportTestHooks} from "./academic_import";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: unknown}) => Promise<unknown>};
type WireRow = {index: number; kind: string; errors: string[]; warnings: string[]; inventedDepartment?: string};
type PreviewOut = {rows: WireRow[]; counts: Record<string, number>};
type ImportOut = {importId: string; counts: {colleges: number; departments: number; courses: number};
  status: string; message?: string};

const db = getFirestore();
const preview = previewAcademicCatalogImport as unknown as Callable;
const commit = importAcademicCatalog as unknown as Callable;
const run = `AC${Date.now()}`;
const key = run.toLowerCase();
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const auth = {uid: adminUid};
let adminCreated = false;
let suiteStart = Timestamp.now();

const COLLECTIONS = ["colleges", "departments", "courses"] as const;
const mine = (collection: string) => db.collection(collection)
  .where("normalizedName", ">=", key).where("normalizedName", "<", `${key}~`);
const sizeOf = async (collection: string) => (await mine(collection).get()).size;
const sizes = async () => (await Promise.all(COLLECTIONS.map(sizeOf))).join("/");
type Row = Record<string, unknown> & {id: string};
const docsOf = async (collection: string): Promise<Row[]> =>
  (await mine(collection).get()).docs.map((d) => ({...d.data(), id: d.id} as Row));

async function denied(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e: {code?: unknown}) => e?.code === code);
}

function name(label: string): string {
  return `${run} ${label}`;
}

before(async () => {
  suiteStart = Timestamp.fromMillis(Date.now() - 1000);
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && adminUid, "emulator + SUPER_ADMIN_UID required");
  const admin = db.collection("users").doc(adminUid);
  if (!(await admin.get()).exists) {
    adminCreated = true;
    await admin.set({accessRole: "admin", firstName: "Test", lastName: "Admin", email: "a@example.com"});
  }
});

after(async () => {
  academicImportTestHooks.beforeCommit = undefined;
  const refs: FirebaseFirestore.DocumentReference[] = [];
  for (const collection of COLLECTIONS) refs.push(...(await mine(collection).get()).docs.map((d) => d.ref));
  const imports = await db.collection("academic_catalogue_imports").where("actorId", "==", adminUid).get();
  const audits = await db.collection("admin_audit_logs")
    .where("actorId", "==", adminUid).where("action", "==", "ACADEMIC_CATALOGUE_IMPORTED").get();
  const recent = (d: FirebaseFirestore.QueryDocumentSnapshot) => {
    const at = d.data().createdAt;
    return at instanceof Timestamp && at.toMillis() >= suiteStart.toMillis();
  };
  refs.push(...imports.docs.filter(recent).map((d) => d.ref), ...audits.docs.filter(recent).map((d) => d.ref));
  await Promise.all(refs.map((r) => r.delete()));
  if (adminCreated) await db.collection("users").doc(adminUid).delete();
});

const cleanRows = () => [
  {college: name("College of Pharmacy"), department: name("Pharmacy Dept"), course: name("BS Pharmacy")},
  {college: name("College of Pharmacy"), department: name("Pharmacy Dept"), course: name("BS Pharmacy Tech")},
  {college: name("College of Law"), department: name("Law Dept"), course: name("Juris Doctor")},
];

test("callers must be admin and row counts are bounded", async () => {
  await denied(preview.run({auth: {uid: `${run}-nobody`}, data: {fileName: "x", rows: cleanRows()}}), "permission-denied");
  await denied(commit.run({auth: {uid: `${run}-nobody`}, data: {fileName: "x", rows: cleanRows()}}), "permission-denied");
  await denied(preview.run({auth, data: {fileName: "x", rows: []}}), "invalid-argument");
  await denied(preview.run({auth, data: {fileName: "x", rows: "nope"}}), "invalid-argument");
  const many = Array.from({length: 1001}, (_, i) => ({college: name("C"), department: name("D"), course: name(`K${i}`)}));
  await denied(preview.run({auth, data: {fileName: "x", rows: many}}), "invalid-argument");
  await denied(commit.run({auth, data: {fileName: "x", rows: many}}), "invalid-argument");
});

test("preview writes nothing and reports every row as create", async () => {
  const before = await sizes();
  const out = await preview.run({auth, data: {fileName: "cat.xlsx", sheetName: "Sheet1", rows: cleanRows()}}) as PreviewOut;
  assert.deepEqual(out.rows.map((r) => r.kind), ["create", "create", "create"]);
  assert.deepEqual(out.rows[0], {index: 0, kind: "create", errors: [], warnings: []});
  assert.equal(out.counts.create, 3);
  assert.equal(out.counts.exists, 0);
  assert.equal(out.counts.error, 0);
  assert.equal(out.counts.colleges, 2);
  assert.equal(out.counts.departments, 2);
  assert.equal(out.counts.courses, 3);
  assert.equal(await sizes(), before);
});

test("error rows refuse the whole import and nothing is written", async () => {
  const rows = [...cleanRows(), {college: name("College of Law"), department: "", course: name("Juris Doctor II")}];
  const out = await preview.run({auth, data: {fileName: "cat.xlsx", rows}}) as PreviewOut;
  assert.equal(out.rows[3].kind, "error");
  assert.match(out.rows[3].errors.join(" "), /unmap/i);
  const before = await sizes();
  await denied(commit.run({auth, data: {fileName: "cat.xlsx", rows}}), "invalid-argument");
  assert.equal(await sizes(), before);
});

test("over-long names and codes are error rows and nothing is written", async () => {
  const rows = [
    {college: name("College of Law"), department: name("Law Dept"), course: `${run} ${"x".repeat(121)}`},
    {college: name("College of Law"), department: name("Law Dept"), course: name("BS Legal"), courseCode: "y".repeat(31)},
  ];
  const out = await preview.run({auth, data: {fileName: "cat.xlsx", rows}}) as PreviewOut;
  assert.deepEqual(out.rows.map((r) => r.kind), ["error", "error"]);
  assert.match(out.rows[0].errors.join(" "), /Course name/);
  assert.match(out.rows[1].errors.join(" "), /Course code/);
  const before = await sizes();
  await denied(commit.run({auth, data: {fileName: "cat.xlsx", rows}}), "invalid-argument");
  assert.equal(await sizes(), before);
});

test("a clean import creates the catalogue, audits once, and re-running is a no-op", async () => {
  const out = await commit.run({auth, data: {fileName: "catalogue.xlsx", sheetName: "Sheet1", rows: cleanRows()}}) as ImportOut;
  assert.equal(out.status, "complete");
  assert.deepEqual(out.counts, {colleges: 2, departments: 2, courses: 3});
  assert.ok(out.importId);

  const colleges = await docsOf("colleges");
  const departments = await docsOf("departments");
  const courses = await docsOf("courses");
  assert.equal(colleges.length, 2);
  const pharmacy = colleges.find((c) => c.name === name("College of Pharmacy")) as Record<string, unknown>;
  assert.equal(pharmacy.active, true);
  assert.equal(pharmacy.status, "ACTIVE");
  assert.equal(pharmacy.normalizedName, name("College of Pharmacy").toLowerCase());
  assert.equal(pharmacy.normalizedCode, String(pharmacy.code).toLowerCase());
  const pharmacyDept = departments.find((d) => d.name === name("Pharmacy Dept")) as Record<string, unknown>;
  assert.equal(pharmacyDept.collegeId, pharmacy.id);
  assert.equal(pharmacyDept.active, true);
  const bsp = courses.find((c) => c.name === name("BS Pharmacy")) as Record<string, unknown>;
  assert.equal(bsp.collegeId, pharmacy.id);
  assert.equal(bsp.departmentId, pharmacyDept.id);
  assert.equal(bsp.status, "ACTIVE");

  const audits = await db.collection("admin_audit_logs").where("actorId", "==", adminUid)
    .where("action", "==", "ACADEMIC_CATALOGUE_IMPORTED").get();
  const ours = audits.docs.filter((d) => d.data().targetId === out.importId);
  assert.equal(ours.length, 1);
  const meta = ours[0].data().metadata as Record<string, unknown>;
  assert.equal(meta.fileName, "catalogue.xlsx");
  assert.deepEqual(meta.counts, {colleges: 2, departments: 2, courses: 3});

  // Re-running the same file is a no-op, even with different case and spacing.
  const again = cleanRows().map((r) => ({...r, college: `  ${r.college.toUpperCase()}  `}));
  const re = await preview.run({auth, data: {fileName: "catalogue.xlsx", rows: again}}) as PreviewOut;
  assert.deepEqual(re.rows.map((r) => r.kind), ["exists", "exists", "exists"]);
  assert.equal(re.counts.colleges, 0);
  const before = await sizes();
  const second = await commit.run({auth, data: {fileName: "catalogue.xlsx", rows: again}}) as ImportOut;
  assert.deepEqual(second.counts, {colleges: 0, departments: 0, courses: 0});
  assert.equal(await sizes(), before);
  assert.equal((await docsOf("colleges")).length, 2);
});

test("a file code colliding with another record errors; a differing code only warns", async () => {
  const colleges = await docsOf("colleges");
  const pharmacy = colleges.find((c) => c.name === name("College of Pharmacy")) as Record<string, unknown>;
  const law = colleges.find((c) => c.name === name("College of Law")) as Record<string, unknown>;
  const collide = [{college: name("College of Law"), collegeCode: String(pharmacy.code).toLowerCase(),
    department: name("Law Dept"), course: name("Juris Doctor")}];
  const out = await preview.run({auth, data: {fileName: "c.xlsx", rows: collide}}) as PreviewOut;
  assert.equal(out.rows[0].kind, "error");
  assert.match(out.rows[0].errors.join(" "), /College of Pharmacy/);

  const differing = [{college: name("College of Law"), collegeCode: `${run}ZZ`,
    department: name("Law Dept"), course: name("Juris Doctor")}];
  const warned = await preview.run({auth, data: {fileName: "c.xlsx", rows: differing}}) as PreviewOut;
  assert.equal(warned.rows[0].kind, "exists");
  assert.match(warned.rows[0].warnings.join(" "), new RegExp(`${run}ZZ`));
  await commit.run({auth, data: {fileName: "c.xlsx", rows: differing}});
  const stored = await db.collection("colleges").doc(String(law.id)).get();
  assert.equal(stored.data()?.code, law.code);
});

test("an archived college named by the file is an error row", async () => {
  const archived = db.collection("colleges").doc(`${run}-archived`);
  await archived.set({name: name("College of Ghosts"), code: `${run}G`, normalizedName: name("College of Ghosts").toLowerCase(),
    normalizedCode: `${run}g`.toLowerCase(), active: false, status: "ARCHIVED"});
  const out = await preview.run({auth, data: {fileName: "c.xlsx", rows: [
    {college: name("college of ghosts"), department: name("Ghost Dept"), course: name("BS Haunting")},
  ]}}) as PreviewOut;
  assert.equal(out.rows[0].kind, "error");
  assert.match(out.rows[0].errors.join(" "), /archived — restore it first/);
  assert.match(out.rows[0].errors.join(" "), new RegExp(name("College of Ghosts")));
});

test("no Department column invents one department per college and flags the rows", async () => {
  const rows = [
    {college: name("College of Invention"), course: name("BS Invention")},
    {college: name("College of Invention"), course: name("BS Tinkering")},
  ];
  const out = await preview.run({auth, data: {fileName: "c.xlsx", rows}}) as PreviewOut;
  assert.deepEqual(out.rows.map((r) => r.inventedDepartment),
    [name("College of Invention"), name("College of Invention")]);
  assert.equal(out.counts.departments, 1);
  const imported = await commit.run({auth, data: {fileName: "c.xlsx", rows}}) as ImportOut;
  assert.deepEqual(imported.counts, {colleges: 1, departments: 1, courses: 2});
  const departments = await docsOf("departments");
  const invented = departments.filter((d) => d.name === name("College of Invention"));
  assert.equal(invented.length, 1);
  const courses = (await docsOf("courses")).filter((c) => c.departmentId === invented[0].id);
  assert.equal(courses.length, 2);
});

test("derived codes that collide gain a digit", async () => {
  const rows = [
    {college: name("College of Codes"), department: name("Codes Dept"), course: `${run} Information Technology`},
    {college: name("College of Codes"), department: name("Codes Dept"), course: `${run} Industrial Technology`},
  ];
  await commit.run({auth, data: {fileName: "c.xlsx", rows}});
  const courses = await docsOf("courses");
  const codes = [`${run} Information Technology`, `${run} Industrial Technology`]
    .map((n) => String(courses.find((c) => c.name === n)?.code ?? ""));
  assert.deepEqual(codes, [`${run}IT`, `${run}IT2`]);
});

test("a department name used under a different college is created, and a duplicated course is refused", async () => {
  const rows = [{college: name("College of Law"), department: name("Pharmacy Dept"), course: name("BS Law Pharmacy")}];
  const out = await preview.run({auth, data: {fileName: "c.xlsx", rows}}) as PreviewOut;
  assert.equal(out.rows[0].kind, "create");
  assert.equal(out.counts.departments, 1);

  const dupe = [
    {college: name("College of Law"), department: name("Law Dept"), course: name("BS Doubled")},
    {college: name("College of Law"), department: name("law   dept"), course: name("BS   DOUBLED")},
  ];
  const duped = await preview.run({auth, data: {fileName: "c.xlsx", rows: dupe}}) as PreviewOut;
  assert.deepEqual(duped.rows.map((r) => r.kind), ["create", "error"]);
  await denied(commit.run({auth, data: {fileName: "c.xlsx", rows: dupe}}), "invalid-argument");
});

test("a failure partway reports what was committed", async () => {
  const rows = [{college: name("College of Partials"), department: name("Partial Dept"), course: name("BS Partial")}];
  academicImportTestHooks.beforeCommit = async (level: string) => {
    if (level === "courses") throw new Error("boom");
  };
  try {
    const out = await commit.run({auth, data: {fileName: "c.xlsx", rows}}) as ImportOut;
    assert.equal(out.status, "partial");
    assert.deepEqual(out.counts, {colleges: 1, departments: 1, courses: 0});
    assert.match(String(out.message), /committed/i);
  } finally {
    academicImportTestHooks.beforeCommit = undefined;
  }
  assert.equal((await docsOf("courses")).filter((c) => c.name === name("BS Partial")).length, 0);
});
