import assert from "node:assert/strict";
import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, setDoc} from "firebase/firestore";
import {deleteObject, getBytes, getMetadata, list, listAll, ref, updateMetadata, uploadBytes} from "firebase/storage";

const projectId = process.env.GCLOUD_PROJECT || "demo-mindmate-clinical-attachments";
const appointmentId = "appointment-1";
const casAppointmentId = "appointment-cas";
const unverifiedAppointmentId = "appointment-unverified";
const path = "counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.pdf";
const casPath = "counseling_session_files/appointment-cas/other-counselor/0123456789abcdef0123456789abcdef.pdf";
const unverifiedPath = "counseling_session_files/appointment-unverified/counselor/0123456789abcdef0123456789abcdef.pdf";
const adminUnverifiedPath = "counseling_session_files/appointment-unverified/admin/0123456789abcdef0123456789abcdef.pdf";
let env: RulesTestEnvironment;

function storageFor(uid: string, emailVerified = true) {
  return env.authenticatedContext(uid, {email_verified: emailVerified}).storage();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    storage: {rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8")},
  });
});

beforeEach(async () => {
  await Promise.all([env.clearFirestore(), env.clearStorage()]);
  await env.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "system_config/security"), {superAdminUid: "admin"}),
      setDoc(doc(firestore, "users/counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/other-counselor"), {
        accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cas"],
      }),
      setDoc(doc(firestore, "users/counselor-unapproved"), {
        accessRole: "counselor", staffAccountStatus: "pending", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor-revoked"), {
        accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor-suspended"), {
        accessRole: "counselor", staffAccountStatus: "disabled", accountStatus: "suspended", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor-legacy-suspended"), {
        accessRole: "counselor", accountStatus: "suspended", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/admin"), {accessRole: "admin", accountStatus: "active"}),
      setDoc(doc(firestore, "users/other-admin"), {
        accessRole: "admin", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/admin-suspended"), {accessRole: "admin", accountStatus: "suspended"}),
      setDoc(doc(firestore, "users/portal-staff"), {
        accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/student"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/student-cas"), {
        accessRole: "appUser", collegeId: "cas", verificationStatus: "verified",
      }),
      setDoc(doc(firestore, "users/student-unverified"), {
        accessRole: "appUser", collegeId: "cite", verificationStatus: "needsReview",
      }),
      setDoc(doc(firestore, `appointments/${appointmentId}`), {
        status: "confirmed", userId: "student", collegeId: "cite", studentVerificationStatus: "verified",
      }),
      setDoc(doc(firestore, `appointments/${casAppointmentId}`), {
        status: "confirmed", userId: "student-cas", collegeId: "cas", studentVerificationStatus: "verified",
      }),
      setDoc(doc(firestore, `appointments/${unverifiedAppointmentId}`), {
        status: "confirmed", userId: "student-unverified", collegeId: "cite", studentVerificationStatus: "needsReview",
      }),
    ]);
  });
});

after(async () => env.cleanup());

const payload = new Uint8Array([1, 2, 3, 4]);
const meta = {
  contentType: "application/pdf",
  customMetadata: {uploadedBy: "counselor", appointmentId},
};

function stripComments(source: string): string {
  return source.replace(/\/\/.*$/gm, "");
}

function extractBlock(source: string, openBraceIndex: number): {body: string; endIndex: number} {
  let depth = 0;
  for (let i = openBraceIndex; i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    else if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) {
        return {body: source.slice(openBraceIndex + 1, i), endIndex: i};
      }
    }
  }
  throw new Error("Unbalanced braces in storage.rules");
}

