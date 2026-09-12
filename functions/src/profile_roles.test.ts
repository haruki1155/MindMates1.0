import assert from "node:assert/strict";
import {test} from "node:test";
import {
  mapLegacyAccessRole,
  mapLegacyPopulationRole,
  resolveProjectId,
} from "./backfill_profiles";
import {canAccessClinicalData, canManageAccess, canReviewVerification} from "./index";

test("migration maps every supported legacy population spelling", () => {
  assert.equal(mapLegacyPopulationRole("student"), "student");
  assert.equal(mapLegacyPopulationRole("faculty"), "teaching");
  assert.equal(mapLegacyPopulationRole("Teaching Personnel"), "teaching");
  assert.equal(mapLegacyPopulationRole("staff"), "nonTeaching");
  assert.equal(mapLegacyPopulationRole("non-teaching"), "nonTeaching");
  assert.equal(mapLegacyPopulationRole("admin"), null);
});

test("migration resolves the repository Firebase project", () => {
  assert.equal(resolveProjectId(), "mindmate-staging");
});

test("least-privilege access policy separates every portal role", () => {
  assert.equal(canReviewVerification("appUser"), false);
  assert.equal(canReviewVerification("portalStaff"), true);
  assert.equal(canAccessClinicalData("portalStaff"), false);
  assert.equal(canAccessClinicalData("counselor"), true);
  assert.equal(canManageAccess("counselor"), false);
  assert.equal(canManageAccess("admin"), true);
});

test("migration does not confuse non-teaching staff with portal access", () => {
  assert.equal(mapLegacyAccessRole("staff"), "appUser");
  assert.equal(mapLegacyAccessRole("counselor"), "counselor");
  assert.equal(mapLegacyAccessRole("admin"), "admin");
});
