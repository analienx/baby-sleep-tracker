'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {tokenHash,durableAuth,nonemptyName,recentlyAuthenticated,
  ttlMs}=require('../services');
test('only 256-bit base64url tokens accepted; hash hides invitation',()=>{
  const code=crypto.randomBytes(32).toString('base64url');
  assert.equal(tokenHash(code),crypto.createHash('sha256').update(code).digest('hex'));
  assert.equal(tokenHash(code).length,64);
  for(const bad of ['', 'guessable','a'.repeat(42),'!'.repeat(43)]) assert.throws(()=>tokenHash(bad));
});
test('anonymous users cannot redeem or issue invitations',()=>{
  assert.equal(durableAuth({uid:'a',token:{firebase:{sign_in_provider:'anonymous'}}}),false);
  assert.equal(durableAuth({uid:'a',token:{firebase:{sign_in_provider:'password'},
    email_verified:false}}),false);
  assert.equal(durableAuth({uid:'a',token:{firebase:{sign_in_provider:'password'},
    email_verified:true}}),true);
  assert.equal(durableAuth(null),false);
});
test('baby name limits and invite lifetime',()=>{
  assert.equal(nonemptyName(' Demo Baby '),'Demo Baby');
  assert.throws(()=>nonemptyName(' '));
  assert.throws(()=>nonemptyName('x'.repeat(51)));
  assert.equal(ttlMs,86400000);
});
test('destructive account deletion requires a recent password sign-in',()=>{
  const now=Date.UTC(2026,9,20,10,0,0);
  const authTime=Math.floor(now/1000);
  const password={auth:{uid:'owner',token:{auth_time:authTime,
    firebase:{sign_in_provider:'password'}}}};
  assert.equal(recentlyAuthenticated(password,now),true);
  assert.equal(recentlyAuthenticated(password,now+301000),false);
  assert.equal(recentlyAuthenticated({auth:{uid:'owner',token:{
    firebase:{sign_in_provider:'password'}}}},now),false);
  assert.equal(recentlyAuthenticated({auth:{uid:'owner',token:{
    auth_time:authTime+500,firebase:{sign_in_provider:'password'}}}},now),false);
  assert.equal(recentlyAuthenticated({auth:{uid:'temp',token:{
    firebase:{sign_in_provider:'anonymous'}}}},now),true);
});
