import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

import {saveOrganizationRecord} from "./index";

if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT});

type Callable = {run: (request: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<unknown>};

const db = getFirestore();
const save = saveOrganizationRecord as unknown as Callable;
const run = `OR${Date.now()}`;
const adminUid = process.env.SUPER_ADMIN_UID ?? "";
const auth = {uid: adminUid};
const collegeA = `${run}-collegeA`;
const collegeB = `${run}-collegeB`;
const deptA = `${run}-deptA`;
const deptB = `${run}-deptB`;
const deptA2 = `${run}-deptA2`;
const saved: FirebaseFirestore.DocumentReference[] = [];
let adminCreated = false;

async function denied(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e: {code?: unknown}) => e?.code === code);
}
async function saveOk(data: Record<string, unknown>): Promise<string> {
  const res = (await save.run({auth, data})) as {id: string};
  const collection = ({college: "colleges", department: "departments", course: "courses"} as Record<string, string>)[String(data.kind)];
  saved.push(db.collection(collection).doc(res.id));
  return res.id;
}

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST && adminUid, "emulator + SUPER_ADMIN_UID required");
  const admin = db.collection("users").doc(adminUid);
  if (!(await admin.get()).exists) {
    adminCreated = true;
    await admin.set({accessRole: "admin", firstName: "Test", lastName: "Admin", email: "a@example.com"});
  }
  await Promise.all([
    db.collection("colleges").doc(collegeA).set({name: `${run} A`, code: `${run}CA`, active: true}),
    db.collection("colleges").doc(collegeB).set({name: `${run} B`, code: `${run}CB`, active: true}),
    db.collection("departments").doc(deptA).set({name: `${run} DA`, code: `${run}DA`, collegeId: collegeA, active: true}),
    db.collection("departments").doc(deptB).set({name: `${run} DB`, code: `${run}DB`, collegeId: collegeB, active: true}),
    db.collection("departments").doc(deptA2).set({name: `${run} DA2`, code: `${run}DA2`, collegeId: collegeA, active: true}),
  ]);
});

after(async () => {
  const docs = [collegeA, collegeB].map((id) => db.collection("colleges").doc(id));
  const depts = [deptA, deptB, deptA2].map((id) => db.collection("departments").doc(id));
  await Promise.all([...docs, ...depts, ...saved].map((r) => r.delete()));
  if (adminCreated) await db.collection("users").doc(adminUid).delete();
});

test("a department name repeats under a different college but not within one", async () => {
  const name = `${run} Information Technology`;
  await saveOk({kind: "department", name, code: `${run}IT1`, collegeId: collegeA});
  await saveOk({kind: "department", name, code: `${run}IT2`, collegeId: collegeB});
  await denied(save.run({auth, data: {kind: "department", name, code: `${run}IT3`, collegeId: collegeA}}), "already-exists");
});

// A course name is unique per COLLEGE, not per department: the roster matcher resolves a course inside
// a college, so two same-named courses in one college would be indistinguishable to it.
test("a course name repeats across colleges but not within one", async () => {
  const name = `${run} BS Information Technology`;
  await saveOk({kind: "course", name, code: `${run}K1`, collegeId: collegeA, departmentId: deptA});
  await denied(save.run({auth, data: {kind: "course", name, code: `${run}K2`, collegeId: collegeA, departmentId: deptA2}}), "already-exists");
  await denied(save.run({auth, data: {kind: "course", name, code: `${run}K3`, collegeId: collegeA, departmentId: deptA}}), "already-exists");
  await saveOk({kind: "course", name, code: `${run}K4`, collegeId: collegeB, departmentId: deptB});
});

test("codes stay unique across parents", async () => {
  await saveOk({kind: "department", name: `${run} Code One`, code: `${run}SAME`, collegeId: collegeA});
  await denied(save.run({auth, data: {kind: "department", name: `${run} Code Two`, code: `${run}SAME`, collegeId: collegeB}}), "already-exists");
  await saveOk({kind: "course", name: `${run} Course Code One`, code: `${run}CSAME`, collegeId: collegeA, departmentId: deptA});
  await denied(save.run({auth, data: {kind: "course", name: `${run} Course Code Two`, code: `${run}CSAME`, collegeId: collegeB, departmentId: deptB}}), "already-exists");
});

test("college names stay globally unique", async () => {
  const name = `${run} Global College`;
  await saveOk({kind: "college", name, code: `${run}GC1`});
  await denied(save.run({auth, data: {kind: "college", name, code: `${run}GC2`}}), "already-exists");
});

test("editing a record keeps its own name and code", async () => {
  const name = `${run} Editable`;
  const id = await saveOk({kind: "department", name, code: `${run}ED`, collegeId: collegeA});
  await save.run({auth, data: {kind: "department", id, name, code: `${run}ED`, collegeId: collegeA}});
  const snap = await db.collection("departments").doc(id).get();
  assert.equal(snap.data()?.name, name);
});
