'use strict';
const test=require('node:test');
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {serverTimestamp}=require('firebase/firestore');
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  require('@firebase/rules-unit-testing');

test('Spark multi-baby: owner-only profiles, per-baby operations and fenced erasure',
  {skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
  const env=await initializeTestEnvironment({
    projectId:'demo-little-rest',
    firestore:{rules:readFileSync(resolve(__dirname,'../../firestore.rules'),'utf8')},
  });
  const ownerUid='multi-baby-owner-20261022';
  const carerUid='multi-baby-carer-20261022';
  const outsiderUid='multi-baby-outsider-20261022';
  const root='personalSleep/'+ownerUid;
  const babyA=root+'/babies/child-alpha-20261022';
  const babyB=root+'/babies/child-beta-20261022';
  const primary=root+'/operations';
  const at=new Date('2026-10-22T09:00:00Z');
  const op=uid=>({schemaVersion:1,actorId:uid,sessionId:'sleep-1',
    parentIds:[],deleted:false,recordedAtUtc:at,startedAtUtc:at,
    endedAtUtc:new Date('2026-10-22T09:30:00Z')});
  try {
    const owner=env.authenticatedContext(ownerUid,{email_verified:true}).firestore();
    const carer=env.authenticatedContext(carerUid,{email_verified:true}).firestore();
    const unverified=env.authenticatedContext(carerUid,{email_verified:false}).firestore();
    const outsider=env.authenticatedContext(outsiderUid,{email_verified:true}).firestore();
    await assertSucceeds(owner.doc(primary+'/old-nap').set(op(ownerUid)));
    await assertFails(carer.collection(root+'/babies').get());
    await assertFails(carer.doc(babyA).set({name:'Impostor',createdAt:serverTimestamp()}));
    await assertFails(outsider.doc(babyA).get());
    await assertSucceeds(owner.doc(babyA).set({
      name:'Child A',createdAt:serverTimestamp(),
    }));
    await assertSucceeds(owner.doc(babyB).set({
      name:'Child B',createdAt:serverTimestamp(),
    }));
    // Renaming Baby 1 creates the primary profile document. Its journal
    // stays at the legacy root: the nested primary collection must stay
    // unreadable so no split journal can form. Account erasure therefore
    // must never list it (that query aborts erasure for renamed owners).
    const babyPrimary=root+'/babies/primary';
    await assertSucceeds(owner.doc(babyPrimary).set({
      name:'First',createdAt:serverTimestamp(),
    }));
    await assertFails(owner.collection(babyPrimary+'/operations').get());
    await assertFails(carer.collection(babyPrimary+'/operations').get());
    await assertFails(owner.doc(root+'/babies/bad-profile').set({
      name:'',createdAt:serverTimestamp(),
    }));
    await assertFails(owner.doc(root+'/babies/evil-fields').set({
      name:'N',createdAt:serverTimestamp(),isAdmin:true,
    }));
    await assertFails(owner.doc(babyA).update({createdAt:serverTimestamp()}));
    await assertSucceeds(owner.doc(babyA).update({name:'Child A renamed'}));
    await assertFails(owner.doc(babyA).delete());

    // Real owner approval, same Family Lite security gate.
    await assertSucceeds(owner.doc(root+'/sharing/state').set({
      enabled:true,createdAt:serverTimestamp(),
    }));
    await assertSucceeds(owner.doc(root+'/caregivers/'+carerUid).set({
      uid:carerUid,role:'caregiver',createdAt:serverTimestamp(),
    }));
    await assertSucceeds(carer.collection(root+'/babies').get());
    await assertSucceeds(carer.doc(babyA).get());
    await assertFails(unverified.collection(root+'/babies').get());
    await assertFails(outsider.collection(root+'/babies').get());
    await assertFails(carer.doc(babyA).update({name:'Hacked'}));
    await assertFails(carer.doc(babyB).delete());
    await assertSucceeds(owner.doc(babyA+'/operations/a-nap').set(op(ownerUid)));
    await assertSucceeds(carer.doc(babyB+'/operations/b-nap').set(op(carerUid)));
    await assertFails(carer.doc(babyA+'/operations/forge').set(op(ownerUid)));
    await assertFails(outsider.doc(babyB+'/operations/forge').set(op(outsiderUid)));
    await assertFails(carer.doc(root+'/babies/not-existing/operations/unknown')
      .set(op(carerUid)));
    const a=await assertSucceeds(owner.collection(babyA+'/operations').get());
    const b=await assertSucceeds(owner.collection(babyB+'/operations').get());
    const legacy=await assertSucceeds(owner.collection(primary).get());
    if(a.docs.length!==1||b.docs.length!==1||legacy.docs.length!==1){
      throw Error('Sleep operations mixed between children or legacy journal');
    }
    await assertSucceeds(owner.doc(root+'/control/state').set({
      deleting:true,requestedAt:serverTimestamp(),
    }));
    await assertFails(carer.doc(babyA+'/operations/a-nap').get());
    await assertFails(carer.doc(babyB+'/operations/new').set(op(carerUid)));
    await assertFails(owner.doc(babyA+'/operations/new').set(op(ownerUid)));
    await assertFails(owner.doc(root+'/babies/newborn').set({
      name:'Newborn',createdAt:serverTimestamp(),
    }));
    await assertSucceeds(owner.doc(babyA+'/operations/a-nap').delete());
    await assertSucceeds(owner.doc(babyA).delete());
    await assertSucceeds(owner.doc(babyB+'/operations/b-nap').delete());
    await assertSucceeds(owner.doc(babyB).delete());
    // Fenced erasure removes the renamed primary profile and its legacy
    // root journal without ever listing the nested primary collection.
    await assertSucceeds(owner.doc(babyPrimary).delete());
    await assertSucceeds(owner.doc(primary+'/old-nap').delete());
  }finally{await env.cleanup()}
});
test('Spark multi-baby: fenced erasure works without any sharing marker (cross-build)',{skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
  const env=await initializeTestEnvironment({projectId:'demo-little-rest',firestore:{rules:readFileSync(resolve(__dirname,'../../firestore.rules'),'utf8')}});
  const uid='multi-baby-solo-20261022'; const root='personalSleep/'+uid;
  const baby=root+'/babies/child-solo-20261022'; const at=new Date('2026-10-22T09:00:00Z');
  const op={schemaVersion:1,actorId:uid,sessionId:'sleep-1',parentIds:[],deleted:false,recordedAtUtc:at,startedAtUtc:at,endedAtUtc:new Date('2026-10-22T09:30:00Z')};
  try{
    const owner=env.authenticatedContext(uid,{email_verified:true}).firestore();
    await assertSucceeds(owner.doc(baby).set({name:'Solo',createdAt:serverTimestamp()}));
    await assertSucceeds(owner.doc(baby+'/operations/s-nap').set(op));
    await assertSucceeds(owner.doc(root+'/operations/old-nap').set(op));
    // No sharing/state exists: profile deletion must still be fence-gated,
    // and the ungated client erasure sequence must be able to complete.
    await assertFails(owner.doc(baby).delete());
    await assertSucceeds(owner.doc(root+'/control/state').set({deleting:true,requestedAt:serverTimestamp()}));
    await assertSucceeds(owner.doc(baby+'/operations/s-nap').delete());
    await assertSucceeds(owner.doc(baby).delete());
    await assertSucceeds(owner.doc(root+'/operations/old-nap').delete());
  }finally{await env.cleanup()}
});