function parseFunctions(rulesBody: string): Map<string, string> {
  const functions = new Map<string, string>();
  const fnHeader = /\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*\{/g;
  let match: RegExpExecArray | null;
  while ((match = fnHeader.exec(rulesBody)) !== null) {
    const braceStart = rulesBody.indexOf("{", match.index);
    const {body, endIndex} = extractBlock(rulesBody, braceStart);
    functions.set(match[1], body);
    fnHeader.lastIndex = endIndex + 1;
  }
  return functions;
}

function collectFirestoreDocsForRule(
  expr: string,
  functions: Map<string, string>,
): {branches: Array<Set<string>>; allDocs: Set<string>} {
  const expand = (snippet: string, depth = 0): string => {
    if (depth > 12) return snippet;
    let out = "";
    let i = 0;
    while (i < snippet.length) {
      const rest = snippet.slice(i);
      const fnMatch = /^([A-Za-z_][A-Za-z0-9_]*)\s*\(/.exec(rest);
      if (fnMatch && functions.has(fnMatch[1])) {
        const fnName = fnMatch[1];
        const openIdx = i + fnMatch[0].length - 1;
        let parenDepth = 0;
        let closeIdx = openIdx;
        for (let j = openIdx; j < snippet.length; j += 1) {
          if (snippet[j] === "(") parenDepth += 1;
          else if (snippet[j] === ")") {
            parenDepth -= 1;
            if (parenDepth === 0) {
              closeIdx = j;
              break;
            }
          }
        }
        const inner = expand(functions.get(fnName)!, depth + 1);
        const args = expand(snippet.slice(openIdx + 1, closeIdx), depth + 1);
        out += `(${args} && (${inner}))`;
        i = closeIdx + 1;
        continue;
      }
      out += snippet[i];
      i += 1;
    }
    return out;
  };

  const extractDocs = (snippet: string): Set<string> => {
    const docs = new Set<string>();
    const refPattern = /firestore\.(?:get|exists)\(\s*(\/databases\/\(default\)\/documents\/[^)]+)\)/g;
    let match: RegExpExecArray | null;
    while ((match = refPattern.exec(snippet)) !== null) {
      docs.add(match[1].trim());
    }
    return docs;
  };

  const splitTopLevel = (snippet: string, op: "||" | "&&"): string[] => {
    const parts: string[] = [];
    let depth = 0;
    let start = 0;
    for (let i = 0; i < snippet.length; i += 1) {
      const ch = snippet[i];
      if (ch === "(") depth += 1;
      else if (ch === ")") depth -= 1;
      else if (depth === 0 && ch === op[0] && snippet[i + 1] === op[1]) {
        parts.push(snippet.slice(start, i).trim());
        i += 1;
        start = i + 1;
      }
    }
    parts.push(snippet.slice(start).trim());
    return parts.filter(Boolean);
  };

  const branchesOf = (snippet: string): Array<Set<string>> => {
    let s = snippet.trim();
    while (s.startsWith("(") && s.endsWith(")")) {
      let d = 0;
      let wrapsAll = true;
      for (let i = 0; i < s.length - 1; i += 1) {
        if (s[i] === "(") d += 1;
        else if (s[i] === ")") {
          d -= 1;
          if (d === 0) {
            wrapsAll = false;
            break;
          }
        }
      }
      if (!wrapsAll) break;
      s = s.slice(1, -1).trim();
    }
    const orParts = splitTopLevel(s, "||");
    if (orParts.length > 1) {
      return orParts.flatMap(branchesOf);
    }
    const andParts = splitTopLevel(s, "&&");
    if (andParts.length > 1) {
      let acc: Array<Set<string>> = [new Set()];
      for (const part of andParts) {
        const sub = branchesOf(part);
        const next: Array<Set<string>> = [];
        for (const a of acc) {
          for (const b of sub) {
            next.push(new Set([...a, ...b]));
          }
        }
        acc = next;
      }
      return acc;
    }
    return [extractDocs(s)];
  };

  const expanded = expand(expr);
  const branches = branchesOf(expanded);
  const allDocs = new Set<string>();
  for (const branch of branches) {
    for (const docPath of branch) allDocs.add(docPath);
  }
  return {branches, allDocs};
}

test("storage.rules static check enforces <= 2 distinct Firestore docs per authorization branch and preserves other paths", () => {
  const raw = stripComments(readFileSync(resolve(__dirname, "../../storage.rules"), "utf8"));
  const functions = parseFunctions(raw);
  const matchHeader = /\bmatch\s+\/(counseling_session_files|secret_chat_profiles|profile_images)(?:\/(?:\{[A-Za-z0-9_]+\}|[A-Za-z0-9_]+))+\s*\{/g;
  const matchBodies = new Map<string, string>();
  let match: RegExpExecArray | null;
  while ((match = matchHeader.exec(raw)) !== null) {
    const braceStart = match.index + match[0].length - 1;
    const {body, endIndex} = extractBlock(raw, braceStart);
    matchBodies.set(match[1], body);
    matchHeader.lastIndex = endIndex + 1;
  }

  for (const publicImageMatch of ["secret_chat_profiles", "profile_images"]) {
    const body = matchBodies.get(publicImageMatch);
    assert.ok(body, `expected match block for ${publicImageMatch}`);
    assert.equal(/firestore\.(get|exists)/.test(body), false, `${publicImageMatch} must not perform Firestore lookups`);
  }

  const clinicalBody = matchBodies.get("counseling_session_files");
  assert.ok(clinicalBody, "expected match block for counseling_session_files");
  const rulePattern = /\ballow\s+([^:]+):\s*if\s+([^;]+);/g;
  const rules = new Map<string, string>();
  while ((match = rulePattern.exec(clinicalBody)) !== null) {
    rules.set(match[1].trim(), match[2].trim());
  }

  assert.equal(rules.get("list"), "false");
  assert.equal(rules.get("update"), "false");

  for (const op of ["get", "create", "delete"]) {
    const expr = rules.get(op);
    assert.ok(expr, `expected allow ${op} rule`);
    const {branches, allDocs} = collectFirestoreDocsForRule(expr, functions);
    assert.ok(branches.length >= 1, `expected branches for ${op}`);
    for (const branchDocs of branches) {
      assert.ok(
        branchDocs.size <= 2,
        `${op} branch exceeded 2 distinct Firestore documents: ${[...branchDocs].join(", ")}`,
      );
      assert.equal(
        [...branchDocs].some((d) => d.includes("$(studentId)")),
        false,
        `${op} must not read users/$(studentId)`,
      );
    }
    if (op === "create" || op === "delete") {
      assert.equal(
        [...allDocs].some((d) => d.includes("system_config/security")),
        false,
        `super-admin ${op} must be disabled and must not reference system_config/security`,
      );
    }
  }
});

test("approved counselor can upload, view, and delete valid clinical attachments while session is confirmed", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  await assertSucceeds(getMetadata(ref(clinician, path)));
  const bytes = await assertSucceeds(getBytes(ref(clinician, path)));
  assert.deepEqual(new Uint8Array(bytes), payload);
  await assertSucceeds(deleteObject(ref(clinician, path)));
});

test("configured super-admin can view existing attachments, including unverified triage, but cannot upload or delete", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));

  await env.withSecurityRulesDisabled(async (context) => {
    const storage = context.storage();
    await uploadBytes(ref(storage, adminUnverifiedPath), payload, {
      contentType: "application/pdf",
      customMetadata: {uploadedBy: "admin", appointmentId: unverifiedAppointmentId},
    });
  });

  const superAdmin = storageFor("admin");
  await assertSucceeds(getMetadata(ref(superAdmin, path)));
  await assertSucceeds(getBytes(ref(superAdmin, path)));
  await assertSucceeds(getMetadata(ref(superAdmin, adminUnverifiedPath)));

  // Super-admin direct Storage upload and deletion are disabled under Option A1.
  await assertFails(uploadBytes(ref(superAdmin, adminUnverifiedPath.replace("0123", "abcd")), payload, {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "admin", appointmentId: unverifiedAppointmentId},
  }));
  await assertFails(uploadBytes(ref(superAdmin, path.replace("/counselor/", "/admin/")), payload, {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "admin", appointmentId},
  }));
  await assertFails(deleteObject(ref(superAdmin, adminUnverifiedPath)));
  await assertFails(deleteObject(ref(superAdmin, path)));
});

