'use strict';
const crypto = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const ttlMs = 24 * 60 * 60 * 1000;
const recentLoginSeconds = 5 * 60;
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
  return Boolean(auth && auth.uid &&
    auth.token?.firebase?.sign_in_provider !== 'anonymous' &&
    auth.token?.email_verified === true);
}
function uidOf(request) {
  const uid = request.auth?.uid;
  if (!uid || typeof uid !== 'string') throw new Error('unauthenticated');
  return uid;
}
function recentlyAuthenticated(request, nowMs = Date.now()) {
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  // Anonymous accounts have no reusable credential with which to reauthenticate.
  // Their bearer token already controls the anonymous household.
  if (provider === 'anonymous') return true;
  const seconds = request.auth?.token?.auth_time;
  return typeof seconds === 'number' &&
    seconds <= Math.floor(nowMs / 1000) + 60 &&
    Math.floor(nowMs / 1000) - seconds <= recentLoginSeconds;
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
  // Short-lived deletion tombstones prevent a still-valid ID token from
  // recreating an identity while the Admin SDK removes its Auth credentials.
  const deletion = uid => db.collection('accountDeletions').doc(uid);

  async function createFamily(request) {
    const uid = uidOf(request);
    const name = nonemptyName(request.data?.babyName);
    const familyRef = db.collection('families').doc();
    const babyRef = familyRef.collection('babies').doc();
    return db.runTransaction(async tx => {
      const [existing, deleting] = await Promise.all([
        tx.get(user(uid)), tx.get(deletion(uid)),
      ]);
      if (deleting.exists) throw new Error('account-deleting');
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
    if (!durableAuth(request.auth)) throw new Error('verified-account-required');
    if ((await deletion(uid).get()).exists) throw new Error('account-deleting');
    const profile = await user(uid).get();
    if (!profile.exists) throw new Error('failed-precondition');
    const familyId = profile.data().familyId;
    const code = crypto.randomBytes(32).toString('base64url');
    const expiresAtMs = Date.now()+ttlMs;
    await db.runTransaction(async tx => {
      const [role, household] = await Promise.all([
        tx.get(member(familyId,uid)), tx.get(family(familyId)),
      ]);
      assertMember(role,uid);
      if (role.data().role !== 'owner') throw new Error('permission-denied');
      if (!household.exists || household.data().deleting === true) throw new Error('family-unavailable');
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
    if (!durableAuth(request.auth)) throw new Error('verified-account-required');
    const inviteRef = invite(request.data?.code);
    return db.runTransaction(async tx => {
      const [profile,invitation,deleting] = await Promise.all([
        tx.get(user(uid)),tx.get(inviteRef),tx.get(deletion(uid)),
      ]);
      if (deleting.exists) throw new Error('account-deleting');
      if (profile.exists) throw new Error('already-in-family');
      if (!invitation.exists) throw new Error('invalid-invitation');
      const data = invitation.data();
      if (data.usedAt || data.expiresAt.toMillis()<=Date.now()) throw new Error('expired-or-used');
      const issuer = await tx.get(member(data.familyId,data.createdBy));
      assertMember(issuer,data.createdBy);
      const household = await tx.get(family(data.familyId));
      if (!household.exists || household.data().deleting === true) throw new Error('family-unavailable');
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
    if ((await deletion(uid).get()).exists) throw new Error('account-deleting');
    return db.runTransaction(async tx => {
      const profile = await tx.get(user(uid));
      if (!profile.exists) throw new Error('permission-denied');
      const familyId = profile.data().familyId;
      const [actor,target,targetProfile,household] = await Promise.all([
        tx.get(member(familyId,uid)),tx.get(member(familyId,targetUid)),
        tx.get(user(targetUid)),tx.get(family(familyId)),
      ]);
      if (!household.exists || household.data().deleting === true) throw new Error('family-unavailable');
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

  // Irreversible data deletion. The family remains marked as deleting until
  // ALL descendants, invitations and profiles are gone; retrying the callable
  // after an interrupted cleanup is safe. Authentication credentials are NOT
  // deleted here (other caregivers own their own Firebase Auth accounts).
  async function deleteFamily(request) {
    const uid = uidOf(request);
    const profile = await user(uid).get();
    if (!profile.exists || typeof profile.data().familyId !== 'string') {
      throw new Error('failed-precondition');
    }
    const familyId = profile.data().familyId;
    const householdRef = family(familyId);

    await db.runTransaction(async tx => {
      const [household, ownerMembership] = await Promise.all([
        tx.get(householdRef), tx.get(member(familyId,uid)),
      ]);
      if (!household.exists || household.data().ownerId !== uid) {
        throw new Error('permission-denied');
      }
      // Once marked deleting, the owner's membership may already have been
      // removed by a prior attempt. Their profile and ownerId remain until
      // the final atomic commit, permitting a legitimate retry.
      if (household.data().deleting !== true) {
        if (!ownerMembership.exists || ownerMembership.data().role !== 'owner') {
          throw new Error('permission-denied');
        }
        tx.update(householdRef, {
          deleting: true, deletionRequestedAt: stamp(),
        });
        tx.update(user(uid), {deleting:true});
      }
    });

    // Use bounded batches rather than a single transaction (Firestore's
    // transaction/write limits). Each committed page can safely be retried.
    async function deleteMatching(query, excludeId) {
      while (true) {
        const snapshot = await query.limit(200).get();
        const docs = snapshot.docs.filter(doc => doc.id !== excludeId);
        if (docs.length === 0) break;
        const batch = db.batch();
        for (const doc of docs) batch.delete(doc.ref);
        await batch.commit();
      }
    }
    await deleteMatching(db.collection('familyInvites').where('familyId','==',familyId));
    // This traverses babies/{id}/operations/{id}; deleting only baby docs
    // would orphan their immutable operation journals.
    await db.recursiveDelete(householdRef.collection('babies'));
    await deleteMatching(db.collection('users').where('familyId','==',familyId),uid);
    await db.recursiveDelete(householdRef.collection('members'));

    // The profile and household disappear atomically only after descendants
    // and invitations have been removed. Never report completion earlier.
    await db.runTransaction(async tx => {
      const [latest, ownerProfile] = await Promise.all([
        tx.get(householdRef), tx.get(user(uid)),
      ]);
      if (!latest.exists || latest.data().ownerId !== uid || latest.data().deleting !== true ||
          !ownerProfile.exists || ownerProfile.data().familyId !== familyId) {
        throw new Error('failed-precondition');
      }
      tx.delete(user(uid));
      tx.delete(householdRef);
    });
    return {deleted:true};
  }

  /// An Auth account is separate from the household. Remove its private
  /// membership/profile first; shared caregiver edits remain as a pseudonymous
  /// immutable audit journal. The owner must delete the whole household.
  /// Retained, short-lived markers make failed Admin Auth deletions retryable.
  async function deleteAccount(request) {
    const uid = uidOf(request);
    if (!recentlyAuthenticated(request)) throw new Error('recent-login-required');
    const marker = deletion(uid);
    const profileRef = user(uid);
    const profile = await profileRef.get();
    const markerSnapshot = await marker.get();
    if (!markerSnapshot.exists) {
      if (profile.exists && typeof profile.data().familyId === 'string') {
        const household = await family(profile.data().familyId).get();
        if (household.exists && household.data().ownerId === uid) {
          // Owner deletion must be explicit: this is an irreversible removal
          // of all caregivers' journals, not a silent transfer of ownership.
          if (request.data?.deleteOwnedHousehold !== true) {
            throw new Error('owner-must-delete-household');
          }
        }
      }
      await db.runTransaction(async tx => {
        const [current, markerState] = await Promise.all([
          tx.get(profileRef), tx.get(marker),
        ]);
        if (markerState.exists) return;
        if (current.exists && typeof current.data().familyId === 'string') {
          const household = await tx.get(family(current.data().familyId));
          if (household.exists && household.data().ownerId === uid &&
              request.data?.deleteOwnedHousehold !== true) {
            throw new Error('owner-must-delete-household');
          }
        }
        tx.create(marker, {
          requestedAt:stamp(), expiresAt:timestamp(Date.now()+ttlMs),
        });
      });
    }
    // If an earlier attempt was interrupted, the marker permits a retry.
    const latestProfile = await profileRef.get();
    if (latestProfile.exists && typeof latestProfile.data().familyId === 'string') {
      const familyId = latestProfile.data().familyId;
      const household = await family(familyId).get();
      if (household.exists && household.data().ownerId === uid) {
        await deleteFamily(request);
      } else {
        await db.runTransaction(async tx => {
          const current = await tx.get(profileRef);
          if (!current.exists) return;
          const id = current.data().familyId;
          const home = await tx.get(family(id));
          if (home.exists && home.data().ownerId === uid) {
            throw new Error('owner-must-delete-household');
          }
          tx.delete(profileRef);
          tx.delete(member(id,uid));
        });
      }
    }
    try {
      await admin.auth().deleteUser(uid);
    } catch (error) {
      // A previous attempt can have deleted Auth but timed out before reply.
      if (error.code !== 'auth/user-not-found') throw error;
    }
    return {deleted:true};
  }
  return {createFamily,issueInvite,redeemInvite,revokeMember,deleteFamily,deleteAccount};
}
module.exports = {
  familyService,tokenHash,durableAuth,nonemptyName,recentlyAuthenticated,
  ttlMs,
};
