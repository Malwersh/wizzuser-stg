'use strict';

const { handler: checkout } = require('../functions/create-order');

const paths = new Set(['/orders', '/orders/commercial-preview']);
const headers = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization,Content-Type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const reply = (statusCode, code) => ({
  statusCode, headers, body: code ? JSON.stringify({ success: false, code }) : '',
});

exports.handler = async event => {
  if (process.env.ENVIRONMENT !== 'production' ||
      event.requestContext?.stage !== 'production' || !paths.has(event.resource)) {
    return reply(404, 'NOT_FOUND');
  }
  if (event.httpMethod === 'OPTIONS') return reply(204);
  if (event.httpMethod !== 'POST') return reply(405, 'METHOD_NOT_ALLOWED');
  if (!/^Bearer \S+$/.test(event.headers?.Authorization || event.headers?.authorization || '')) {
    return reply(401, 'AUTH_REQUIRED');
  }
  if (event.isBase64Encoded || typeof event.body !== 'string' || Buffer.byteLength(event.body) > 64000) {
    return reply(400, 'INVALID_ORDER_REQUEST');
  }
  let body;
  try { body = JSON.parse(event.body); } catch { return reply(400, 'INVALID_ORDER_REQUEST'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(400, 'INVALID_ORDER_REQUEST');
  const preview = event.resource === '/orders/commercial-preview';
  if (preview ? body.action !== 'preview_commercial' : body.action !== undefined) {
    return reply(400, 'INVALID_ORDER_ACTION');
  }

  const response = await checkout(event);
  if (response.statusCode >= 500) return reply(503, 'CHECKOUT_UNAVAILABLE');
  return { ...response, headers: { ...response.headers, ...headers } };
};
