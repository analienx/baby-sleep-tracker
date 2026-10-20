'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');

test('create, invite, redeem, revoke via real Auth + Functions emulators', {
  skip: !process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST,
}, async ()=>{
  const {initializeApp,deleteApp}=require('firebase/app');
  const {getAuth,connectAuthEmulator,createUserWithEmailAndPassword}=require('firebase/auth');
  const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
  const {getFirestore,connectFirestoreEmulator,doc,setDoc,getDoc}=require('firebase/firestore');
  const {initializeApp: initializeAdmin,deleteApp:deleteAdmin}=require('firebase-admin/app');
  const {getFirestore:getAdminFirestore}=require('firebase-admin/firestore');
  const {getAuth:getAdminAuth}=require('firebase-admin/auth');
  const {tokenHash}=require('../services');
  const suffix=Math.random().toString(36).slice(2);
  const ownerApp=initializeApp({apiKey:'demo-key',projectId:'demo-little-rest',
    appId:'demo:owner:'+suffix},'owner-'+suffix);
  const joinerApp=initializeApp({apiKey:'demo-key',projectId:'demo-little-rest',
    appId:'demo:joiner:'+suffix},'joiner-'+suffix);
  const thirdApp=initializeApp({apiKey:'demo-key',projectId:'demo-little-rest',
    appId:'demo:third:'+suffix},'third-'+suffix);
  const adminApp=initializeAdmin({projectId:'demo-little-rest'},'admin-'+suffix);
  const adminDb=getAdminFirestore(adminApp);
  const adminAuth=getAdminAuth(adminApp);
  try {
    const ownerAuth=getAuth(ownerApp);
    const joinerAuth=getAuth(joinerApp);
    const thirdAuth=getAuth(thirdApp);
    connectAuthEmulator(ownerAuth,'http://127.0.0.1:9099',{disableWarnings:true});
    connectAuthEmulator(joinerAuth,'http://127.0.0.1:9099',{disableWarnings:true});
    connectAuthEmulator(thirdAuth,'http://127.0.0.1:9099',{disableWarnings:true});
    const f1=getFunctions(ownerApp,'europe-west1');
    const f2=getFunctions(joinerApp,'europe-west1');
    const f3=getFunctions(thirdApp,'europe-west1');
    connectFunctionsEmulator(f1,'127.0.0.1',5001);
    connectFunctionsEmulator(f2,'127.0.0.1',5001);
    connectFunctionsEmulator(f3,'127.0.0.1',5001);
    await createUserWithEmailAndPassword(ownerAuth,'owner'+suffix+'@example.test','password123');
    await createUserWithEmailAndPassword(joinerAuth,'joiner'+suffix+'@example.test','password123');
    await createUserWithEmailAndPassword(thirdAuth,'third'+suffix+'@example.test','password123');
    const created=(await httpsCallable(f1,'createFamily')({babyName:'Vincent'})).data;
    assert.ok(created.familyId&&created.babyId);
    await assert.rejects(httpsCallable(f1,'issueInvite')({}),
      'an unverified email must not be permitted to issue caregiver invitations');
    for(const auth of [ownerAuth,joinerAuth,thirdAuth]) {
      await adminAuth.updateUser(auth.currentUser.uid,{emailVerified:true});
      await auth.currentUser.getIdToken(true);
    }
    const again=(await httpsCallable(f1,'createFamily')({babyName:'Vincent'})).data;
    assert.deepEqual(again,created,'retries preserve one household');
    const issued=(await httpsCallable(f1,'issueInvite')({})).data;
    assert.equal(issued.code.length,43);
    await assert.rejects(httpsCallable(f2,'redeemInvite')({code:'x'.repeat(43)}));
    const joined=(await httpsCallable(f2,'redeemInvite')({code:issued.code})).data;
    assert.deepEqual(joined,created);
    await assert.rejects(httpsCallable(f2,'redeemInvite')({code:issued.code}));
    await assert.rejects(httpsCallable(f2,'issueInvite')({}),
      'caregivers cannot issue invitations');
    await assert.rejects(httpsCallable(f2,'deleteFamily')({}),
      'caregivers cannot delete the household');

    // Exercise two genuinely distinct Firebase identities against the
    // household journal, not just an in-memory mock or same-UID repository.
    const db1=getFirestore(ownerApp);
    const db2=getFirestore(joinerApp);
    connectFirestoreEmulator(db1,'127.0.0.1',8080);
    connectFirestoreEmulator(db2,'127.0.0.1',8080);
    const operations='families/'+created.familyId+'/babies/'+created.babyId+'/operations/';
    const before=new Date('2026-10-19T07:00:00Z');
    const after=new Date('2026-10-19T07:30:00Z');
    const first={schemaVersion:1,actorId:ownerAuth.currentUser.uid,
      sessionId:'shared',parentIds:[],deleted:false,
      recordedAtUtc:after,startedAtUtc:before,endedAtUtc:null};
    await setDoc(doc(db1,operations+'start'),first);
    assert.equal((await getDoc(doc(db2,operations+'start'))).exists(),true);
    const second={...first,actorId:joinerAuth.currentUser.uid,
      parentIds:['start'],endedAtUtc:after};
    await setDoc(doc(db2,operations+'stop'),second);
    assert.equal((await getDoc(doc(db1,operations+'stop'))).exists(),true);
    // Server permits pending offline ancestors. The client isolates a
    // bad branch while preserving prior committed history.
    await setDoc(doc(db2,operations+'orphan-branch'),{
      ...second,parentIds:['missing-offline-ancestor'],
    });
    assert.equal((await getDoc(doc(db1,operations+'start'))).exists(),true);
    assert.equal((await getDoc(doc(db1,operations+'stop'))).exists(),true);
    await assert.rejects(setDoc(doc(db2,operations+'forged'),
      {...first,actorId:ownerAuth.currentUser.uid}));
    await httpsCallable(f1,'revokeMember')({targetUid:joinerAuth.currentUser.uid});
    await assert.rejects(httpsCallable(f2,'issueInvite')({}));
    await assert.rejects(setDoc(doc(db2,operations+'post-revoke'),second));
    await assert.rejects(httpsCallable(f1,'revokeMember')({targetUid:ownerAuth.currentUser.uid}));
    const lastInvite=(await httpsCallable(f1,'issueInvite')({})).data;
    assert.ok(lastInvite.code);
    // Shared UID + IP quotas are transactional. The same owner can issue five
    // codes per 24-hour bucket (including the initial and caregiver codes).
    for (let n=0;n<3;n++) {
      const next=(await httpsCallable(f1,'issueInvite')({})).data;
      assert.equal(next.code.length,43);
    }
    await assert.rejects(httpsCallable(f1,'issueInvite')({}));
    // Deleting a caregiver account is NOT deleting shared household data.
    await httpsCallable(f3,'redeemInvite')({code:lastInvite.code});
    const thirdDb=getFirestore(thirdApp);
    connectFirestoreEmulator(thirdDb,'127.0.0.1',8080);
    const thirdOp={...first,actorId:thirdAuth.currentUser.uid,
      sessionId:'caregiver-audit',parentIds:[]};
    const thirdUid=thirdAuth.currentUser.uid;
    await setDoc(doc(thirdDb,operations+'contributed'),thirdOp);
    assert.equal((await httpsCallable(f2,'deleteAccount')({})).data.deleted,true,
      'a previously revoked caregiver can still erase their Auth identity');
    assert.equal((await httpsCallable(f3,'deleteAccount')({})).data.deleted,true);
    assert.equal((await adminDb.doc(operations+'contributed').get()).exists,true,
      'pseudonymous shared audit remains after caregiver account deletion');
    assert.equal((await adminDb.doc('users/'+thirdUid).get()).exists,false);
    assert.equal((await adminDb.doc('families/'+created.familyId+
      '/members/'+thirdUid).get()).exists,false);
    await assert.rejects(getAdminAuth(adminApp).getUser(thirdUid),
      'Firebase Authentication account must actually be deleted');
    const caregiverDeletionMarker=await adminDb.doc('accountDeletions/'+thirdUid).get();
    assert.equal(caregiverDeletionMarker.exists,true);
    // Simulate a process interruption after the family was fenced and its
    // owner membership removed. The retained owner profile must permit a
    // safe deletion retry without re-exposing cloud data to mobile clients.
    await adminDb.doc('families/'+created.familyId).update({deleting:true});
    await adminDb.doc('users/'+ownerAuth.currentUser.uid).update({deleting:true});
    await adminDb.doc('families/'+created.familyId+'/members/'+ownerAuth.currentUser.uid).delete();
    const deleted=(await httpsCallable(f1,'deleteFamily')({})).data;
    assert.equal(deleted.deleted,true);
    assert.equal((await adminDb.doc('families/'+created.familyId).get()).exists,false);
    assert.equal((await adminDb.doc(operations+'start').get()).exists,false,
      'recursive deletion must remove immutable child operations');
    assert.equal((await adminDb.doc('familyInvites/'+tokenHash(lastInvite.code)).get()).exists,false,
      'unused invitations must be invalidated and erased');
    assert.equal((await getDoc(doc(db1,'users/'+ownerAuth.currentUser.uid))).exists(),false);
    await assert.rejects(getDoc(doc(db1,operations+'start')),
      'a deleted family cannot be accessed even by its former owner');
    await assert.rejects(httpsCallable(f2,'redeemInvite')({code:lastInvite.code}),
      'a deleted family cannot be rejoined via an old invitation');
    const finalHousehold=(await httpsCallable(f1,'createFamily')({babyName:'To erase'})).data;
    assert.notEqual(finalHousehold.familyId,created.familyId);
    const finalOperation='families/'+finalHousehold.familyId+'/babies/'+
      finalHousehold.babyId+'/operations/audit';
    await setDoc(doc(db1,finalOperation),first);
    await assert.rejects(httpsCallable(f1,'deleteAccount')({}),
      'household owner must explicitly confirm family-wide erasure');
    assert.equal((await adminDb.doc(finalOperation).get()).exists,true);
    const ownerUid=ownerAuth.currentUser.uid;
    assert.equal((await httpsCallable(f1,'deleteAccount')({
      deleteOwnedHousehold:true,
    })).data.deleted,true);
    assert.equal((await adminDb.doc(finalOperation).get()).exists,false,
      'owner account deletion recursively erases household journals');
    await assert.rejects(getAdminAuth(adminApp).getUser(ownerUid),
      'deleting the owner account removes their Auth credentials as well');
  } finally {
    await Promise.all([deleteApp(ownerApp),deleteApp(joinerApp),
      deleteApp(thirdApp),deleteAdmin(adminApp)]);
  }
});