test("two-document limit behavioral proof: counselor does not read users/{student} and super-admin view does not read appointments/{id}", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));

  // Delete student user document: counselor still succeeds using only users/{counselor} + appointments/{id}.
  await env.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), "users/student"));
  });
  await assertSucceeds(getMetadata(ref(clinician, path)));
  await assertSucceeds(uploadBytes(ref(clinician, path.replace("0123", "1111")), payload, meta));

  // Seed existing storage object whose appointment doc does not exist: super-admin view succeeds using only users/{admin} + system_config/security.
  const orphanPath = "counseling_session_files/deleted-appointment/counselor/0123456789abcdef0123456789abcdef.pdf";
  await env.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), orphanPath), payload, meta);
  });
  await assertSucceeds(getMetadata(ref(storageFor("admin"), orphanPath)));
  // Counselor is denied on missing appointment.
  await assertFails(getMetadata(ref(clinician, orphanPath)));
});

test("unauthenticated, students, portal staff, ordinary admins, suspended super-admin, unapproved, revoked, suspended, and cross-college counselors are denied", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));

  // Unauthenticated access denied (get, create, delete).
  const unauth = env.unauthenticatedContext().storage();
  await assertFails(getMetadata(ref(unauth, path)));
  await assertFails(getBytes(ref(unauth, path)));
  await assertFails(uploadBytes(ref(unauth, path.replace("0123", "2222")), payload, meta));
  await assertFails(deleteObject(ref(unauth, path)));

  // Unverified-email counselor and super-admin denied.
  await assertFails(getMetadata(ref(storageFor("counselor", false), path)));
  await assertFails(getBytes(ref(storageFor("counselor", false), path)));
  await assertFails(uploadBytes(ref(storageFor("counselor", false), path.replace("0123", "3333")), payload, meta));
  await assertFails(getMetadata(ref(storageFor("admin", false), path)));
  await assertFails(getBytes(ref(storageFor("admin", false), path)));

  for (const account of [
    "student",
    "student-unverified",
    "portal-staff",
    "other-counselor",
    "counselor-unapproved",
    "counselor-revoked",
    "counselor-suspended",
    "counselor-legacy-suspended",
    "other-admin",
    "admin-suspended",
  ]) {
    const client = storageFor(account);
    await assertFails(getMetadata(ref(client, path)));
    await assertFails(getBytes(ref(client, path)));
    await assertFails(deleteObject(ref(client, path)));
    await assertFails(
      uploadBytes(
        ref(client, path.replace("/counselor/", `/${account}/`).replace("0123", "4444")),
        payload,
        {...meta, customMetadata: {uploadedBy: account, appointmentId}},
      ),
    );
  }

  // Cross-college counselor cannot access CITE; CITE counselor cannot access CAS.
  await assertFails(getMetadata(ref(clinician, casPath)));
  await assertFails(uploadBytes(ref(clinician, casPath.replace("/other-counselor/", "/counselor/")), payload, {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "counselor", appointmentId: casAppointmentId},
  }));

  // Even if system_config/security points to a suspended admin, suspended super-admin is denied.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "system_config/security"), {superAdminUid: "admin-suspended"});
  });
  await assertFails(getMetadata(ref(storageFor("admin-suspended"), path)));
  await assertFails(getMetadata(ref(storageFor("admin"), path)));
});

