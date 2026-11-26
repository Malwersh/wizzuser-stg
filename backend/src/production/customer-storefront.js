'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');
const { storefrontFacts } = require('../functions/shared/storefront-facts-170');
const { createAddressSearch } = require('./customer-address-search');
const { wrapCatalog, visible } = require('./branch-menu-catalog');
const db = DynamoDBDocumentClient.from(new DynamoDBClient({ maxAttempts: 2 }));

const addressRoutes = {
  '/users/{user_id}/addresses': {
    GET: require('../functions/get-user-addresses').handler,
    POST: require('../functions/create-address').handler,
  },
  '/users/{user_id}/addresses/{address_id}': {
    GET: require('../functions/get-address').handler,
    PUT: require('../functions/update-address').handler,
    DELETE: require('../functions/delete-address').handler,
  },
  '/users/{user_id}/addresses/{address_id}/set-default': {
    PUT: require('../functions/set-default-address').handler,
  },
  '/users/{user_id}/address-search': {
    POST: createAddressSearch(db),
  },
};

const catalogRoutes = {
  '/api/regions/find-by-coordinates': {
    GET: require('../lambdas/find-region-by-coordinates').handler,
  },
  '/api/businesses/by-region': {
    GET: require('../lambdas/get-businesses-by-region').handler,
  },
  '/api/businesses/nearby': {
    GET: require('../lambdas/get-nearby-businesses').handler,
  },
  '/business/{businessId}': {
    GET: require('../functions/get-business').handler,
  },
  '/business/{businessId}/categories': {
    GET: () => reply(400, { success: false, code: 'INVALID_REQUEST' }),
  },
  '/business/{businessId}/products': {
    GET: require('../functions/get-business-products').handler,
  },
  '/business/{businessId}/working-hours': {
    GET: require('../functions/get-business-working-hours').handler,
  },
  '/api/check-menu-version': {
    POST: require('../lambdas/check-menu-version').handler,
  },
  '/api/check-listing-version': {
    POST: require('../lambdas/check-listing-version').handler,
  },
  '/api/batch-check-versions': {
    POST: require('../lambdas/batch-check-versions').handler,
  },
};

const headers = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization,Content-Type',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};
const reply = (statusCode, data) => ({ statusCode, headers, body: JSON.stringify(data) });
const notFound = () => reply(404, { success: false, code: 'NOT_FOUND' });

function select(record, keys) {
  return Object.fromEntries(keys.filter(key => record[key] != null).map(key => [key, record[key]]));
}

function publicBusiness(business) {
  const result = {
    ...select(business, [
      'businessId', 'business_id', 'businessName', 'business_name', 'name',
      'businessPhotoUrl', 'business_photo_url', 'logoUrl', 'imageUrl',
      'businessType', 'business_type', 'businessTypeId', 'category',
      'publishedCuisineIds', 'regionId', 'latitude', 'longitude', 'isActive', 'is_active',
      'distance', 'acceptingOrders', 'status', 'currentStatus', 'isAvailableNow',
      'isNeighborRegion', 'roadDistanceMeters', 'deliveryTime',
      'isClosed', 'statusMessage', 'minimum_order', 'createdAt', 'created_at',
    ]),
    ...storefrontFacts(business),
  };
  if (business.workingHoursToday) {
    result.workingHoursToday = select(business.workingHoursToday, ['weekday', 'opening', 'closing']);
  }
  if (business.address && typeof business.address === 'object') {
    result.address = select(business.address, [
      'street', 'district', 'city', 'country', 'neighborhood', 'landmark',
      'fullAddress', 'latitude', 'longitude',
    ]);
  } else if (typeof business.address === 'string') {
    result.address = business.address;
  }
  return result;
}

function route(routes, event) {
  if (event.requestContext?.stage !== 'production' || !Object.hasOwn(routes, event.resource)) {
    return undefined;
  }
  return routes[event.resource];
}

async function dispatch(routes, event, catalog = false) {
  const methods = route(routes, event);
  if (!methods) return notFound();
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
  if (!Object.hasOwn(methods, event.httpMethod)) {
    return reply(405, { success: false, code: 'METHOD_NOT_ALLOWED' });
  }
  if (event.isBase64Encoded || (event.body && Buffer.byteLength(event.body) > 32000)) {
    return reply(400, { success: false, code: 'INVALID_REQUEST' });
  }
  try {
    const { httpMethod, pathParameters, queryStringParameters, resource, body } = event;
    let input;
    if (catalog && httpMethod === 'POST') {
      try {
        input = JSON.parse(body);
      } catch {
        return reply(400, { success: false, code: 'INVALID_REQUEST' });
      }
      if (!input || typeof input !== 'object' || Array.isArray(input)) {
        return reply(400, { success: false, code: 'INVALID_REQUEST' });
      }
      for (const [key, id] of [['businesses', 'businessId'], ['regions', 'regionId']]) {
        const rows = input[key];
        if (rows != null && (!Array.isArray(rows) || rows.length > 100 ||
            rows.some(row => typeof row?.[id] !== 'string' || !row[id] || row[id].length > 200))) {
          return reply(400, { success: false, code: 'INVALID_REQUEST' });
        }
      }
    }
    const businessId = pathParameters?.businessId ??
      (resource === '/api/check-menu-version' ? input?.businessId : undefined);
    if (catalog && businessId) {
      const { Item } = await db.send(new GetCommand({
        TableName: process.env.BUSINESSES_TABLE, Key: { businessId }, ConsistentRead: true,
      }));
      if (!visible(Item)) return notFound();

    }
    const request = catalog ? { httpMethod, pathParameters, queryStringParameters, resource, body,
      requestContext: { identity: { sourceIp: event.requestContext.identity?.sourceIp } } } : event;
    const response = await methods[httpMethod](request);
    if (response.statusCode >= 500) {
      return reply(503, { success: false, code: 'SERVICE_UNAVAILABLE', message: 'تعذر إكمال العملية. أعد المحاولة.' });
    }
    if (!catalog || response.statusCode !== 200) {
      return { ...response, headers: { ...response.headers, ...headers } };
    }
    const data = JSON.parse(response.body);
    if (Array.isArray(data.data?.businesses)) {
      data.data.businesses = data.data.businesses.filter(visible).map(publicBusiness);
    }
    if (resource === '/api/batch-check-versions' && Array.isArray(data.businesses)) {
      data.businesses = data.businesses.filter(business => business.isActive === true)
        .map(({ businessName, ...versions }) => versions);
      const rows = [...data.businesses, ...data.regions];
      data.summary = { totalChecked: rows.length, needsUpdate: rows.filter(row => row.needsUpdate).length };
    }
    if (data.business) {
      data.business = { ...publicBusiness(data.business), ...select(data.business, [
        'rating', 'reviewCount', 'averagePreparationMinutes', 'minimumOrderAmountIqd', 'storefrontDeliveryAgreements',
      ]) };
    }
    return reply(response.statusCode, data);
  } catch (error) {
    console.error('Customer API request failed', { code: error.name });
    return reply(503, { success: false, code: 'SERVICE_UNAVAILABLE', message: 'تعذر إكمال العملية. أعد المحاولة.' });
  }
}

exports.addresses = event => dispatch(addressRoutes, event);
exports.catalog = wrapCatalog({ db, catalog: event => dispatch(catalogRoutes, event, true), reply });
