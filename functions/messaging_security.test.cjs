const {before, beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, deleteDoc, getDoc, writeBatch, serverTimestamp, Timestamp} = require('firebase/firestore');
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
      setDoc(doc(db,'users/pendingCounselor'),{accessRole:'counselor',staffAccountStatus:'pending',accountStatus:'active'}),
      setDoc(doc(db,'users/suspendedCounselor'),{accessRole:'counselor',staffAccountStatus:'approved',accountStatus:'suspended'}),
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

test('pending and suspended counselors are denied read/write on threads, messages, and receipts', async () => {
  await studentSend(db('student'));
  for (const id of ['pendingCounselor', 'suspendedCounselor']) {
    const actor = db(id, true);
    await assertFails(getDoc(doc(actor, 'counselor_threads/student')));
    await assertFails(getDoc(doc(actor, 'counselor_threads/student/messages/m1')));
    await assertFails(setDoc(doc(actor, 'counselor_threads/student/messages/r1'), {
      senderId: id, senderRole: 'counselor', text: 'Denied', createdAt: serverTimestamp(),
    }));
    await assertFails(getDoc(doc(actor, `counselor_inbox_reads/${id}/threads/student`)));
    await assertFails(setDoc(doc(actor, `counselor_inbox_reads/${id}/threads/student`), {
      readAt: serverTimestamp(),
    }));
  }
});

test('non-counselors (admin, staff, student) are denied read and write on counselor_inbox_reads', async () => {
  await studentSend(db('student'));
  for (const id of ['admin', 'staff', 'student']) {
    const actor = db(id, true);
    await assertFails(getDoc(doc(actor, 'counselor_inbox_reads/counselor/threads/student')));
    await assertFails(setDoc(doc(actor, 'counselor_inbox_reads/counselor/threads/student'), {
      readAt: serverTimestamp(),
    }));
    await assertFails(getDoc(doc(actor, `counselor_inbox_reads/${id}/threads/student`)));
    await assertFails(setDoc(doc(actor, `counselor_inbox_reads/${id}/threads/student`), {
      readAt: serverTimestamp(),
    }));
  }
});

test('cross-counselor updateDoc and deleteDoc are denied on counselor_inbox_reads', async () => {
  await studentSend(db('student'));
  const counselor = db('counselor', true);
  const other = db('counselor2', true);
  const receipt = doc(counselor, 'counselor_inbox_reads/counselor/threads/student');
  await assertSucceeds(setDoc(receipt, {readAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(other, 'counselor_inbox_reads/counselor/threads/student'), {
    readAt: serverTimestamp(),
  }));
  await assertFails(deleteDoc(receipt));
  await assertFails(deleteDoc(doc(other, 'counselor_inbox_reads/counselor/threads/student')));
});

test('counselor_inbox_reads rejects extra keys, client timestamps, and nonexistent thread', async () => {
  await studentSend(db('student'));
  const counselor = db('counselor', true);
  const receipt = doc(counselor, 'counselor_inbox_reads/counselor/threads/student');
  await assertFails(setDoc(receipt, {readAt: serverTimestamp(), extra: true}));
  await assertFails(setDoc(receipt, {readAt: Timestamp.fromMillis(1700000000000)}));
  await assertFails(setDoc(doc(counselor, 'counselor_inbox_reads/counselor/threads/nonexistent'), {
    readAt: serverTimestamp(),
  }));
});

test('atomic 3-write counselor reply and mark-read batch succeeds with matching timestamps', async () => {
  await studentSend(db('student'));
  const counselor = db('counselor', true);
  const batch = writeBatch(counselor);
  batch.update(doc(counselor, 'counselor_threads/student'), {
    updatedAt: serverTimestamp(),
    lastCounselorMessageAt: serverTimestamp(),
    lastCounselorMessageId: 'reply_atomic',
  });
  batch.set(doc(counselor, 'counselor_threads/student/messages/reply_atomic'), {
    senderId: 'counselor',
    senderRole: 'counselor',
    text: 'Atomic reply',
    createdAt: serverTimestamp(),
  });
  batch.set(doc(counselor, 'counselor_inbox_reads/counselor/threads/student'), {
    readAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  const thread = await getDoc(doc(counselor, 'counselor_threads/student'));
  const receipt = await getDoc(doc(counselor, 'counselor_inbox_reads/counselor/threads/student'));
  assert.equal(
    thread.data().lastCounselorMessageAt.toMillis(),
    receipt.data().readAt.toMillis(),
  );
});

test('student and counselor field tampering attempts are rejected', async () => {
  await studentSend(db('student'));
  const student = db('student');
  const counselor = db('counselor', true);
  // Student cannot forge counselor reply metadata
  await assertFails(updateDoc(doc(student, 'counselor_threads/student'), {
    lastCounselorMessageAt: serverTimestamp(),
    lastCounselorMessageId: 'forged',
  }));
  // Student cannot bump lastStudentMessageAt without a linked message
  await assertFails(updateDoc(doc(student, 'counselor_threads/student'), {
    updatedAt: serverTimestamp(),
    lastStudentMessageAt: serverTimestamp(),
    lastStudentMessageId: 'missing_msg',
  }));
  // Counselor cannot overwrite studentReadAt, lastStudentMessageAt, or collegeId
  await assertFails(updateDoc(doc(counselor, 'counselor_threads/student'), {
    studentReadAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(counselor, 'counselor_threads/student'), {
    lastStudentMessageAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(counselor, 'counselor_threads/student'), {
    collegeId: 'CBA',
  }));
});