test("unverified student and missing or untrusted appointment scope projections fail closed for counselors", async () => {
  const clinician = storageFor("counselor");
  await assertFails(getMetadata(ref(clinician, unverifiedPath)));
  await assertFails(uploadBytes(ref(clinician, unverifiedPath), payload, {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "counselor", appointmentId: unverifiedAppointmentId},
  }));

  // Missing appointment denied for counselor (get, create, delete).
  const missingPath = "counseling_session_files/nonexistent-appt/counselor/0123456789abcdef0123456789abcdef.pdf";
  await env.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(ref(context.storage(), missingPath), payload, meta);
  });
  await assertFails(getMetadata(ref(clinician, missingPath)));
  await assertFails(deleteObject(ref(clinician, missingPath)));
  await assertFails(uploadBytes(ref(clinician, missingPath.replace("0123", "5555")), payload, {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "counselor", appointmentId: "nonexistent-appt"},
  }));

  // Missing or untrusted appointment projections fail closed even if users/student is verified in cite.
  const badProjections: Array<Record<string, unknown>> = [
    {status: "confirmed", userId: "student", collegeId: "cite"}, // missing studentVerificationStatus
    {status: "confirmed", userId: "student", studentVerificationStatus: "verified"}, // missing collegeId
    {status: "confirmed", userId: "student", collegeId: "", studentVerificationStatus: "verified"}, // empty collegeId
    {status: "confirmed", userId: "student", collegeId: 123, studentVerificationStatus: "verified"}, // non-string collegeId
    {status: "confirmed", userId: "", collegeId: "cite", studentVerificationStatus: "verified"}, // walk-in / empty userId
    {status: "confirmed", collegeId: "cite", studentVerificationStatus: "verified"}, // missing userId
  ];
  for (const [idx, apptData] of badProjections.entries()) {
    const badId = `appointment-bad-${idx}`;
    const badFile = `counseling_session_files/${badId}/counselor/0123456789abcdef0123456789abcdef.pdf`;
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `appointments/${badId}`), apptData);
      await uploadBytes(ref(context.storage(), badFile), payload, {
        contentType: "application/pdf",
        customMetadata: {uploadedBy: "counselor", appointmentId: badId},
      });
    });
    await assertFails(getMetadata(ref(clinician, badFile)));
    await assertFails(deleteObject(ref(clinician, badFile)));
    await assertFails(
      uploadBytes(ref(clinician, badFile.replace("0123", "6666")), payload, {
        contentType: "application/pdf",
        customMetadata: {uploadedBy: "counselor", appointmentId: badId},
      }),
    );
  }
});

