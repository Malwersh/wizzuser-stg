'use strict';
const crypto = require('node:crypto');
const MAX_ATTEMPTS = 5;
const TTL_SECONDS = 300;
function defineChallenge(event) {
  const session = event.request.session || [];
  const valid = session.every(s => s.challengeName === 'CUSTOM_CHALLENGE');
  const success = valid && session.length > 0 && session.at(-1).challengeResult === true;
  event.response = {
    issueTokens: success && !event.request.userNotFound,
    failAuthentication: !valid || !!event.request.userNotFound || (!success && session.length >= MAX_ATTEMPTS),
  };
  if (!event.response.issueTokens && !event.response.failAuthentication) event.response.challengeName = 'CUSTOM_CHALLENGE';
  return event;
}
function digest(key, id, username, code) {
  return crypto.createHmac('sha256', key).update(JSON.stringify([id, username, code])).digest('hex');
}
function matches(key, record, username, answer, now) {
  if (!record || record.username !== username || record.expiresAt <= now || record.used || record.attempts >= MAX_ATTEMPTS || !/^[0-9]{6}$/.test(answer || '')) return false;
  const expected = Buffer.from(record.digest, 'hex');
  const received = Buffer.from(digest(key, record.id, username, answer), 'hex');
  return expected.length === received.length && crypto.timingSafeEqual(expected, received);
}
module.exports = { defineChallenge, digest, matches, MAX_ATTEMPTS, TTL_SECONDS };
