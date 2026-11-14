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

test("deriveCode takes initials from an ALL-CAPS registrar export", async () => {
  const {deriveCode} = await load();
  assert.equal(deriveCode("BS NURSING"), "BN");
  assert.equal(deriveCode("COLLEGE OF PHARMACY"), "CP");
  assert.equal(deriveCode("BACHELOR OF SCIENCE IN NURSING"), "BSN");
  // The acronym exception still applies to a mixed-case name, and is bounded to a short word.
  assert.equal(deriveCode("BS Information Technology"), "BSIT");
  assert.equal(deriveCode("MINDMATE Institute of Technology"), "MIT");
});

test("a name whose initials come to one letter falls back to its first four characters", async () => {
  const {deriveCode} = await load();
  assert.equal(deriveCode("NURSING"), "NURS");
  assert.equal(deriveCode("PHARMACY"), "PHAR");
  assert.equal(deriveCode("Midwifery"), "MIDW");
  // Still unchanged.
  assert.equal(deriveCode("BS Information Technology"), "BSIT");
  assert.equal(deriveCode("COLLEGE OF PHARMACY"), "CP");
  assert.equal(deriveCode("BS NURSING"), "BN");
  assert.equal(deriveCode("BACHELOR OF SCIENCE IN NURSING"), "BSN");
});

test("a file code given for a stored record is not displaced by a derived one", async () => {
  const {validateCatalogRows} = await load();
  const index = {
    colleges: [{id: "x1", name: "College of Law", code: "CL", active: true}],
    departments: [], courses: [],
  };
  const stated = {college: "College of Law", collegeCode: "CP", department: "Law Dept", course: "Juris Doctor"};
  const fresh = {college: "City Park", department: "Annex Dept", course: "BS Annex"};
  for (const rows of [[stated, fresh], [fresh, stated]]) {
    const out = validateCatalogRows(rows, index);
    const law = out.results[rows.indexOf(stated)];
    assert.equal(law.ok, true, JSON.stringify(out.results));
    assert.match(law.ok ? law.warnings.join(" ") : "", /differs from the stored code “CL”/);
    assert.deepEqual(out.plan.colleges.map((c) => c.name), ["City Park"]);
    // “CP” was named by the file for the stored college, so the new college cannot derive it.
    assert.equal(out.plan.colleges[0].code, "CP2");
  }
});

test("two stored rows naming the same code both only warn", async () => {
  const {validateCatalogRows} = await load();
  const index = {
    colleges: [
      {id: "x1", name: "College of Law", code: "CL", active: true},
      {id: "x2", name: "College of Arts", code: "CA", active: true},
    ],
    departments: [], courses: [],
  };
  const law = {college: "College of Law", collegeCode: "ZZ", department: "Law Dept", course: "Juris Doctor"};
  const arts = {college: "College of Arts", collegeCode: "ZZ", department: "Arts Dept", course: "BA Arts"};
  for (const rows of [[law, arts], [arts, law]]) {
    const out = validateCatalogRows(rows, index);
    assert.deepEqual(out.results.map((r) => r.ok), [true, true], JSON.stringify(out.results));
    for (const result of out.results) {
      assert.match(result.ok ? result.warnings.join(" ") : "", /differs from the stored code/);
    }
    assert.equal(out.counts.error, 0);
  }
});

test("a file code given to a new record wins, and the stored row naming it only warns", async () => {
  const {validateCatalogRows} = await load();
  const index = {colleges: [{id: "x1", name: "College of Law", code: "CL", active: true}], departments: [], courses: []};
  const fresh = {college: "City Park", collegeCode: "CP", department: "Park Dept", course: "BS Park"};
  const stored = {college: "College of Law", collegeCode: "CP", department: "Law Dept", course: "Juris Doctor"};
  for (const rows of [[fresh, stored], [stored, fresh]]) {
    const out = validateCatalogRows(rows, index);
    assert.deepEqual(out.results.map((r) => r.ok), [true, true], JSON.stringify(out.results));
    const storedRow = out.results[rows.indexOf(stored)];
    assert.match(storedRow.ok ? storedRow.warnings.join(" ") : "", /differs from the stored code “CL”/);
    assert.deepEqual(out.plan.colleges.map((c) => [c.name, c.code]), [["City Park", "CP"]]);
  }
});