test("appointment scope and lifecycle regressions immediately revoke or reassign counselor access", async () => {
  const clinician = storageFor("counselor");
  const otherClinician = storageFor("other-counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));

  // 1. Student becomes unverified -> counselor immediately loses get, create, delete; super-admin keeps get.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `appointments/${appointmentId}`), {
      status: "confirmed", userId: "student", collegeId: "cite", studentVerificationStatus: "needsReview",
    });
  });
  await assertFails(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "7777")), payload, meta));
  await assertSucceeds(getMetadata(ref(storageFor("admin"), path)));

  // 2. Student moves colleges (cite -> cas) -> CITE counselor loses access; CAS counselor gains get/create.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `appointments/${appointmentId}`), {
      status: "confirmed", userId: "student", collegeId: "cas", studentVerificationStatus: "verified",
    });
  });
  await assertFails(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
  await assertSucceeds(getMetadata(ref(otherClinician, path)));
  await assertSucceeds(uploadBytes(ref(otherClinician, path.replace("/counselor/", "/other-counselor/").replace("0123", "8888")), payload, {
    contentType: "application/pdf",
    customMetadata: {uploadedBy: "other-counselor", appointmentId},
  }));
  // Another counselor still cannot delete someone else's uploaded path segment.
  await assertFails(deleteObject(ref(otherClinician, path)));

  // Restore CITE scope on appointment.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `appointments/${appointmentId}`), {
      status: "confirmed", userId: "student", collegeId: "cite", studentVerificationStatus: "verified",
    });
  });
  await assertSucceeds(getMetadata(ref(clinician, path)));

  // 3. Counselor loses college assignment -> immediate denial on get, create, delete.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/counselor"), {
      accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "active", assignedCollegeIds: ["cas"],
    });
  });
  await assertFails(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "9999")), payload, meta));

  // 4. Staff account becomes suspended -> immediate denial even if assignedCollegeIds includes cite.
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/counselor"), {
      accessRole: "counselor", staffAccountStatus: "approved", accountStatus: "suspended", assignedCollegeIds: ["cite"],
    });
  });
  await assertFails(getMetadata(ref(clinician, path)));
  await assertFails(deleteObject(ref(clinician, path)));
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "aaaa")), payload, meta));
});

