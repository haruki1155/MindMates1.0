import {getApps, initializeApp} from "firebase-admin/app";
import assert from "node:assert/strict";
import test from "node:test";

if (!getApps().length) initializeApp({projectId: "mind-mates-account-integrity-test"});

test("profile provisioning validates each population role", async () => {
  const {validatedProfileInput} = await import("./account_integrity");
  const base = {firstName: "Mind", lastName: "Mate", gender: "Prefer not to say", dateOfBirth: "2005-01-15T00:00:00.000Z"};
  assert.equal(validatedProfileInput({...base, populationRole: "student", department: "CITE", course: "BSIT", yearLevel: "2"}).populationRole, "student");
  assert.equal(validatedProfileInput({...base, populationRole: "teaching", employeeId: "E-1", department: "CITE", position: "Instructor"}).populationRole, "teaching");
  assert.equal(validatedProfileInput({...base, populationRole: "nonTeaching", employeeId: "E-2", sector: "Registrar", position: "Officer"}).populationRole, "nonTeaching");
});

test("profile provisioning rejects incomplete student input", async () => {
  const {validatedProfileInput} = await import("./account_integrity");
  assert.throws(() => validatedProfileInput({firstName: "Mind", lastName: "Mate", gender: "Female", dateOfBirth: "2005-01-15T00:00:00.000Z", populationRole: "student"}), /Students must provide/);
});

test("profile provisioning requires a supported sex or gender value", async () => {
  const {validatedProfileInput} = await import("./account_integrity");
  const profile = {firstName: "Mind", lastName: "Mate", dateOfBirth: "2005-01-15T00:00:00.000Z",
    populationRole: "student", department: "CITE", course: "BSIT", yearLevel: "2"};
  assert.throws(() => validatedProfileInput(profile), /Sex \/ gender/);
  assert.throws(() => validatedProfileInput({...profile, gender: "unsupported"}), /valid sex \/ gender/);
});

test("registration role is derived only from the exact UCU email domain", async () => {
  const {registrationRoleForEmail} = await import("./account_integrity");
  assert.equal(registrationRoleForEmail("juandelacruz@ucu.edu.ph"), "teaching");
  assert.equal(registrationRoleForEmail(" JuanDelaCruz@UCU.EDU.PH "), "teaching");
  assert.equal(registrationRoleForEmail("teacher@ucu.edu.ph.example.com"), "student");
  assert.equal(registrationRoleForEmail("student@gmail.com"), "student");
});

test("recovery normalizes School IDs consistently", async () => {
  const {authEmailForSchoolId, canonicalLoginId} = await import("./account_recovery");
  assert.equal(authEmailForSchoolId(" 2024 / 001 "), "2024.001@mindmate.local");
  assert.throws(() => authEmailForSchoolId("***"), /valid School ID/);
  assert.equal(canonicalLoginId(" 2026-0001 "), "20260001");
  assert.equal(canonicalLoginId(" fac_001 "), "FAC001");
  assert.throws(() => canonicalLoginId("--"), /valid School ID/);
});

test("student IDs follow the supplied five-year allowlist structure", async () => {
  const {canonicalStudentId} = await import("./account_integrity");
  assert.equal(canonicalStudentId("20260001"), "20260001");
  assert.throws(() => canonicalStudentId("20210001"), /approved list/);
  assert.throws(() => canonicalStudentId("2026-0001"), /approved list/);
});
