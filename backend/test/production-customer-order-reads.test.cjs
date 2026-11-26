'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createOrderReads } = require('../src/production/customer-order-reads');

const env = {
  ENVIRONMENT: 'production', AWS_REGION: 'us-east-1',
  USER_POOL_ID: 'us-east-1_rNtNKVsVf', USER_POOL_CLIENT_ID: '3e8p0ouglrprpd0a3pc91du0hg',
};

function scenario() {
  const dbCalls = [];
  const list = '/users/{user_id}/orders';
  const detail = '/orders/{orderId}';
  const token = 'header.' + Buffer.from(JSON.stringify({
    sub: 'alice', iss: 'https://cognito-idp.us-east-1.amazonaws.com/' + env.USER_POOL_ID,
    client_id: env.USER_POOL_CLIENT_ID, token_use: 'access',
  })).toString('base64url') + '.signature';
  const owner = { userId: 'alice', userSub: 'alice', orderId: 'order-one', status: 'pending',
    pricing: { total: 6500000 }, financialSnapshot: { private: true }, financialOutcome: 'internal',
    exceptionCancellation: { caseId: 'case-1', state: 'REQUESTED', reviewerNote: 'internal' } };
  const other = { ...owner, userId: 'bob', userSub: 'bob', orderId: 'order-two' };
  const db = { async send(command) {
    const input = command.input;
    dbCalls.push(input);
    if (input.TableName === 'wizz-production-Customers') {
      return { Item: { userId: 'alice', cognitoSub: 'alice', isActive: true } };
    }
    if (input.IndexName === 'GSI_User') return { Items: [owner, other] };
    if (input.Key?.PK === 'ORDER#order-one') return { Item: owner };
    return { Item: other };
  } };
  const cognito = { async send(command) {
    assert.equal(command.input.AccessToken, token);
    return { Username: 'alice', UserAttributes: [{ Name: 'sub', Value: 'alice' }] };
  } };
  const handler = createOrderReads({ db, cognito, env, now: () => Date.parse('2026-11-23T00:00:00Z') });
  const invoke = async (resource, pathParameters, extra = {}) => {
    const response = await handler({ resource, pathParameters, httpMethod: 'GET',
      requestContext: { stage: 'production' }, headers: { Authorization: 'Bearer ' + token }, ...extra });
    return { ...response, data: JSON.parse(response.body) };
  };
  return { list, detail, dbCalls, invoke };
}

test('order history queries production GSI_User and returns only orders owned by the verified subject', async () => {
  const { invoke, list, dbCalls } = scenario();
  const result = await invoke(list, { user_id: 'alice' }, { queryStringParameters: { historyDays: '30', status: 'active' } });
  assert.equal(result.statusCode, 200);
  assert.deepEqual(result.data.orders.map(x => x.orderId), ['order-one']);
  assert.equal(dbCalls[1].ExpressionAttributeValues[':since'], '2026-10-24T00:00:00.000Z');
  assert.equal(result.data.orders[0].financialSnapshot, undefined);
  assert.deepEqual(result.data.orders[0].exceptionCancellation, { caseId: 'case-1', state: 'REQUESTED' });
});

test('order reads reject missing login, another user, and details of another user’s order', async () => {
  const { invoke, list, detail, dbCalls } = scenario();
  assert.equal((await invoke(list, { user_id: 'alice' }, { headers: {} })).statusCode, 401);
  assert.equal(dbCalls.length, 0);
  assert.equal((await invoke(list, { user_id: 'bob' })).statusCode, 403);
  assert.ok(!dbCalls.some(call => call.IndexName === 'GSI_User'));
  assert.equal((await invoke(detail, { orderId: 'order-two' })).statusCode, 404);
  assert.equal((await invoke(detail, { orderId: 'order-one' })).statusCode, 200);
});
