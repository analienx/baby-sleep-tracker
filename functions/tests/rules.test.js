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
      await db.doc('families/secure/babies/baby').set({name:'Vincent'});
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
    await assertFails(carer.doc(path).update({deleted:true}));
    await assertFails(carer.doc(path).delete());
    await assertFails(carer.doc('families/secure/babies/baby/operations/impersonate')
      .set({...op,actorId:'owner'}));
    await assertFails(carer.doc('families/secure/babies/baby/operations/bad')
      .set({...op,endedAtUtc:new Date('2026-10-18T00:00:00Z')}));
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
