'use strict';
const admin = require('firebase-admin');
const {onCall,HttpsError} = require('firebase-functions/v2/https');
const {familyService} = require('./services');
admin.initializeApp();
const handlers = familyService(admin.firestore(),admin);
const errorCodes = {
  'unauthenticated':'unauthenticated','permission-denied':'permission-denied',
  'durable-account-required':'failed-precondition',
  'failed-precondition':'failed-precondition','already-in-family':'already-exists',
  'invalid-invitation':'not-found','expired-or-used':'failed-precondition',
  'invalid-name':'invalid-argument','invalid-code':'invalid-argument',
  'invalid-member':'invalid-argument','last-owner':'failed-precondition',
  'family-unavailable':'failed-precondition','membership-inconsistent':'failed-precondition',
  'rate-limit-exceeded':'resource-exhausted','abuse-configuration-missing':'failed-precondition',
};
function callable(name) {
  // Production callables require attestations. The Firebase emulator accepts
  // synthetic SDK identities without registering debug App Check tokens.
  return onCall({
    region:'europe-west1',maxInstances:10,
    enforceAppCheck: !process.env.FUNCTIONS_EMULATOR,
  },async request => {
    try { return await handlers[name](request); }
    catch(error) {
      const code=errorCodes[error.message];
      if(code) throw new HttpsError(code,error.message);
      console.error('Family operation failed',name,error);
      throw new HttpsError('internal','Family request failed.');
    }
  });
}
exports.createFamily=callable('createFamily');
exports.issueInvite=callable('issueInvite');
exports.redeemInvite=callable('redeemInvite');
exports.revokeMember=callable('revokeMember');
