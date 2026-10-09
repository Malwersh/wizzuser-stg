'use strict';

const https = require('https');

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};

function json(statusCode, body) {
  return { statusCode, headers, body: JSON.stringify(body) };
}

function getHeader(event, name) {
  const headers = event.headers || {};
  const target = String(name || '').toLowerCase();
  for (const [k, v] of Object.entries(headers)) {
    if (String(k).toLowerCase() === target) return v;
  }
  return undefined;
}

function requestJson({ url, method, headers, body }) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method, headers }, (res) => {
      const chunks = [];
      res.on('data', (d) => chunks.push(d));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve({ statusCode: res.statusCode || 0, body: text });
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

exports.handler = async (event) => {
  try {
    const baseUrl = String(process.env.CENTRAL_NOTIFICATIONS_BASE_URL || '').trim();
    const internalKey = String(process.env.CENTRAL_NOTIFICATIONS_INTERNAL_KEY || '').trim();

    if (!baseUrl) return json(500, { message: 'Missing CENTRAL_NOTIFICATIONS_BASE_URL' });
    if (!internalKey) return json(500, { message: 'Missing CENTRAL_NOTIFICATIONS_INTERNAL_KEY' });

    const body = JSON.parse(event.body || '{}');

    const token = String(body.token || '').trim();
    const platform = String(body.platform || '').trim();
    const guestToken = String(body.guestToken || '').trim();
    const deviceId = body.deviceId ? String(body.deviceId).trim() : undefined;

    if (!token) return json(400, { message: 'Missing token' });
    if (!platform) return json(400, { message: 'Missing platform' });
    if (!guestToken) return json(400, { message: 'Missing guestToken' });

    // Optional: require a guest context (prevents this from being used for logged-in user spoofing)
    const auth = String(getHeader(event, 'authorization') || getHeader(event, 'Authorization') || '').trim();
    if (auth && auth.toLowerCase().startsWith('bearer ')) {
      return json(403, { message: 'Guest token registration not allowed for authenticated users' });
    }

    const subjectId = `GUEST_${guestToken}`;

    const url = `${baseUrl.replace(/\/$/, '')}/push/tokens/register`;

    const upstreamPayload = {
      token,
      subjectId,
      app: 'user',
      platform,
      env: 'staging',
      deviceId,
    };

    const resp = await requestJson({
      url,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-internal-key': internalKey,
      },
      body: JSON.stringify(upstreamPayload),
    });

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      console.log('register-guest-push-token: upstream failed', resp.statusCode, resp.body);
      return json(502, { message: 'Upstream registration failed', statusCode: resp.statusCode, body: resp.body });
    }

    return json(200, { ok: true, subjectId });
  } catch (err) {
    console.error('register-guest-push-token error', err);
    return json(500, { message: 'Server error', error: String(err && err.message ? err.message : err) });
  }
};