test("invalid filenames, MIME types, oversized/empty files, forged metadata, updates, and directory listing are denied", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));

  // Wrong uploader path segment.
  await assertFails(uploadBytes(ref(clinician, path.replace("/counselor/", "/admin/")), payload, meta));
  // Invalid filenames.
  await assertFails(uploadBytes(ref(clinician, "counseling_session_files/appointment-1/counselor/invalid-name.pdf"), payload, meta));
  await assertFails(uploadBytes(ref(clinician, "counseling_session_files/appointment-1/counselor/0123456789abcdef0123456789abcdef.txt"), payload, {
    ...meta, contentType: "text/plain",
  }));
  await assertFails(uploadBytes(ref(clinician, "counseling_session_files/appointment-1/counselor/0123456789ABCDEF0123456789ABCDEF.pdf"), payload, meta));
  // Invalid MIME type.
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "bbbb")), payload, {...meta, contentType: "text/html"}));
  // Oversized (> 5 MB) and empty (0 byte) files.
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "cccc")), new Uint8Array(5 * 1024 * 1024 + 1), meta));
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "dddd")), new Uint8Array(0), meta));
  // Forged metadata (uploadedBy / appointmentId / missing metadata).
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "eeee")), payload, {
    ...meta, customMetadata: {uploadedBy: "admin", appointmentId},
  }));
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "ffff")), payload, {
    ...meta, customMetadata: {uploadedBy: "counselor", appointmentId: casAppointmentId},
  }));
  await assertFails(uploadBytes(ref(clinician, path.replace("0123", "1234")), payload, {
    contentType: "application/pdf",
  }));

  // Forbidden file update (overwrite metadata / overwrite existing path).
  await assertFails(updateMetadata(ref(clinician, path), {customMetadata: {uploadedBy: "counselor", appointmentId, note: "tampered"}}));
  await assertFails(updateMetadata(ref(storageFor("admin"), path), {customMetadata: {uploadedBy: "admin", appointmentId}}));

  // Forbidden directory listing.
  await assertFails(listAll(ref(clinician, "counseling_session_files/appointment-1/counselor")));
  await assertFails(list(ref(clinician, "counseling_session_files/appointment-1"), {maxResults: 10}));
  await assertFails(listAll(ref(storageFor("admin"), "counseling_session_files")));
});

test("clinical evidence becomes read-only after the session is completed", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `appointments/${appointmentId}`), {
      status: "completed", userId: "student", collegeId: "cite", studentVerificationStatus: "verified",
    });
  });
  await assertSucceeds(getMetadata(ref(clinician, path)));
  await assertSucceeds(getMetadata(ref(storageFor("admin"), path)));
  await assertFails(deleteObject(ref(clinician, path)));
  const second = path.replace("0123456789abcdef", "fedcba9876543210");
  await assertFails(uploadBytes(ref(clinician, second), payload, meta));
});

