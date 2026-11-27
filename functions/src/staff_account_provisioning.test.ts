import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  createStaffAccountByAdminHandler,
  generateStaffTemporaryPassword,
  ProvisioningDeps,
} from "./staff_account_provisioning";

function harness(overrides: Partial<ProvisioningDeps> = {}) {
  const createdUsers: Array<{uid: string; email: string; password: string}> = [];
  const deletedAuthUids: string[] = [];
  const savedProfiles: Array<Record<string, unknown>> = [];
  const deletedProfileUids: string[] = [];
  const sentEmails: Array<{to: string; subject: string; text: string; html: string}> = [];

  const deps: ProvisioningDeps = {
    requireSuperAdmin: async () => ({accessRole: "admin", name: "Super Admin"}),
    findAuthUidByEmail: async () => null,
    hasFirestoreEmail: async () => false,
    createAuthUser: async ({email, password}) => {
      const uid = `staff-${createdUsers.length + 1}`;
      createdUsers.push({uid, email, password});
      return {uid};
    },
    deleteAuthUser: async (uid) => {
      deletedAuthUids.push(uid);
    },
    writeStaffProfileAndAudit: async (input) => {
      savedProfiles.push({...input});
    },
    deleteUserProfile: async (uid) => {
      deletedProfileUids.push(uid);
    },
    generatePassword: () => "TempPass#9482!",
    sendMail: async (message) => {
      sentEmails.push(message);
    },
    portalUrl: () => "https://mindmate-staging.web.app",
    ...overrides,
  };

  return {deps, createdUsers, deletedAuthUids, savedProfiles, deletedProfileUids, sentEmails};
}

test("generateStaffTemporaryPassword returns 14-char complex password without ambiguous characters", () => {
  for (let i = 0; i < 15; i++) {
    const pwd = generateStaffTemporaryPassword();
    assert.equal(pwd.length, 14);
    assert.match(pwd, /[A-Z]/);
    assert.match(pwd, /[a-z]/);
    assert.match(pwd, /[2-9]/);
    assert.match(pwd, /[!@#$%&*?]/);
    assert.doesNotMatch(pwd, /[0O1lI]/);
  }
});

test("createStaffAccountByAdmin rejects non-super-admins, invalid roles, and invalid emails", async () => {
  const denied = harness({
    requireSuperAdmin: async () => {
      throw new HttpsError("permission-denied", "Super-administrator access is required.");
    },
  });
  await assert.rejects(
    createStaffAccountByAdminHandler({auth: {uid: "u1"}, data: {email: "c@school.edu", role: "counselor"}}, denied.deps),
    (e: unknown) => e instanceof HttpsError && e.code === "permission-denied",
  );

  const badRole = harness();
  await assert.rejects(
    createStaffAccountByAdminHandler({auth: {uid: "admin"}, data: {email: "c@school.edu", role: "admin"}}, badRole.deps),
    (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
  );

  await assert.rejects(
    createStaffAccountByAdminHandler({auth: {uid: "admin"}, data: {email: "not-an-email", role: "counselor"}}, badRole.deps),
    (e: unknown) => e instanceof HttpsError && e.code === "invalid-argument",
  );
});

test("createStaffAccountByAdmin rejects duplicate email addresses before creating Auth users", async () => {
  const dupAuth = harness({findAuthUidByEmail: async () => "existing-uid"});
  await assert.rejects(
    createStaffAccountByAdminHandler({auth: {uid: "admin"}, data: {email: "dup@school.edu", role: "counselor"}}, dupAuth.deps),
    (e: unknown) => e instanceof HttpsError && e.code === "already-exists",
  );
  assert.equal(dupAuth.createdUsers.length, 0);

  const dupProfile = harness({hasFirestoreEmail: async () => true});
  await assert.rejects(
    createStaffAccountByAdminHandler({auth: {uid: "admin"}, data: {email: "dup@school.edu", role: "portalStaff"}}, dupProfile.deps),
    (e: unknown) => e instanceof HttpsError && e.code === "already-exists",
  );
  assert.equal(dupProfile.createdUsers.length, 0);
});

test("createStaffAccountByAdmin provisions Counselor/Portal Staff, emails temporary password, and omits password from return", async () => {
  const h = harness();
  const res = await createStaffAccountByAdminHandler(
    {
      auth: {uid: "admin-1"},
      data: {email: "  New.Counselor@School.EDU ", role: "counselor", firstName: "Elena", lastName: "Cruz"},
    },
    h.deps,
  );

  assert.deepEqual(res, {
    ok: true,
    uid: "staff-1",
    email: "new.counselor@school.edu",
    role: "counselor",
    roleLabel: "Counselor",
  });
  assert.equal("password" in res, false);
  assert.equal(h.createdUsers.length, 1);
  assert.equal(h.createdUsers[0].email, "new.counselor@school.edu");
  assert.equal(h.createdUsers[0].password, "TempPass#9482!");
  assert.equal(h.savedProfiles.length, 1);
  assert.equal(h.savedProfiles[0].role, "counselor");
  assert.equal(h.savedProfiles[0].actorId, "admin-1");
  assert.equal(h.sentEmails.length, 1);
  assert.equal(h.sentEmails[0].to, "new.counselor@school.edu");
  assert.match(h.sentEmails[0].text, /TempPass#9482!/);
  assert.match(h.sentEmails[0].html, /TempPass#9482!/);
  assert.match(h.sentEmails[0].text, /Counselor/);
});

test("createStaffAccountByAdmin rolls back Firestore profile and Auth user when credential email fails", async () => {
  const h = harness({
    sendMail: async () => {
      throw new Error("SMTP timeout");
    },
  });
  await assert.rejects(
    createStaffAccountByAdminHandler(
      {auth: {uid: "admin-1"}, data: {email: "staff@school.edu", role: "portalStaff"}},
      h.deps,
    ),
    (e: unknown) => e instanceof HttpsError && e.code === "unavailable",
  );
  assert.deepEqual(h.deletedProfileUids, ["staff-1"]);
  assert.deepEqual(h.deletedAuthUids, ["staff-1"]);
});
