'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');

test('family rules block strangers, privilege escalation, updates and revocation', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async ()=>{
  const env=await initializeTestEnvironment({
    projectId:'demo-little-rest',
    firestore:{rules:readFileSync(resolve(__dirname,'../../firestore.rules'),'utf8')},
  });
  try {
    await env.withSecurityRulesDisabled(async context=>{
      const db=context.firestore();
      await db.doc('families/secure').set({ownerId:'owner'});
      await db.doc('families/secure/babies/baby').set({name:'Demo Baby'});
      await db.doc('families/secure/members/owner').set({uid:'owner',role:'owner'});
      await db.doc('families/secure/members/carer').set({uid:'carer',role:'caregiver'});
      await db.doc('families/other').set({ownerId:'outsider'});
      await db.doc('families/other/babies/other').set({name:'Another'});
      await db.doc('families/other/members/outsider').set({uid:'outsider',role:'owner'});
    });
    const owner=env.authenticatedContext('owner').firestore();
    const carer=env.authenticatedContext('carer').firestore();
    const stranger=env.authenticatedContext('outsider').firestore();
    const anon=env.unauthenticatedContext().firestore();
    const path='families/secure/babies/baby/operations/op1';
    const start=new Date('2026-10-19T08:00:00Z');
    const end=new Date('2026-10-19T08:25:00Z');
    const op={schemaVersion:1,actorId:'carer',sessionId:'s1',parentIds:[],
      deleted:false,recordedAtUtc:start,startedAtUtc:start,endedAtUtc:end};
    await assertSucceeds(carer.doc(path).set(op));
    await assertSucceeds(owner.doc(path).get());
    await assertFails(stranger.doc(path).get());
    await assertFails(anon.doc(path).get());
    await assertFails(carer.doc('families/other/babies/other/operations/no').set(op));
    await assertFails(carer.doc('families/secure/members/carer').update({role:'owner'}));
    await assertFails(owner.doc('families/secure/members/new').set({role:'owner',uid:'new'}));
    await assertFails(owner.doc('familyInvites/guess').get());
    await assertFails(owner.doc('accountDeletions/owner').get());
    await assertFails(owner.doc('accountDeletions/owner').set({requestedAt:start}));
    await assertFails(owner.doc('familyRateLimits/counter').get());
    await assertFails(owner.doc('familyRateLimits/counter').set({count:0}));
    await assertSucceeds(carer.doc('families/secure/babies/baby/operations/pending-parent')
      .set({...op,parentIds:['pending-offline-parent']}));
    await assertFails(carer.doc(path).update({deleted:true}));
    await assertFails(carer.doc(path).delete());
    await assertFails(carer.doc('families/secure/babies/baby/operations/impersonate')
      .set({...op,actorId:'owner'}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/bad')
      .set({...op,endedAtUtc:new Date('2026-10-18T00:00:00Z')}));
    // Parent references must be well-formed even though their *existence*
    // cannot be required during offline replay: a parent may still be queued.
    await assertFails(carer.doc('families/secure/babies/baby/operations/typed')
      .set({...op,parentIds:[true]}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/typed-later')
      .set({...op,parentIds:['valid',42]}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/empty')
      .set({...op,parentIds:['']}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/self')
      .set({...op,parentIds:['self']}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/late-type')
      .set({...op,parentIds:[...Array.from({length:19},(_,i)=>'p'+i),false]}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/duplicate')
      .set({...op,parentIds:['valid','valid']}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/too-many')
      .set({...op,parentIds:Array.from({length:21},(_,i)=>'parent'+i)}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/tombstone')
      .set({...op,deleted:true,parentIds:[]}));
    // Account deletion fencing precedes removal of Auth credentials. A still
    // valid identity token cannot submit another immutable operation.
    await env.withSecurityRulesDisabled(async ctx=>{
      await ctx.firestore().doc('accountDeletions/carer').set({requestedAt:start});
    });
    await assertFails(carer.doc('users/carer').get());
    await assertFails(carer.doc(path).get());
    await assertFails(carer.doc('families/secure/babies/baby/operations/deleting-user').set(op));
    // Deletion is a server-only state transition. Once marked, no stale
    // membership document may permit any more reads or writes.
    await env.withSecurityRulesDisabled(async ctx=>{
      await ctx.firestore().doc('families/secure').update({deleting:true});
    });
    await assertFails(owner.doc(path).get());
    await assertFails(carer.doc('families/secure/babies/baby/operations/during-delete').set(op));
    await assertFails(carer.doc('families/secure/members/owner').get());
    // Simulate server-side revocation; no cached client retains cloud access.
    await env.withSecurityRulesDisabled(async ctx=>{
      await ctx.firestore().doc('families/secure/members/carer').delete();
    });
    await assertFails(carer.doc('families/secure/babies/baby/operations/revoked').set(op));
    await assertFails(carer.doc(path).get());
  } finally {
    await env.cleanup();
  }
});


test('Spark personal sleep journal is user-private and append-only until explicit self-erasure', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-little-rest',
    firestore: { rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8') },
  });
  try {
    const owner = env.authenticatedContext('personal-owner').firestore();
    const other = env.authenticatedContext('personal-other').firestore();
    const unauth = env.unauthenticatedContext().firestore();
    const ownerPath = 'personalSleep/personal-owner/operations/sleep-1';
    const otherPath = 'personalSleep/personal-other/operations/sleep-1';
    const start = new Date('2026-10-20T06:00:00Z');
    const end = new Date('2026-10-20T06:30:00Z');
    const valid = {
      schemaVersion: 1, actorId: 'personal-owner', sessionId: 'sleep-1',
      parentIds: [], deleted: false, recordedAtUtc: end,
      startedAtUtc: start, endedAtUtc: end,
    };
    await assertSucceeds(owner.doc(ownerPath).set(valid));
    await assertSucceeds(owner.doc(ownerPath).get());
    await assertSucceeds(owner.collection('personalSleep/personal-owner/operations').get());
    await assertFails(other.doc(ownerPath).get());
    await assertFails(other.collection('personalSleep/personal-owner/operations').get());
    await assertFails(unauth.doc(ownerPath).get());
    await assertFails(owner.doc(otherPath).set({ ...valid, actorId: 'personal-other' }));
    await assertFails(owner.doc('personalSleep/personal-owner').set({ role: 'admin' }));
    await assertFails(owner.doc(ownerPath).update({ deleted: true }));
    await assertFails(owner.doc('personalSleep/personal-owner/operations/forged')
      .set({ ...valid, actorId: 'personal-other' }));
    await assertFails(owner.doc('personalSleep/personal-owner/operations/bad-time')
      .set({ ...valid, endedAtUtc: new Date('2026-10-19T06:00:00Z') }));
    await assertFails(other.doc(ownerPath).delete());
    await assertSucceeds(owner.doc(ownerPath).delete());
    await assertSucceeds(owner.doc(ownerPath).get());
  } finally {
    await env.cleanup();
  }
});
