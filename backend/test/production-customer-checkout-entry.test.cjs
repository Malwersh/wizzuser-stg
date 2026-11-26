'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../src/production/customer-checkout.js'), 'utf8');

function load(environment) {
  const exports = {};
  const calls = [];
  vm.runInNewContext(source, { exports, process: { env: { ENVIRONMENT: environment } }, Buffer,
    require: () => ({ handler: async event => {
      calls.push(event);
      return { statusCode: 201, headers: { 'X-Order-Test': '1' }, body: '{"orderId":"test"}' };
    } }),
  });
  return { ...exports, calls };
}

const event = (resource = '/orders', overrides = {}) => ({
  resource, httpMethod: 'POST', requestContext: { stage: 'production' },
  headers: { authorization: 'Bearer sample' }, body: '{}', ...overrides,
});

test('production container and stage are required before using checkout', async () => {
  const stage = load('staging');
  assert.equal((await stage.handler(event())).statusCode, 404);
  const prod = load('production');
  assert.equal((await prod.handler(event('/orders', { requestContext: { stage: 'staging' } }))).statusCode, 404);
  assert.equal((await prod.handler(event('/payments'))).statusCode, 404);
  assert.deepEqual(stage.calls, []);
  assert.deepEqual(prod.calls, []);
});

test('rejects invalid payloads and mismatched preview actions before invoking order logic', async () => {
  const prod = load('production');
  assert.equal((await prod.handler(event('/orders', { headers: {} }))).statusCode, 401);
  for (const body of ['{', '[]', 'null', 'X'.repeat(64001)]) {
    assert.equal((await prod.handler(event('/orders', { body }))).statusCode, 400);
  }
  assert.equal((await prod.handler(event('/orders', { body: '{"action":"preview_commercial"}' }))).statusCode, 400);
  assert.equal((await prod.handler(event('/orders/commercial-preview'))).statusCode, 400);
  assert.deepEqual(prod.calls, []);
});

test('the production route passes the exact valid request to the same checkout handler', async () => {
  const prod = load('production');
  const request = event('/orders/commercial-preview', { body: '{"action":"preview_commercial","requestId":"a"}' });
  const response = await prod.handler(request);
  assert.equal(response.statusCode, 201);
  assert.equal(response.headers['X-Order-Test'], '1');
  assert.equal(response.headers['Cache-Control'], 'no-store');
  assert.deepEqual(prod.calls, [request]);
  const preflight = await prod.handler(event('/orders', { httpMethod: 'OPTIONS', headers: {} }));
  assert.equal(preflight.statusCode, 204);
  assert.deepEqual(prod.calls, [request]);
});
