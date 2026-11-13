const {before, beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, writeBatch, serverTimestamp} = require('firebase/firestore');
let env;
const projectId = 'demo-mindmate-messaging-security';
before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8')}});
});
after(async () => {if(env) await env.cleanup()});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db,'users/student'),{accessRole:'appUser',collegeId:'CITE',firstName:'Ana',middleName:'',lastName:'Santos',name:'Ana Santos'}),
      setDoc(doc(db,'users/other'),{accessRole:'appUser',collegeId:'CITE'}),
      setDoc(doc(db,'users/counselor'),{accessRole:'counselor',staffAccountStatus:'approved',accountStatus:'active'}),
      setDoc(doc(db,'users/counselor2'),{accessRole:'counselor',staffAccountStatus:'approved',accountStatus:'active'}),
      setDoc(doc(db,'users/staff'),{accessRole:'portalStaff'}),
      setDoc(doc(db,'users/admin'),{accessRole:'admin'})
    ]);
  });
});
const db = (id, verified=false) => env.authenticatedContext(id, verified ? {email_verified:true} : {}).firestore();
async function studentSend(firestore, name='Ana Santos', id='m1') {
  const batch = writeBatch(firestore);
  batch.set(doc(firestore,'counselor_threads/student'),{
    userId:'student',collegeId:'CITE',updatedAt:serverTimestamp(),
    lastStudentMessageAt:serverTimestamp(),lastStudentMessageId:id,studentName:name
  },{merge:true});
  batch.set(doc(firestore,`counselor_threads/student/messages/${id}`),{
    senderId:'student',senderRole:'user',text:'Hello',createdAt:serverTimestamp()
  });
  return batch.commit();
}
test('verified student name and atomic new message allowed', async () => {
  await assertSucceeds(studentSend(db('student')));
  const counselor = db('counselor',true);
  const thread = await assertSucceeds(getDoc(doc(counselor,'counselor_threads/student')));
  assert.equal(thread.data().studentName,'Ana Santos');
});
test('forged name rejected', async () => {
  await assertFails(studentSend(db('student'),'Fake Name'));
});
test('cannot create a thread with a fabricated unread timestamp alone', async () => {
  const student = db('student');
  await assertFails(setDoc(doc(student,'counselor_threads/student'),{
    userId:'student',collegeId:'CITE',updatedAt:serverTimestamp(),
    lastStudentMessageAt:serverTimestamp(),lastStudentMessageId:'missing'
  }));
});
test('counselor reply must be tied to a new message', async () => {
  await studentSend(db('student'));
  const counselor = db('counselor',true);
  await assertFails(setDoc(doc(counselor,'counselor_threads/student'),{
    updatedAt:serverTimestamp(),lastCounselorMessageAt:serverTimestamp(),lastCounselorMessageId:'missing'
  },{merge:true}));
  const batch = writeBatch(counselor);
  batch.update(doc(counselor,'counselor_threads/student'),{
    updatedAt:serverTimestamp(),lastCounselorMessageAt:serverTimestamp(),lastCounselorMessageId:'reply1'
  });
  batch.set(doc(counselor,'counselor_threads/student/messages/reply1'),{
    senderId:'counselor',senderRole:'counselor',text:'Hello back',createdAt:serverTimestamp()
  });
  await assertSucceeds(batch.commit());
});
test('counselor read receipts are isolated by counselor uid', async () => {
  await studentSend(db('student'));
  const counselor = db('counselor',true);
  const other = db('counselor2',true);
  const receipt = doc(counselor,'counselor_inbox_reads/counselor/threads/student');
  await assertSucceeds(setDoc(receipt,{readAt:serverTimestamp()}));
  await assertFails(getDoc(doc(other,'counselor_inbox_reads/counselor/threads/student')));
  await assertFails(setDoc(doc(other,'counselor_inbox_reads/counselor/threads/student'),{readAt:serverTimestamp()}));
  await assertSucceeds(setDoc(doc(other,'counselor_inbox_reads/counselor2/threads/student'),{readAt:serverTimestamp()}));
});
test('other students, staff and admin cannot read counseling thread', async () => {
  await studentSend(db('student'));
  for (const id of ['other','staff','admin']) {
    await assertFails(getDoc(doc(db(id,true),'counselor_threads/student')));
  }
  await assertFails(getDoc(doc(db('counselor'),'counselor_threads/student')));
});
test('student may mark own counselor reply as read', async () => {
  await studentSend(db('student'));
  await assertSucceeds(setDoc(doc(db('student'),'counselor_threads/student'),{studentReadAt:serverTimestamp()},{merge:true}));
});
