import {test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp, deleteApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {saveAnnouncement} from "./announcements";
import {saveAnnouncement as callable, previewAnnouncementLink} from "./announcements_callable";
import express from "express";
import {createServer} from "node:http";
import {AddressInfo} from "node:net";

test("transaction persists publication and audit atomically and checks current role", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const app = initializeApp({projectId: "demo-announcements"}, "announcement-transactions");
  const db = getFirestore(app);
  try {
    await db.doc("users/publisher").set({accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"});
    const post = {kind: "original", category: "careerGuidance", title: "Career talk", body: "Join us"};
    const saved = await saveAnnouncement(db, "publisher", {expectedRevision: 0, action: "publish", post});
    assert.equal((await db.doc(`announcements/${saved.id}`).get()).data()?.status, "published");
    assert.equal((await db.collection("admin_audit_logs").where("targetId", "==", saved.id).get()).size, 1);
    await assert.rejects(saveAnnouncement(db, "publisher", {id: saved.id, expectedRevision: 0, action: "publish", post}));
    await db.doc("users/publisher").update({accountStatus: "suspended"});
    await assert.rejects(saveAnnouncement(db, "publisher", {id: saved.id, expectedRevision: 1, action: "archive"}));
    assert.equal((await db.doc(`announcements/${saved.id}`).get()).data()?.revision, 1);
  } finally { await deleteApp(app); }
});

test("HTTP wrapper denies missing/unverified/ineligible identities and publishes with audit", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  // Unsigned synthetic tokens are accepted only by Firebase Admin's explicit Auth-emulator mode.
  const previousAuthHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:19099";
  const app = initializeApp({projectId:"demo-announcements"});
  const db = getFirestore(app);
  const httpApp = express();
  httpApp.use(express.json());
  httpApp.post("/save", (req,res) => callable(req as never,res as never));
  httpApp.post("/preview", (req,res) => previewAnnouncementLink(req as never,res as never));
  const server = createServer(httpApp);
  await new Promise<void>((resolve) => server.listen(0,"127.0.0.1",resolve));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const token = (uid:string,verified=true) => {
    const now = Math.floor(Date.now()/1000);
    return Buffer.from(JSON.stringify({alg:"none",typ:"JWT"})).toString("base64url") + "." + Buffer.from(JSON.stringify({iss:"https://securetoken.google.com/demo-announcements",aud:"demo-announcements",sub:uid,user_id:uid,iat:now,exp:now+3600,auth_time:now,email_verified:verified,firebase:{identities:{},sign_in_provider:"custom"}})).toString("base64url") + ".";
  };
  const post = {kind:"original",category:"placements",title:"HTTP job fair",body:"Synthetic local fixture"};
  const send = (path:string,data:unknown,auth?:string) => fetch(base+path,{method:"POST",headers:{"Content-Type":"application/json",...(auth?{Authorization:`Bearer ${auth}`}:{})},body:JSON.stringify({data})});
  try {
    await getAuth(app).createUser({uid:"http-staff",email:"http-staff@example.invalid",emailVerified:false});
    assert.equal((await send("/save",{})).status,403);
    assert.equal((await send("/save",{},token("http-staff",false))).status,403);
    for (const role of ["portalStaff","admin","counselor","appUser"]) {
      await getAuth(app).createUser({uid:`http-${role}`,email:`http-${role}@example.invalid`,emailVerified:true});
      await db.doc(`users/http-${role}`).set({accessRole:role,staffAccountStatus:"approved",accountStatus:"active"});
    }
    for (const role of ["counselor","appUser"]) {
      assert.equal((await send("/save",{expectedRevision:0,action:"publish",post},token(`http-${role}`))).status,403);
      assert.equal((await send("/preview",{url:"https://example.com"},token(`http-${role}`))).status,403);
    }
    for (const role of ["portalStaff","admin"]) {
      const response = await send("/save",{expectedRevision:0,action:"publish",post},token(`http-${role}`));
      assert.equal(response.status,200);
      const result = (await response.json() as {result:{id:string}}).result;
      assert.equal((await db.doc(`announcements/${result.id}`).get()).data()?.title,"HTTP job fair");
      assert.equal((await db.collection("admin_audit_logs").where("targetId","==",result.id).get()).size,1);
    }
    await db.doc("users/http-portalStaff").update({accountStatus:"suspended"});
    assert.equal((await send("/save",{expectedRevision:0,action:"publish",post},token("http-portalStaff"))).status,403);
  } finally {
    server.closeAllConnections(); await new Promise<void>((resolve)=>server.close(()=>resolve())); await deleteApp(app);
    if(previousAuthHost==null)delete process.env.FIREBASE_AUTH_EMULATOR_HOST;else process.env.FIREBASE_AUTH_EMULATOR_HOST=previousAuthHost;
  }
});
