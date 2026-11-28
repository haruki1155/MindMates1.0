import {test} from "node:test";
import assert from "node:assert/strict";
import {canManageAnnouncements, validateAnnouncementPayload, announcementMutation} from "./announcements";

const post = {kind: "link", postType: "announcement", audienceRoles: ["student", "teaching", "nonTeaching"], mediaType: "standard", category: "placements", title: "Job fair", body: "Apply today", sourceUrl: "https://example.com/post"};
test("only active approved staff and admins manage announcements", () => {
  for (const role of ["portalStaff", "admin"]) assert.equal(canManageAnnouncements({accessRole: role, staffAccountStatus: "approved", accountStatus: "active"}), true);
  for (const profile of [{accessRole: "counselor"}, {accessRole: "appUser"}, {accessRole: "portalStaff", staffAccountStatus: "pending"}, {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "inactive"}]) assert.equal(canManageAnnouncements(profile), false);
});
test("post validation rejects bad enums, lengths, source and privileged fields", () => {
  assert.equal(validateAnnouncementPayload({...post, title: "  Job fair  "}).title, "Job fair");
  for (const patch of [{kind: "video"}, {category: "other"}, {title: " "}, {title: "a".repeat(161)}, {body: "b".repeat(10001)}, {sourceUrl: "javascript:alert(1)"}, {sourceUrl: "https://user:pass@example.com"}, {sourceUrl: ""}, {status: "published"}, {imageUrl: "file:///private"}]) assert.throws(() => validateAnnouncementPayload({...post, ...patch}));
  assert.throws(() => validateAnnouncementPayload({...post, kind: "original"}));
});
test("draft, publish, edit and archive preserve author and publication timestamp", () => {
  const draft = announcementMutation(null, {action: "saveDraft", expectedRevision: 0, post}, "staff", "now");
  assert.equal(draft.status, "draft"); assert.equal(draft.revision, 1); assert.equal(draft.publishedAt, null);
  const published = announcementMutation(draft, {action: "publish", expectedRevision: 1, post}, "admin", "later");
  assert.equal(published.publishedAt, "later"); assert.equal(published.authorId, "staff");
  const edited = announcementMutation(published, {action: "publish", expectedRevision: 2, post: {...post, title: "Updated"}}, "admin", "last");
  assert.equal(edited.publishedAt, "later"); assert.equal(edited.title, "Updated");
  assert.throws(() => announcementMutation(edited, {action: "saveDraft", expectedRevision: 3, post}, "staff", "x"));
  assert.throws(() => announcementMutation(edited, {action: "publish", expectedRevision: 1, post}, "staff", "x"));
  const archived = announcementMutation(edited, {action: "archive", expectedRevision: 3}, "staff", "x");
  assert.equal(archived.status, "archived"); assert.equal(archived.body, "Apply today");
  assert.throws(() => announcementMutation(archived, {action: "publish", expectedRevision: 4, post}, "staff", "x"));
});

const targeted = {kind: "link", postType: "information", audienceRoles: ["nonTeaching", "student"], mediaType: "video", title: "Campus tour", body: "Watch it", imageUrl: "", sourceUrl: "https://example.com/video"};
test("targeted post validation canonicalises audiences and enforces type/media matrix", () => {
  const valid = validateAnnouncementPayload(targeted);
  assert.deepEqual(valid.audienceRoles, ["student", "nonTeaching"]);
  assert.equal(valid.postType, "information"); assert.equal(valid.mediaType, "video");
  assert.equal("category" in valid, false);
  assert.equal(validateAnnouncementPayload({...targeted, category: "placements"}).category, "placements");
  assert.equal(validateAnnouncementPayload({...targeted, kind: "original", mediaType: "standard", sourceUrl: ""}).kind, "original");
  for (const patch of [
    {postType: "video"}, {postType: undefined}, {mediaType: "audio"}, {mediaType: undefined},
    {audienceRoles: []}, {audienceRoles: "student"}, {audienceRoles: ["student", "student"]}, {audienceRoles: ["counselor"]}, {audienceRoles: [1]}, {audienceRoles: undefined},
    {kind: "original", sourceUrl: ""}, {kind: "original", mediaType: "video", sourceUrl: ""}, {sourceUrl: ""}, {category: "other"},
    {authorId: "x"}, {revision: 3}, {publishedAt: "x"}, {createdAt: "x"},
  ]) assert.throws(() => validateAnnouncementPayload({...targeted, ...patch}), JSON.stringify(patch));
});
test("edits and archives preserve legacy category, author and publication time", () => {
  const legacy = {kind: "link", category: "careerGuidance", title: "Old", body: "Old body", imageUrl: "", sourceUrl: "https://example.com/a", status: "published", authorId: "orig", createdAt: "c", publishedAt: "p", revision: 4};
  const edited = announcementMutation(legacy, {action: "publish", expectedRevision: 4, post: {...targeted, mediaType: "standard"}}, "admin", "now");
  assert.equal(edited.category, "careerGuidance"); assert.equal(edited.authorId, "orig"); assert.equal(edited.publishedAt, "p"); assert.equal(edited.revision, 5);
  assert.deepEqual(edited.audienceRoles, ["student", "nonTeaching"]);
  const archived = announcementMutation(edited, {action: "archive", expectedRevision: 5}, "staff", "later");
  assert.equal(archived.category, "careerGuidance"); assert.equal(archived.postType, "information"); assert.deepEqual(archived.audienceRoles, ["student", "nonTeaching"]); assert.equal(archived.publishedAt, "p");
  const fresh = announcementMutation(null, {action: "saveDraft", expectedRevision: 0, post: {...targeted, mediaType: "standard"}}, "staff", "now");
  assert.equal("category" in fresh, false);
});
test("legacy portal saves without targeting fields keep the post's values or safe defaults", () => {
  const legacyPost = {kind: "link", category: "placements", title: "Job fair", body: "Apply", imageUrl: "", sourceUrl: "https://example.com/post"};
  const created = announcementMutation(null, {action: "publish", expectedRevision: 0, post: legacyPost}, "staff", "now");
  assert.deepEqual(created.audienceRoles, ["student", "teaching", "nonTeaching"]);
  assert.equal(created.postType, "announcement"); assert.equal(created.mediaType, "standard"); assert.equal(created.category, "placements");
  const targeted = {...created, audienceRoles: ["teaching"], postType: "information", mediaType: "video"};
  const edited = announcementMutation(targeted, {action: "publish", expectedRevision: 1, post: {...legacyPost, title: "Edited", postType: null}}, "admin", "later");
  assert.deepEqual(edited.audienceRoles, ["teaching"], "old clients must not widen an existing audience");
  assert.equal(edited.postType, "information"); assert.equal(edited.mediaType, "video"); assert.equal(edited.title, "Edited");
  assert.throws(() => announcementMutation(targeted, {action: "publish", expectedRevision: 1, post: {...legacyPost, audienceRoles: []}}, "admin", "x"));
  assert.throws(() => announcementMutation(null, {action: "publish", expectedRevision: 0, post: {...legacyPost, kind: "original", sourceUrl: "", mediaType: "video"}}, "staff", "x"));
});
