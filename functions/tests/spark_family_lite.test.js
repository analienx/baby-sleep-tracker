'use strict';
const test = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {serverTimestamp} = require('firebase/firestore');
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require('@firebase/rules-unit-testing');

test('Spark Family Lite: verified caregiver grant, revocation, and durable delete fence', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-little-rest',
    firestore: {rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8')},
  });
  const ownerId = 'lite-owner-20261022';
  const carerId = 'lite-carer-20261022';
  const strangerId = 'lite-stranger-20261022';
  const scope = 'personalSleep/' + ownerId;
  const grant = scope + '/caregivers/' + carerId;
  const ops = scope + '/operations';
  const at = new Date('2026-10-22T08:00:00.000Z');
  const operation = actorId => ({
    schemaVersion: 1, actorId, sessionId: 'nap1', parentIds: [],
    deleted: false, recordedAtUtc: at, startedAtUtc: at,
    endedAtUtc: new Date('2026-10-22T08:30:00.000Z'),
  });
  try {
    const owner = env.authenticatedContext(ownerId, {email_verified:true}).firestore();
    const caregiver = env.authenticatedContext(carerId, {email_verified:true}).firestore();
    const unverified = env.authenticatedContext(carerId, {email_verified:false}).firestore();
    const outsider = env.authenticatedContext(strangerId, {email_verified:true}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const unverifiedOwner = env.authenticatedContext(ownerId, {email_verified:false}).firestore();
    await assertSucceeds(owner.doc(ops+'/one').set(operation(ownerId)));
    await assertFails(caregiver.doc(ops+'/one').get());
    await assertFails(outsider.collection(ops).get());
    await assertFails(anonymous.doc(ops+'/one').get());

    // A malicious caregiver cannot self-enroll or forge a new owner.
    await assertFails(caregiver.doc(grant).set({
      uid: carerId, role:'caregiver', createdAt:at,
    }));
    await assertFails(unverifiedOwner.doc(grant).set({
      uid: carerId, role:'caregiver', createdAt:at,
    }));
    await assertFails(owner.doc(grant).set({
      uid: carerId, role:'owner', createdAt:at,
    }));
    await assertFails(owner.doc(grant).set({
      uid: strangerId, role:'caregiver', createdAt:at,
    }));
    // Owner must permanently mark a journal as shared before any grant.
    // That marker makes old personal-only app erasure fail closed.
    await assertFails(caregiver.doc(scope+'/sharing/state').set({enabled:true}));
    await assertFails(owner.doc(grant).set({
      uid:carerId, role:'caregiver', createdAt:serverTimestamp(),
    }));
    await assertSucceeds(owner.doc(scope+'/sharing/state').set({
      enabled:true, createdAt:serverTimestamp(),
    }));
    await assertFails(owner.doc(scope+'/sharing/state').delete());
    await assertFails(owner.doc(scope+'/sharing/state').update({enabled:false}));
    await assertFails(owner.doc(ops+'/one').delete());
    // The only writer of grants is a verified owner; timestamp must
    // equal server request time, not be forged by the mobile app.
    await assertSucceeds(owner.doc(grant).set({
      uid:carerId, role:'caregiver',
      createdAt:serverTimestamp(),
    }));
    await assertSucceeds(caregiver.doc(grant).get());
    await assertFails(outsider.doc(grant).get());
    await assertFails(caregiver.collection(scope+'/caregivers').get());
    await assertSucceeds(owner.collection(scope+'/caregivers').get());
    await assertFails(unverified.doc(grant).get());
    await assertFails(unverified.doc(ops+'/one').get());
    await assertSucceeds(caregiver.doc(ops+'/one').get());
    await assertSucceeds(caregiver.collection(ops).get());
    await assertSucceeds(caregiver.doc(ops+'/two').set(operation(carerId)));
    await assertSucceeds(owner.doc(ops+'/two').get());

    // Identity checks are not just UI checks: actor spoofing and editing
    // the immutable history are forbidden for both users.
    await assertFails(caregiver.doc(ops+'/forge').set(operation(ownerId)));
    await assertFails(caregiver.doc(ops+'/one').update({deleted:true}));
    await assertFails(caregiver.doc(ops+'/one').delete());
    await assertFails(caregiver.doc(grant).update({role:'owner'}));
    await assertFails(caregiver.doc(grant).delete());
    await assertFails(outsider.doc(ops+'/outsider').set(operation(strangerId)));

    await assertSucceeds(owner.doc(grant).delete());
    await assertFails(caregiver.doc(ops+'/one').get());
    await assertFails(caregiver.collection(ops).get());
    await assertFails(caregiver.doc(ops+'/retry').set(operation(carerId)));
    await assertSucceeds(owner.doc(ops+'/one').get());

    // Regrant then begin deletion: no stale caregiver session may write;
    // the owner may only enumerate and DELETE their own operations.
    await assertSucceeds(owner.doc(grant).set({
      uid:carerId, role:'caregiver',
      createdAt:serverTimestamp(),
    }));
    const state=owner.doc(scope+'/control/state');
    await assertFails(caregiver.doc(scope+'/control/state').set({deleting:true}));
    await assertFails(owner.doc(scope+'/control/state').set({deleting:false}));
    await assertSucceeds(state.set({
      deleting:true,
      requestedAt:serverTimestamp(),
    }));
    await assertFails(caregiver.doc(ops+'/one').get());
    await assertFails(caregiver.doc(ops+'/later').set(operation(carerId)));
    await assertFails(owner.doc(ops+'/later').set(operation(ownerId)));
    await assertFails(owner.doc(grant).set({uid:carerId,role:'caregiver'}));
    await assertFails(state.delete());
    await assertFails(state.update({deleting:false}));
    await assertSucceeds(owner.doc(ops+'/one').delete());
    await assertSucceeds(owner.doc(grant).delete());
    await assertFails(caregiver.doc(ops+'/one').get());
  } finally {
    await env.cleanup();
  }
});
