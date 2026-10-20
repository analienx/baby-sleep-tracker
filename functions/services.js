'use strict';
const crypto = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const ttlMs = 24 * 60 * 60 * 1000;
const codePattern = /^[A-Za-z0-9_-]{43}$/;
function nonemptyName(input) {
  if (typeof input !== 'string') throw new Error('invalid-name');
  const value = input.trim();
  if (value.length < 1 || value.length > 50) throw new Error('invalid-name');
  return value;
}
function tokenHash(code) {
  if (typeof code !== 'string' || !codePattern.test(code)) throw new Error('invalid-code');
  return crypto.createHash('sha256').update(code, 'utf8').digest('hex');
}
function durableAuth(auth) {
  return Boolean(auth && auth.uid && auth.token?.firebase?.sign_in_provider !== 'anonymous');
}
function uidOf(request) {
  const uid = request.auth?.uid;
  if (!uid || typeof uid !== 'string') throw new Error('unauthenticated');
  return uid;
}
function assertMember(snapshot, uid) {
  if (!snapshot.exists || snapshot.data().uid !== uid) throw new Error('permission-denied');
}
// Quotas are updated in the *same transaction* as the restricted action.
// Do not persist IP addresses or expose request headers to Firestore clients.
const quotaWindowMs=24*60*60*1000;
function limitIdentity(request, uid, action) {
  const pepper=process.env.FAMILY_ABUSE_PEPPER ||
    (process.env.FUNCTIONS_EMULATOR ? 'emulator-not-for-production' : null);
  if (!pepper) throw new Error('abuse-configuration-missing');
  const ip=request.rawRequest?.ip || request.rawRequest?.socket?.remoteAddress || 'unknown';
  return {
    uid:crypto.createHash('sha256').update(pepper+':'+action+':uid:'+uid).digest('hex'),
    ip:crypto.createHash('sha256').update(pepper+':'+action+':ip:'+ip).digest('hex'),
  };
}
async function guardRate(tx, db, request, uid, action, uidMax, ipMax) {
  const keys=limitIdentity(request,uid,action);
  const start=Math.floor(Date.now()/quotaWindowMs)*quotaWindowMs;
  const refs=[
    db.collection('familyRateLimits').doc('u-'+keys.uid+'-'+start),
    db.collection('familyRateLimits').doc('i-'+keys.ip+'-'+start),
  ];
  const [a,b]=await Promise.all(refs.map(ref=>tx.get(ref)));
  const counts=[a,b].map(s=>s.exists ? s.data().count : 0);
  if (counts[0]>=uidMax || counts[1]>=ipMax)
    throw new Error('rate-limit-exceeded');
  for(let i=0;i<refs.length;i++) {
    tx.set(refs[i],{count:counts[i]+1,
      expireAt:Timestamp.fromMillis(start+2*quotaWindowMs)});
  }
}
function familyService(db, admin) {
  const stamp = () => FieldValue.serverTimestamp();
  const timestamp = ms => Timestamp.fromMillis(ms);
  const user = uid => db.collection('users').doc(uid);
  const family = id => db.collection('families').doc(id);
  const member = (id, uid) => family(id).collection('members').doc(uid);
  const invite = code => db.collection('familyInvites').doc(tokenHash(code));

  async function createFamily(request) {
    const uid = uidOf(request);
    const name = nonemptyName(request.data?.babyName);
    const familyRef = db.collection('families').doc();
    const babyRef = familyRef.collection('babies').doc();
    return db.runTransaction(async tx => {
      const existing = await tx.get(user(uid));
      if (existing.exists) {
        return {familyId: existing.data().familyId, babyId: existing.data().babyId};
      }
      await guardRate(tx,db,request,uid,'createFamily',2,10);
      tx.create(familyRef, {ownerId:uid, createdAt:stamp(), schemaVersion:1});
      tx.create(babyRef, {name, createdAt:stamp()});
      tx.create(member(familyRef.id,uid), {uid,role:'owner',joinedAt:stamp()});
      tx.create(user(uid), {familyId:familyRef.id,babyId:babyRef.id});
      return {familyId:familyRef.id,babyId:babyRef.id};
    });
  }
  async function issueInvite(request) {
    const uid = uidOf(request);
    if (!durableAuth(request.auth)) throw new Error('durable-account-required');
    const profile = await user(uid).get();
    if (!profile.exists) throw new Error('failed-precondition');
    const familyId = profile.data().familyId;
    const code = crypto.randomBytes(32).toString('base64url');
    const expiresAtMs = Date.now()+ttlMs;
    await db.runTransaction(async tx => {
      const role = await tx.get(member(familyId,uid));
      assertMember(role,uid);
      if (role.data().role !== 'owner') throw new Error('permission-denied');
      await guardRate(tx,db,request,uid,'issueInvite',5,30);
      tx.create(invite(code), {
        familyId,createdBy:uid,expiresAt:timestamp(expiresAtMs),
        createdAt:stamp(),usedAt:null,usedBy:null,
      });
    });
    return {code, expiresAt:new Date(expiresAtMs).toISOString()};
  }
  async function redeemInvite(request) {
    const uid = uidOf(request);
    if (!durableAuth(request.auth)) throw new Error('durable-account-required');
    const inviteRef = invite(request.data?.code);
    return db.runTransaction(async tx => {
      const [profile,invitation] = await Promise.all([tx.get(user(uid)),tx.get(inviteRef)]);
      if (profile.exists) throw new Error('already-in-family');
      if (!invitation.exists) throw new Error('invalid-invitation');
      const data = invitation.data();
      if (data.usedAt || data.expiresAt.toMillis()<=Date.now()) throw new Error('expired-or-used');
      const issuer = await tx.get(member(data.familyId,data.createdBy));
      assertMember(issuer,data.createdBy);
      const babies = await tx.get(family(data.familyId).collection('babies').limit(1));
      if (babies.empty) throw new Error('family-unavailable');
      tx.create(member(data.familyId,uid),{uid,role:'caregiver',joinedAt:stamp()});
      tx.create(user(uid),{familyId:data.familyId,babyId:babies.docs[0].id});
      tx.update(inviteRef,{usedAt:stamp(),usedBy:uid});
      return {familyId:data.familyId,babyId:babies.docs[0].id};
    });
  }
  async function revokeMember(request) {
    const uid = uidOf(request);
    const targetUid = request.data?.targetUid;
    if (typeof targetUid!=='string'||!targetUid||targetUid===uid) throw new Error('invalid-member');
    return db.runTransaction(async tx => {
      const profile = await tx.get(user(uid));
      if (!profile.exists) throw new Error('permission-denied');
      const familyId = profile.data().familyId;
      const [actor,target,targetProfile] = await Promise.all([
        tx.get(member(familyId,uid)),tx.get(member(familyId,targetUid)),tx.get(user(targetUid)),
      ]);
      if (!actor.exists||actor.data().role!=='owner'||!target.exists) throw new Error('permission-denied');
      if (target.data().role==='owner') throw new Error('last-owner');
      if (!targetProfile.exists||targetProfile.data().familyId!==familyId) {
        throw new Error('membership-inconsistent');
      }
      tx.delete(member(familyId,targetUid));
      tx.delete(user(targetUid));
      return {revoked:true};
    });
  }
  return {createFamily,issueInvite,redeemInvite,revokeMember};
}
module.exports = {familyService,tokenHash,durableAuth,nonemptyName,ttlMs};
