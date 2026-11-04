'use strict';
const crypto = require('node:crypto');
const { digest } = require('./challenge-policy');
function newProof(key, username, time) {
  const id=crypto.randomUUID();
  const answer=crypto.randomBytes(32).toString('hex');
  return {answer,record:{id,username,purpose:'login-proof',expiresAt:time+90,attempts:0,used:false,digest:digest(key,id,username,answer)}};
}
function proofMatches(key, record, username, answer, time) {
  if (!record || record.purpose!=='login-proof' || record.username!==username || record.used || record.expiresAt<=time || !/^[a-f0-9]{64}$/.test(answer || '')) return false;
  const expected=Buffer.from(record.digest,'hex'),actual=Buffer.from(digest(key,record.id,username,answer),'hex');
  return expected.length===actual.length && crypto.timingSafeEqual(expected,actual);
}
module.exports={newProof,proofMatches};
