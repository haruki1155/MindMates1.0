import {after, before, beforeEach, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, serverTimestamp, Timestamp} from 'firebase/firestore';

let environment: RulesTestEnvironment;
before(async () => {
  environment = await initializeTestEnvironment({projectId: 'mind-aid-dialogue-test', firestore: {rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'mind_aid_messages/safe'), {userId: 'owner', conversationId: 'conversation', sender: 'assistant', text: 'original', safetyLevel: 'safeSupport', requiresEscalation: false});
    await setDoc(doc(context.firestore(), 'mind_aid_messages/crisis'), {userId: 'owner', sender: 'assistant', text: 'safety response', safetyLevel: 'crisisOrImmediateRisk', requiresEscalation: true});
  });
});
after(async () => environment.cleanup());
test('display updates are owner-only and cannot mutate safety or text', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const other = environment.authenticatedContext('other').firestore();
  const display = {text: 'Open assessment?', actions: [{type: 'openAssessment', label: 'Open self-assessment', payload: {}}]};
  await assertSucceeds(updateDoc(doc(owner, 'mind_aid_messages/safe'), {paaccDisplay: display}));
  await assertFails(updateDoc(doc(other, 'mind_aid_messages/safe'), {paaccDisplay: display}));
  await assertFails(updateDoc(doc(owner, 'mind_aid_messages/crisis'), {paaccDisplay: display}));
  await assertFails(updateDoc(doc(owner, 'mind_aid_messages/safe'), {text: 'altered', paaccDisplay: display}));
  await assertFails(updateDoc(doc(owner, 'mind_aid_messages/safe'), {safetyLevel: 'highDistress'}));
  await assertFails(updateDoc(doc(owner, 'mind_aid_messages/safe'), {paaccDisplay: {text: 'bad', actions: [{type: 'deleteAccount', label: 'bad', payload: {}}]}}));
});
test('conversation state is owner-only with constrained action schema', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const other = environment.authenticatedContext('other').firestore();
  const path = 'mind_aid_dialogue_state/owner/conversations/conversation';
  const state = {userId: 'owner', conversationId: 'conversation', updatedAt: serverTimestamp(), pending: {sourceMessageId: 'safe', action: {type: 'openAssessment', label: 'Open self-assessment', payload: {}}, expiresAt: Timestamp.fromMillis(Date.now() + 600000)}};
  await assertSucceeds(setDoc(doc(owner, path), state));
  await assertSucceeds(getDoc(doc(owner, path)));
  await assertFails(getDoc(doc(other, path)));
  await assertFails(setDoc(doc(other, path), state));
  await assertFails(updateDoc(doc(owner, path), {userId: 'other', updatedAt: serverTimestamp()}));
  await assertFails(setDoc(doc(owner, path), {...state, pending: {...state.pending, sourceMessageId: 'crisis'}}));
  await assertFails(setDoc(doc(owner, path), {...state, pending: {...state.pending, expiresAt: Timestamp.fromMillis(Date.now() + 3600000)}}));
  await assertSucceeds(updateDoc(doc(owner, path), {pending: null, updatedAt: serverTimestamp()}));
});
test('owner can save local chat turns and another user cannot read them', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const other = environment.authenticatedContext('other').firestore();
  const path = 'mind_aid_messages/local-turn';
  const turn = {
    id: 'local-turn', userId: 'owner', conversationId: 'conversation',
    sender: 'assistant', text: 'A short supportive reply.',
    createdAt: serverTimestamp(), status: 'sent', safetyLevel: 'safeSupport',
    primaryIntent: null, requiresEscalation: false, source: 'local',
    confidence: 0, fallbackReason: '', actions: [],
  };
  await assertSucceeds(setDoc(doc(owner, path), turn));
  await assertSucceeds(getDoc(doc(owner, path)));
  await assertFails(getDoc(doc(other, path)));
});