test("a failed row's stored code claim does not deny that code to a successful row", async () => {
  const {validateCatalogRows} = await load();
  const index = {colleges: [{id: "x1", name: "College of Law", code: "CL", active: true}], departments: [], courses: []};
  const out = validateCatalogRows([
    // Claims DX for its department and plans "City Park", whose name derives CP.
    {college: "City Park", department: "Park Dept", departmentCode: "DX", course: "BS Park"},
    // Fails on the already-claimed department code, so its CP claim must not reserve anything.
    {college: "College of Law", collegeCode: "CP", department: "Law Dept", departmentCode: "DX",
      course: "Juris Doctor"},
  ], index);
  assert.deepEqual(out.results.map((r) => r.ok), [true, false], JSON.stringify(out.results));
  assert.deepEqual(out.plan.colleges.map((c) => [c.name, c.code]), [["City Park", "CP"]]);
});

test("a sparse code column is read before any code is derived, in either row order", async () => {
  const {validateCatalogRows} = await load();
  const blankFirst = [
    {college: "College of Law", collegeCode: "", department: "Law Dept", course: "Juris Doctor"},
    {college: "College of Law", collegeCode: "CLAW", department: "Law Dept", course: "Master of Laws"},
  ];
  const codeFirst = [blankFirst[1], blankFirst[0]];
  for (const rows of [blankFirst, codeFirst]) {
    const out = validateCatalogRows(rows, emptyIndex);
    assert.deepEqual(out.results.map((r) => r.ok), [true, true], JSON.stringify(out.results));
    assert.deepEqual(out.plan.colleges.map((c) => c.code), ["CLAW"]);
  }
});

test("a derived code yields to another row's explicit code", async () => {
  const {validateCatalogRows} = await load();
  const rows = [
    {college: "College of Pharmacy", department: "Pharmacy Dept", course: "BS Pharmacy"},
    {college: "City Park Annex", collegeCode: "CP", department: "Annex Dept", course: "BS Annex"},
  ];
  for (const ordered of [rows, [rows[1], rows[0]]]) {
    const out = validateCatalogRows(ordered, emptyIndex);
    assert.deepEqual(out.results.map((r) => r.ok), [true, true]);
    const byName = new Map(out.plan.colleges.map((c) => [c.name, c.code]));
    assert.equal(byName.get("City Park Annex"), "CP");
    assert.equal(byName.get("College of Pharmacy"), "CP2");
  }
});

test("the same new department name under two new colleges plans two departments", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College One", department: "General Studies", course: "BS One"},
    {college: "College Two", department: "General Studies", course: "BS Two"},
  ], emptyIndex);
  assert.deepEqual(out.results.map((r) => r.ok && r.kind), ["create", "create"]);
  assert.equal(out.plan.departments.length, 2);
  assert.deepEqual(out.plan.departments.map((d) => d.name), ["General Studies", "General Studies"]);
  const [first, second] = out.plan.departments;
  assert.notEqual(first.code, second.code);
  assert.notEqual(first.parent, second.parent);
  assert.deepEqual(out.plan.departments.map((d) => d.parent),
    out.plan.colleges.map((c) => `new:${c.key}`));
});

test("an error row leaves nothing of its own in the plan", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College Kept", collegeCode: "CK", department: "Dept Kept", course: "BS Kept"},
    // The same code for a second college blocks this row only once every code has been read, by which
    // time its department and course had already been resolved. Neither may stay in the plan.
    {college: "College Dropped", collegeCode: "CK", department: "Dept Dropped", course: "BS Dropped"},
  ], emptyIndex);
  assert.deepEqual(out.results.map((r) => r.ok), [true, false]);
  assert.deepEqual(out.plan.colleges.map((c) => c.name), ["College Kept"]);
  assert.deepEqual(out.plan.departments.map((d) => d.name), ["Dept Kept"]);
  assert.deepEqual(out.counts, {create: 1, exists: 0, error: 1, colleges: 1, departments: 1, courses: 1});
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

