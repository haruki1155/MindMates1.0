import {getApps, initializeApp} from "firebase-admin/app";
import assert from "node:assert/strict";
import test from "node:test";

if (!getApps().length) initializeApp({projectId: "mind-mates-roster-domain-test"});

const load = () => import("./student_roster_domain");
const index = {
  colleges: [
    {id: "c1", name: "College of Information Technology and Engineering", code: "CITE"},
    {id: "c2", name: "College of Business", code: "CBA"},
  ],
  courses: [
    {id: "k1", name: "BS Information Technology", code: "BSIT", collegeId: "c1", departmentId: "d1", departmentName: "IT Dept"},
    {id: "k2", name: "BS Accountancy", code: "BSA", collegeId: "c2", departmentId: "d2", departmentName: "Acct Dept"},
  ],
};
const goodRow = {studentNo: "2021-00123", surname: "Dela Cruz", firstName: "Juan", middleName: "",
  dateOfBirth: "2005-02-03", college: "cite", course: "bsit", yearLevel: "1"};

test("normalizeName ignores case, spacing, punctuation and diacritics", async () => {
  const {normalizeName} = await load();
  assert.equal(normalizeName("Dela Cruz"), normalizeName("DELA-CRUZ"));
  assert.equal(normalizeName("Dela Cruz"), normalizeName("dela cruz"));
  assert.equal(normalizeName("Peña"), normalizeName("PENA"));
  assert.equal(normalizeName("O'Brien Jr."), "obrienjr");
});

test("normalizeYearLevel", async () => {
  const {normalizeYearLevel} = await load();
  for (const v of ["1", "1st", "1st year", "Year 1", "First Year", 1]) assert.equal(normalizeYearLevel(v), "1st Year");
  assert.equal(normalizeYearLevel("5"), "5th Year");
  assert.equal(normalizeYearLevel("6"), null);
  assert.equal(normalizeYearLevel(""), null);
});

test("parseDateKey", async () => {
  const {parseDateKey} = await load();
  assert.equal(parseDateKey("2005-02-29"), null);
  assert.equal(parseDateKey("2004-02-29"), "2004-02-29");
  assert.equal(parseDateKey("02/15/2005"), null);
  assert.equal(parseDateKey("2999-01-01"), null);
  assert.equal(parseDateKey("1899-12-31"), null);
  assert.equal(parseDateKey(new Date()), null);
});

test("validateRosterRows accepts a valid row", async () => {
  const {validateRosterRows} = await load();
  const {canonicalLoginId} = await import("./account_recovery");
  const [r] = validateRosterRows([goodRow], index);
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.value.studentKey, canonicalLoginId("2021-00123"));
    assert.equal(r.value.studentKey, "202100123");
    assert.equal(r.value.yearLevel, "1st Year");
    assert.equal(r.value.collegeId, "c1");
    assert.equal(r.value.courseId, "k1");
    assert.equal(r.value.departmentId, "d1");
    assert.equal(r.value.department, "IT Dept");
    assert.equal(r.value.middleName, "");
    assert.equal(r.value.dateOfBirthKey, "2005-02-03");
  }
});

test("validateRosterRows matches college by name or code", async () => {
  const {validateRosterRows} = await load();
  const [r] = validateRosterRows([{...goodRow, college: "COLLEGE OF INFORMATION TECHNOLOGY AND ENGINEERING"}], index);
  assert.equal(r.ok, true);
});

test("validateRosterRows rejects course outside college", async () => {
  const {validateRosterRows} = await load();
  const [r] = validateRosterRows([{...goodRow, course: "BSA"}], index);
  assert.equal(r.ok, false);
  if (!r.ok) assert.ok(r.errors.includes("Course is not under the selected college."));
});

