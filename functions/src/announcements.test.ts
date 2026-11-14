import {test} from "node:test";
import assert from "node:assert/strict";
import {canManageAnnouncements, validateAnnouncementPayload, announcementMutation} from "./announcements";

const post = {kind: "link", category: "placements", title: "Job fair", body: "Apply today", sourceUrl: "https://example.com/post"};
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