test("the same course under two departments of one college is a duplicate error", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College of Computing", department: "Information Technology", course: "BS Information Technology"},
    {college: "College of Computing", department: "IT Department", course: "BS Information Technology"},
  ], emptyIndex);
  assert.equal(out.results[0].ok, true, JSON.stringify(out.results));
  assert.equal(out.results[1].ok, false);
  const message = out.results[1].ok ? "" : out.results[1].errors.join(" ");
  assert.match(message, /BS Information Technology/);
  assert.match(message, /Information Technology”/);
  assert.equal(out.plan.courses.length, 1);
});

test("the same course name under two different colleges still creates two courses", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College of Computing", department: "IT Dept", course: "BS Information Technology"},
    {college: "College of Engineering", department: "CpE Dept", course: "BS Information Technology"},
  ], emptyIndex);
  assert.equal(out.results[0].ok, true, JSON.stringify(out.results));
  assert.equal(out.results[1].ok, true, JSON.stringify(out.results));
  assert.equal(out.plan.courses.length, 2);
  assert.equal(out.counts.error, 0);
});

test("course names are compared with the roster matcher's normalisation", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "College of Nursing", department: "Nursing Dept", course: "B.S. Nursing"},
    {college: "College of Nursing", department: "Nursing Dept", course: "BS Nursing"},
  ], emptyIndex);
  assert.equal(out.results[0].ok, true, JSON.stringify(out.results));
  assert.equal(out.results[1].ok, false);
  assert.equal(out.plan.courses.length, 1);

  const index = {
    colleges: [{id: "x1", name: "College of Nursing", code: "CN", active: true}],
    departments: [{id: "d1", name: "Nursing Dept", code: "ND", active: true, parentId: "x1"}],
    courses: [{id: "k1", name: "BS Nursing", code: "BSN", active: true, parentId: "d1"}],
  };
  const stored = validateCatalogRows(
    [{college: "College of Nursing", department: "Nursing Dept", course: "B.S. Nursing"}], index);
  assert.equal(stored.results[0].ok && stored.results[0].kind, "exists");
  assert.equal(stored.plan.courses.length, 0);
});

test("a stored course is matched anywhere in its college, whatever department the file names", async () => {
  const {validateCatalogRows} = await load();
  const index = {
    colleges: [{id: "x1", name: "College of Computing", code: "CC", active: true}],
    departments: [{id: "d1", name: "IT Dept", code: "ITD", active: true, parentId: "x1"}],
    courses: [{id: "k1", name: "BS Information Technology", code: "BSIT", active: true, parentId: "d1"}],
  };
  const out = validateCatalogRows(
    [{college: "College of Computing", department: "IT Department", course: "BS Information Technology"}], index);
  assert.equal(out.results[0].ok && out.results[0].kind, "exists");
  assert.equal(out.plan.courses.length, 0);
});

test("a group mentioned only by failed rows is not named as a collision owner", async () => {
  const {validateCatalogRows} = await load();
  const out = validateCatalogRows([
    {college: "C1", department: "Dept A", course: "BS IT"},
    {college: "C1", department: "Dept B", departmentCode: "DX", course: "BS IT"},
    {college: "C1", department: "Dept C", departmentCode: "DX", course: "BS Other"},
  ], emptyIndex);
  assert.equal(out.results[1].ok, false);
  assert.equal(out.results[2].ok, true, JSON.stringify(out.results));
  assert.doesNotMatch(JSON.stringify(out.results), /Dept B/);
  assert.deepEqual(out.plan.departments.map((d) => `${d.name}:${d.code}`), ["Dept A:DA", "Dept C:DX"]);
});
