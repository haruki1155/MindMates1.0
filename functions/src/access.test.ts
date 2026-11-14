import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index"; // initialises the default Admin app the gates use
import {requireAdmin, requireClinical, requireStaff} from "./access";

// Server-side authorization gates must agree with firestore.rules: role,
// approved/active lifecycle, verified email and an enabled Auth account.
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `access-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;

type Fixture = {name: string; emailVerified: boolean; disabled?: boolean; profile: Record<string, unknown>};
const fixtures: Fixture[] = [
  {name: "legacy-counselor", emailVerified: true, profile: {accessRole: "counselor"}},
  {name: "legacy-counselor-active", emailVerified: true, profile: {accessRole: "counselor", accountStatus: "active"}},
  {name: "legacy-counselor-suspended", emailVerified: true, profile: {accessRole: "counselor", accountStatus: "suspended"}},
  {name: "legacy-counselor-unverified", emailVerified: false, profile: {accessRole: "counselor"}},
  {name: "legacy-staff-disabled", emailVerified: true, profile: {accessRole: "portalStaff", accountStatus: "disabled"}},
  {name: "approved-staff-auth-disabled", emailVerified: true, disabled: true, profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"}},
  {name: "approved-counselor", emailVerified: true, profile: {accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active"}},
  {name: "admin", emailVerified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  {name: "admin-unverified", emailVerified: false, profile: {accessRole: "admin", accountStatus: "active"}},
  {name: "admin-suspended", emailVerified: true, profile: {accessRole: "admin", accountStatus: "suspended"}},
];

async function denied(promise: Promise<unknown>): Promise<void> {
  await assert.rejects(promise, (error: unknown) => error instanceof HttpsError && error.code === "permission-denied");
}

before(async () => {
  if (!emulated) return;
  const db = getFirestore();
  for (const fixture of fixtures) {
    await getAuth().createUser({uid: uid(fixture.name), email: `${uid(fixture.name)}@example.invalid`, emailVerified: fixture.emailVerified, disabled: fixture.disabled === true});
    await db.doc(`users/${uid(fixture.name)}`).set(fixture.profile);
  }
});

after(async () => {
  if (!emulated) return;
  const db = getFirestore();
  for (const fixture of fixtures) {
    await getAuth().deleteUser(uid(fixture.name)).catch(() => undefined);
    await db.doc(`users/${uid(fixture.name)}`).delete().catch(() => undefined);
  }
});

test("legacy privileged records without lifecycle fields keep callable access when verified and not suspended", {skip: !emulated}, async () => {
  assert.equal((await requireStaff(uid("legacy-counselor"))).accessRole, "counselor");
  assert.equal((await requireClinical(uid("legacy-counselor-active"))).accessRole, "counselor");
  assert.equal((await requireStaff(uid("approved-counselor"))).accessRole, "counselor");
});

test("explicitly suspended, disabled or unverified legacy records are denied by requireStaff", {skip: !emulated}, async () => {
  await denied(requireStaff(uid("legacy-counselor-suspended")));
  await denied(requireClinical(uid("legacy-counselor-suspended")));
  await denied(requireStaff(uid("legacy-counselor-unverified")));
  await denied(requireStaff(uid("legacy-staff-disabled")));
  await denied(requireStaff(uid("approved-staff-auth-disabled")));
});

test("administrator callables require a verified, active, configured super-admin", {skip: !emulated}, async () => {
  const previous = process.env.SUPER_ADMIN_UID;
  try {
    process.env.SUPER_ADMIN_UID = uid("admin");
    assert.equal((await requireAdmin(uid("admin"))).accessRole, "admin");
    await denied(requireAdmin(uid("approved-counselor")));
    process.env.SUPER_ADMIN_UID = uid("admin-unverified");
    await denied(requireStaff(uid("admin-unverified")));
    await denied(requireAdmin(uid("admin-unverified")));
    process.env.SUPER_ADMIN_UID = uid("admin-suspended");
    await denied(requireStaff(uid("admin-suspended")));
    await denied(requireAdmin(uid("admin-suspended")));
  } finally {
    if (previous == null) delete process.env.SUPER_ADMIN_UID; else process.env.SUPER_ADMIN_UID = previous;
  }
});
