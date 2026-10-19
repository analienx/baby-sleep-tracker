'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');

test('create, invite, redeem, revoke via real Auth + Functions emulators', {
  skip: !process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST,
}, async ()=>{
  const {initializeApp,deleteApp}=require('firebase/app');
  const {getAuth,connectAuthEmulator,createUserWithEmailAndPassword}=require('firebase/auth');
  const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
  const suffix=Math.random().toString(36).slice(2);
  const ownerApp=initializeApp({apiKey:'demo-key',projectId:'demo-little-rest',
    appId:'demo:owner:'+suffix},'owner-'+suffix);
  const joinerApp=initializeApp({apiKey:'demo-key',projectId:'demo-little-rest',
    appId:'demo:joiner:'+suffix},'joiner-'+suffix);
  try {
    const ownerAuth=getAuth(ownerApp);
    const joinerAuth=getAuth(joinerApp);
    connectAuthEmulator(ownerAuth,'http://127.0.0.1:9099',{disableWarnings:true});
    connectAuthEmulator(joinerAuth,'http://127.0.0.1:9099',{disableWarnings:true});
    const f1=getFunctions(ownerApp,'europe-west1');
    const f2=getFunctions(joinerApp,'europe-west1');
    connectFunctionsEmulator(f1,'127.0.0.1',5001);
    connectFunctionsEmulator(f2,'127.0.0.1',5001);
    await createUserWithEmailAndPassword(ownerAuth,'owner'+suffix+'@example.test','password123');
    await createUserWithEmailAndPassword(joinerAuth,'joiner'+suffix+'@example.test','password123');
    const created=(await httpsCallable(f1,'createFamily')({babyName:'Vincent'})).data;
    assert.ok(created.familyId&&created.babyId);
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
    await httpsCallable(f1,'revokeMember')({targetUid:joinerAuth.currentUser.uid});
    await assert.rejects(httpsCallable(f2,'issueInvite')({}));
    await assert.rejects(httpsCallable(f1,'revokeMember')({targetUid:ownerAuth.currentUser.uid}));
  } finally {
    await Promise.all([deleteApp(ownerApp),deleteApp(joinerApp)]);
  }
});