test("validateRosterRows flags duplicates in file", async () => {
  const {validateRosterRows} = await load();
  const rs = validateRosterRows([goodRow, {...goodRow, studentNo: "202100123"}, {...goodRow, studentNo: "2022-1"}], index);
  for (const i of [0, 1]) {
    const r = rs[i];
    assert.equal(r.ok, false);
    if (!r.ok) assert.ok(r.errors.includes("Duplicate Student No. in file."));
  }
  assert.equal(rs[2].ok, true);
  assert.deepEqual(rs.map((r) => r.index), [0, 1, 2]);
});

test("validateRosterRows reports missing and invalid fields", async () => {
  const {validateRosterRows} = await load();
  const [a, b, c] = validateRosterRows([
    {...goodRow, surname: ""},
    {...goodRow, dateOfBirth: "02/15/2005"},
    {...goodRow, studentNo: "!!", yearLevel: "9", college: "nope"},
  ], index);
  assert.equal(a.ok, false);
  if (!a.ok) assert.ok(a.errors.some((e) => e.includes("Surname")));
  assert.equal(b.ok, false);
  assert.equal(c.ok, false);
  if (!c.ok) assert.ok(c.errors.length >= 3);
});

test("activation codes: format and alphabet", async () => {
  const {generateActivationCode} = await load();
  for (let i = 0; i < 1000; i++) {
    const code = generateActivationCode();
    assert.match(code, /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/);
    assert.doesNotMatch(code, /[0OIL1]/);
  }
});

test("normalizeActivationCode", async () => {
  const {normalizeActivationCode} = await load();
  assert.equal(normalizeActivationCode(" abcde fghjk "), "ABCDEFGHJK");
  assert.equal(normalizeActivationCode("abcdefghjk"), "ABCDEFGHJK");
  assert.equal(normalizeActivationCode("ABCDE-FGHJ"), null);
  assert.equal(normalizeActivationCode("ABCDE-FGHJ0"), null);
  assert.equal(normalizeActivationCode(null), null);
  assert.equal(normalizeActivationCode(12345), null);
});

test("hash and verify activation codes", async () => {
  const {generateActivationCode, hashActivationCode, verifyActivationCode, ACTIVATION_CODE_TTL_DAYS} = await load();
  assert.equal(ACTIVATION_CODE_TTL_DAYS, 60);
  const code = generateActivationCode();
  const now = new Date("2026-11-12T00:00:00Z");
  const stored = await hashActivationCode(code, now);
  assert.equal(stored.issuedAt.getTime(), now.getTime());
  assert.equal(stored.expiresAt.getTime(), now.getTime() + 60 * 24 * 60 * 60 * 1000);
  assert.equal(await verifyActivationCode(code.toLowerCase().replace("-", ""), stored), true);
  assert.equal(await verifyActivationCode(code, stored), true);
  assert.equal(await verifyActivationCode(generateActivationCode(), stored), false);
  assert.equal(await verifyActivationCode(code, null), false);
  assert.equal(await verifyActivationCode(code, undefined), false);
  assert.equal(await verifyActivationCode("bad", stored), false);
  const again = await hashActivationCode(code, now);
  assert.notEqual(again.hash, stored.hash);
  assert.notEqual(again.salt, stored.salt);
  const expired = await hashActivationCode(code, new Date("2000-01-01"));
  assert.equal(await verifyActivationCode(code, expired), true);
});

test("normalizeCellphone", async () => {
  const {normalizeCellphone} = await load();
  assert.equal(normalizeCellphone("+63 917 123 4567"), "09171234567");
  assert.equal(normalizeCellphone("639171234567"), "09171234567");
  assert.equal(normalizeCellphone("0917-123-4567"), "09171234567");
  assert.equal(normalizeCellphone("08171234567"), null);
  assert.equal(normalizeCellphone("0917123456"), null);
  assert.equal(normalizeCellphone(5), null);
});

