'use strict';

const { SignatureV4 } = require('@smithy/signature-v4');
const { Sha256 } = require('@aws-crypto/sha256-js');
const { writeContext } = require('../functions/shared/address-book-319');

async function locationRequest(method, path, query, payload) {
  const region = process.env.AWS_REGION;
  const hostname = `places.geo.${region}.amazonaws.com`;
  const body = payload === undefined ? undefined : JSON.stringify(payload);
  const signer = new SignatureV4({
    region, service: 'geo-places', sha256: Sha256,
    credentials: {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      sessionToken: process.env.AWS_SESSION_TOKEN,
    },
  });
  const signed = await signer.sign({
    method, protocol: 'https:', hostname, path, query, body,
    headers: { host: hostname, ...(body ? { 'content-type': 'application/json' } : {}) },
  });
  const url = new URL(path, `https://${hostname}`);
  if (query) url.search = new URLSearchParams(query).toString();
  const response = await fetch(url, { method, body, headers: signed.headers, signal: AbortSignal.timeout(7500) });
  if (!response.ok) {
    throw Object.assign(new Error('LOCATION_PROVIDER_FAILED'), { providerStatus: response.status });
  }
  return response.json();
}

function createAddressSearch(db, request = locationRequest) {
  const respond = (statusCode, body) => ({ statusCode, body: JSON.stringify(body) });
  return async event => {
    const userId = event.pathParameters?.user_id;
    if (!userId) return respond(400, { success: false, code: 'INVALID_USER' });

    let input;
    try { input = JSON.parse(event.body); } catch {}
    const query = typeof input?.query === 'string' ? input.query.trim() : '';
    const placeId = input?.placeId;
    const isDetails = typeof placeId === 'string' && /^[A-Za-z0-9._~=-]{1,500}$/.test(placeId);
    if (query ? query.length < 3 || query.length > 160 || placeId !== undefined : !isDetails) {
      return respond(400, { success: false, code: 'INVALID_SEARCH' });
    }

    try {
      await writeContext(db, event, userId);
      if (isDetails) {
        const place = await request('GET', '/v2/place/' + encodeURIComponent(placeId), {
          language: 'ar', 'intended-use': 'Storage',
        });
        const [longitude, latitude] = place.Position || [];
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || place.Address?.Country?.Code3 !== 'IRQ') {
          return respond(404, { success: false, code: 'PLACE_NOT_FOUND' });
        }
        return respond(200, { success: true, place: {
          latitude, longitude, name: place.Title || '', formattedAddress: place.Address.Label || place.Title || '',
        } });
      }

      const data = await request('POST', '/v2/suggest', undefined, {
        QueryText: query, Language: 'ar', BiasPosition: [44.3358, 32.0252],
        Filter: { IncludeCountries: ['IRQ'] }, MaxResults: 7,
      });
      const suggestions = (data.ResultItems || [])
        .filter(item => item.SuggestResultItemType === 'Place' && item.Place?.PlaceId && item.Title)
        .map(item => ({ placeId: item.Place.PlaceId, title: item.Title, subtitle: item.Place.Address?.Label || '' }));
      return respond(200, { success: true, suggestions });
    } catch (error) {
      const status = [401, 403, 409].includes(error.statusCode) ? error.statusCode : 503;
      if (status === 503) console.warn('Address search unavailable', { providerStatus: error.providerStatus });
      return respond(status, { success: false, code: status === 503 ? 'ADDRESS_SEARCH_UNAVAILABLE' : error.code });
    }
  };
}

module.exports = { createAddressSearch, locationRequest };
