import assert from "node:assert/strict";
import test from "node:test";

const load = () => import("./academic_import_domain");

const emptyIndex = {colleges: [], departments: [], courses: []};

test("normalizeKey ignores case and collapses whitespace", async () => {
  const {normalizeKey} = await load();
  assert.equal(normalizeKey("  College   of  Pharmacy "), normalizeKey("college of pharmacy"));
  assert.equal(normalizeKey("College of Pharmacy"), "college of pharmacy");
  assert.equal(normalizeKey(""), "");
});

test("deriveCode keeps acronyms and drops stop words", async () => {
  const {deriveCode} = await load();
  assert.equal(deriveCode("BS Information Technology"), "BSIT");
  assert.equal(deriveCode("College of Pharmacy"), "CP");
  assert.equal(deriveCode("College of Arts and Sciences in the City"), "CASC");
});

test("an absent department column invents one department per college", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College of Pharmacy", course: "BS Pharmacy"},
    {college: "College of Pharmacy", course: "BS Pharmacy Technology"},
  ], emptyIndex);
  assert.deepEqual(out.results.map((r) => r.ok && r.invented?.department),
    ["College of Pharmacy", "College of Pharmacy"]);
  assert.equal(out.plan.departments.length, 1);
  assert.equal(out.plan.departments[0].name, "College of Pharmacy");
});

test("a blank department cell is an error naming both fixes", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([{college: "College of Pharmacy", department: "", course: "BS Pharmacy"}], emptyIndex);
  const row = out.results[0];
  assert.equal(row.ok, false);
  const message = row.ok ? "" : row.errors.join(" ");
  assert.match(message, /Department/);
  assert.match(message, /unmap/i);
  assert.equal(out.plan.courses.length, 0);
});

test("the same course twice under the same department is an error row", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "C1", department: "D1", course: "BS Information Technology"},
    {college: "C1", department: "D1", course: "bs   information technology"},
  ], emptyIndex);
  assert.equal(out.results[0].ok, true);
  assert.equal(out.results[1].ok, false);
  assert.equal(out.counts.error, 1);
});

test("derived codes that collide get a digit appended", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "C1", department: "D1", course: "BS Information Technology"},
    {college: "C1", department: "D2", course: "BS Industrial Technology"},
  ], emptyIndex);
  assert.deepEqual(out.plan.courses.map((c) => c.code), ["BSIT", "BSIT2"]);
});

test("names and codes are bounded, and the error names the field", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "C1", department: "D1", course: "x".repeat(121)},
    {college: "C1", department: "D1", course: "BS Nursing", courseCode: "y".repeat(31)},
  ], emptyIndex);
  assert.match(out.results[0].ok ? "" : out.results[0].errors.join(" "), /Course name must be 2 to 120 characters/);
  assert.match(out.results[1].ok ? "" : out.results[1].errors.join(" "), /Course code must be 1 to 30 characters/);
  assert.equal(out.plan.courses.length, 0);
});

test("an archived college is an error row that names the record", async () => {
  const {validateCatalogRows} = await load();
  const index = {colleges: [{id: "x1", name: "College of Law", code: "CL", active: false}], departments: [], courses: []};
  const out = validateCatalogRows([{college: "college of law", department: "D1", course: "Juris Doctor"}], index);
  const message = out.results[0].ok ? "" : out.results[0].errors.join(" ");
  assert.match(message, /archived — restore it first/);
  assert.match(message, /College of Law/);
});

test("a department name used under another college still counts as new", async () => {
  const {validateCatalogRows} = await load();
  const index = {
    colleges: [{id: "x1", name: "College A", code: "CA", active: true}],
    departments: [{id: "d1", name: "Shared Dept", code: "SD", active: true, parentId: "x1"}],
    courses: [],
  };
  const out = validateCatalogRows([{college: "College B", department: "Shared Dept", course: "BS Nursing"}], index);
  assert.equal(out.results[0].ok && out.results[0].kind, "create");
  assert.equal(out.plan.departments.length, 1);
});

test("a stored record matched by name is exists; a differing file code is a warning", async () => {
  const {validateCatalogRows} = await load();
  const index = {
    colleges: [{id: "x1", name: "College of Pharmacy", code: "CP", active: true}],
    departments: [{id: "d1", name: "Pharmacy Dept", code: "PD", active: true, parentId: "x1"}],
    courses: [{id: "k1", name: "BS Pharmacy", code: "BSP", active: true, parentId: "d1"}],
  };
  const out = validateCatalogRows([
    {college: "  COLLEGE   of Pharmacy ", collegeCode: "CPX", department: "Pharmacy Dept", course: "BS Pharmacy"},
  ], index);
  const row = out.results[0];
  assert.equal(row.ok && row.kind, "exists");
  assert.match(row.ok ? row.warnings.join(" ") : "", /CPX/);
  assert.equal(out.plan.colleges.length, 0);
  assert.equal(out.plan.courses.length, 0);
});

test("a file code already used by a different record is an error", async () => {
  const {validateCatalogRows} = await load();
  const index = {
    colleges: [{id: "x1", name: "College A", code: "CA", active: true}],
    departments: [], courses: [],
  };
  const out = validateCatalogRows([{college: "College B", collegeCode: "ca", department: "Dept", course: "BS X"}], index);
  assert.equal(out.results[0].ok, false);
  assert.match(out.results[0].ok ? "" : out.results[0].errors.join(" "), /College A/);
});

test("one code given to two different names in the file is an error", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College A", collegeCode: "CX", department: "Dept", course: "BS X"},
    {college: "College B", collegeCode: "CX", department: "Dept", course: "BS Y"},
  ], emptyIndex);
  assert.equal(out.results[0].ok, true);
  assert.equal(out.results[1].ok, false);
});