const addr = {number: "1", street: "Main", barangay: "Brgy 1", cityTown: "Pili", province: "Camarines Sur", zipCode: "4400"};
const goodInfo = {sex: "Female", civilStatus: "Single", spouse: "", nationality: "Filipino", placeOfBirth: "Naga",
  cityAddress: null, homeAddress: addr, father: "A", fatherOccupation: "B", mother: "C", motherOccupation: "D",
  guardian: "E", guardianRelationship: "Aunt", guardianAddress: "Somewhere", telephone: "", cellphone: "09171234567"};

test("validatePersonalInfo happy path", async () => {
  const {validatePersonalInfo} = await load();
  const r = validatePersonalInfo({...goodInfo, extra: "x"});
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.value.cityAddress, null);
    assert.equal("extra" in r.value, false);
    assert.equal(r.value.sex, "Female");
  }
});

test("validatePersonalInfo civil status and spouse", async () => {
  const {validatePersonalInfo} = await load();
  const m = validatePersonalInfo({...goodInfo, civilStatus: "Married"});
  assert.equal(m.ok, false);
  if (!m.ok) assert.ok(m.errors.spouse);
  const s = validatePersonalInfo({...goodInfo, spouse: "Someone"});
  assert.equal(s.ok, true);
  if (s.ok) assert.equal(s.value.spouse, "");
  const bad = validatePersonalInfo({...goodInfo, civilStatus: "Complicated", sex: "Other"});
  assert.equal(bad.ok, false);
  if (!bad.ok) {
    assert.ok(bad.errors.civilStatus);
    assert.ok(bad.errors.sex);
  }
});

test("validatePersonalInfo addresses", async () => {
  const {validatePersonalInfo} = await load();
  const h = validatePersonalInfo({...goodInfo, homeAddress: {...addr, barangay: ""}});
  assert.equal(h.ok, false);
  if (!h.ok) assert.ok(h.errors["homeAddress.barangay"]);
  const empty = validatePersonalInfo({...goodInfo, cityAddress: {number: "", street: "", barangay: "", cityTown: "", province: "", zipCode: ""}});
  assert.equal(empty.ok, true);
  if (empty.ok) assert.equal(empty.value.cityAddress, null);
  const partial = validatePersonalInfo({...goodInfo, cityAddress: {number: "", street: "Rizal", barangay: "", cityTown: "", province: "", zipCode: ""}});
  assert.equal(partial.ok, false);
  if (!partial.ok) {
    for (const k of ["barangay", "cityTown", "province"]) assert.ok(partial.errors[`cityAddress.${k}`], k);
  }
  const zip = validatePersonalInfo({...goodInfo, homeAddress: {...addr, zipCode: "240"}});
  assert.equal(zip.ok, false);
  if (!zip.ok) assert.ok(zip.errors["homeAddress.zipCode"]);
});

test("validatePersonalInfo contact, guardian and length", async () => {
  const {validatePersonalInfo} = await load();
  const c = validatePersonalInfo({...goodInfo, cellphone: "+63 917 123 4567"});
  assert.equal(c.ok, true);
  if (c.ok) assert.equal(c.value.cellphone, "09171234567");
  const bc = validatePersonalInfo({...goodInfo, cellphone: "08171234567"});
  assert.equal(bc.ok, false);
  if (!bc.ok) assert.ok(bc.errors.cellphone);
  const g = validatePersonalInfo({...goodInfo, guardian: ""});
  assert.equal(g.ok, false);
  if (!g.ok) assert.ok(g.errors.guardian);
  const long = validatePersonalInfo({...goodInfo, father: "x".repeat(161)});
  assert.equal(long.ok, false);
  if (!long.ok) assert.ok(long.errors.father);
  assert.equal(validatePersonalInfo(null).ok, false);
});

test("constants", async () => {
  const m = await load();
  assert.equal(m.PRIVACY_POLICY_VERSION, "2026-11-ra10173-v1");
  assert.deepEqual([...m.CORRECTABLE_FIELDS], ["surname", "firstName", "middleName", "dateOfBirth", "college", "course", "yearLevel"]);
});