test("denies list/listAll for non-clinical and ordinary-admin callers, rejected/missing users, missing security doc, and accessRole: null fail-closed", async () => {
  const clinician = storageFor("counselor");
  await assertSucceeds(uploadBytes(ref(clinician, path), payload, meta));

  // list / listAll denials across portal-staff, student, other-admin, unauth
  for (const client of [
    storageFor("portal-staff"),
    storageFor("student"),
    storageFor("other-admin"),
    env.unauthenticatedContext().storage(),
  ]) {
    await assertFails(listAll(ref(client, "counseling_session_files/appointment-1/counselor")));
    await assertFails(list(ref(client, "counseling_session_files/appointment-1"), {maxResults: 10}));
  }

  // Rejected counselor, missing users/{uid}, legacy role fallback vs explicit accessRole: null
  await env.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "users/counselor-rejected"), {
        accessRole: "counselor", staffAccountStatus: "rejected", accountStatus: "active", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor-legacy-role"), {
        role: "counselor", assignedCollegeIds: ["cite"],
      }),
      setDoc(doc(firestore, "users/counselor-null-role"), {
        accessRole: null, role: "counselor", assignedCollegeIds: ["cite"],
      }),
    ]);
  });

  const rejected = storageFor("counselor-rejected");
  await assertFails(getBytes(ref(rejected, path)));
  await assertFails(deleteObject(ref(rejected, path)));
  await assertFails(uploadBytes(ref(rejected, path.replace("/counselor/", "/counselor-rejected/").replace("0123", "abcd")), payload, {
    ...meta, customMetadata: {uploadedBy: "counselor-rejected", appointmentId},
  }));

  const noUserDoc = storageFor("no-user-doc");
  await assertFails(getBytes(ref(noUserDoc, path)));
  await assertFails(deleteObject(ref(noUserDoc, path)));
  await assertFails(uploadBytes(ref(noUserDoc, path.replace("/counselor/", "/no-user-doc/").replace("0123", "bcde")), payload, {
    ...meta, customMetadata: {uploadedBy: "no-user-doc", appointmentId},
  }));

  // Legacy role fallback succeeds; explicit accessRole: null fails closed.
  await assertSucceeds(getBytes(ref(storageFor("counselor-legacy-role"), path)));
  await assertFails(getBytes(ref(storageFor("counselor-null-role"), path)));

  // Missing system_config/security denies super-admin reads.
  await env.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), "system_config/security"));
  });
  await assertFails(getMetadata(ref(storageFor("admin"), path)));
  await assertFails(getBytes(ref(storageFor("admin"), path)));
});

test("denies path traversal, extra/missing segments, URL-encoded traversal, non-clinical roots, and distinguishes missing-object errors safely", async () => {
  const clinician = storageFor("counselor");
  const superAdmin = storageFor("admin");
  const badPaths = [
    "counseling_session_files/appointment-1/counselor/../other/0123456789abcdef0123456789abcdef.pdf",
    "counseling_session_files/appointment-1/counselor/sub/0123456789abcdef0123456789abcdef.pdf",
    "counseling_session_files/appointment-1/0123456789abcdef0123456789abcdef.pdf",
    "counseling_session_files/appointment-1/counselor/..%2F0123456789abcdef0123456789abcdef.pdf",
    "backups/2026/export.json",
    "other_private/test.pdf",
  ];
  for (const badPath of badPaths) {
    for (const client of [clinician, superAdmin]) {
      await assertFails(getMetadata(ref(client, badPath)));
      await assertFails(getBytes(ref(client, badPath)));
      await assertFails(uploadBytes(ref(client, badPath), payload, meta));
    }
  }

  // Nonexistent object: authorized callers get storage/object-not-found; unauthorized callers get storage/unauthorized.
  const absentPath = "counseling_session_files/appointment-1/counselor/ffffffffffffffffffffffffffffffff.pdf";
  for (const authorized of [clinician, superAdmin]) {
    await assert.rejects(
      getBytes(ref(authorized, absentPath)),
      (err: {code?: string}) => err?.code === "storage/object-not-found",
    );
  }
  for (const denied of [
    storageFor("portal-staff"),
    storageFor("student"),
    storageFor("other-counselor"),
    storageFor("other-admin"),
  ]) {
    const err = await assertFails(getBytes(ref(denied, absentPath))) as {code?: string};
    assert.equal(err?.code, "storage/unauthorized");
  }
});
