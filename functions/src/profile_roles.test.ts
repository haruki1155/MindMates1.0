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

test("migration resolves an explicit Firebase project override", () => {
  const originalGcloud = process.env.GCLOUD_PROJECT;
  const originalGoogleCloud = process.env.GOOGLE_CLOUD_PROJECT;
  try {
    process.env.GCLOUD_PROJECT = "demo-mindmate-phase7";
    process.env.GOOGLE_CLOUD_PROJECT = "ignored-project";
    assert.equal(resolveProjectId(), "demo-mindmate-phase7");
  } finally {
    if (originalGcloud == null) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = originalGcloud;
    if (originalGoogleCloud == null) delete process.env.GOOGLE_CLOUD_PROJECT;
    else process.env.GOOGLE_CLOUD_PROJECT = originalGoogleCloud;
  }
});

test("migration falls back to the repository Firebase project", () => {
  const originalGcloud = process.env.GCLOUD_PROJECT;
  const originalGoogleCloud = process.env.GOOGLE_CLOUD_PROJECT;
  try {
    delete process.env.GCLOUD_PROJECT;
    delete process.env.GOOGLE_CLOUD_PROJECT;
    assert.equal(resolveProjectId(), "mindmate-staging");
  } finally {
    if (originalGcloud == null) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = originalGcloud;
    if (originalGoogleCloud == null) delete process.env.GOOGLE_CLOUD_PROJECT;
    else process.env.GOOGLE_CLOUD_PROJECT = originalGoogleCloud;
  }
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
