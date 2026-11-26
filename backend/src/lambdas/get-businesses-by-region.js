'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });

// Table names
const regions = require('../utils/customer-regions-313');
const { haversineDistance } = require('../utils/haversine');
const { buildNeighboringRestaurants, previewPageSize } = require('../utils/neighboring-restaurants');
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';

async function list(event, nearby) {
  try {
    // Extract parameters
    const {
      region_id: requestedRegionId,
      latitude, longitude,
      page = '0',
      limit = '20',
      category,
      new: newOnly,
      sort = nearby ? 'distance' : 'default',
      radius_km: requestedRadius = '20',
    } = event.queryStringParameters || {};

    let region_id=requestedRegionId;
    // Validate region_id
    if (!nearby && !region_id) {
      return errorResponse(400, 'MISSING_REGION_ID', 'region_id is required');
    }

    const pageNum = Number(page), requestedLimit = Math.min(Number(limit), nearby ? 100 : 50);
    if(!Number.isInteger(pageNum)||pageNum<0||!Number.isInteger(requestedLimit)||requestedLimit<1)return errorResponse(400,'INVALID_PAGINATION','اختر صفحة وعدد نتائج صالحين.'); // Max 50 per page

    const sdk = { GetCommand, QueryCommand, ScanCommand };
    const regionApi = regions.create({ db: dynamodb, sdk, tables: {
      regions: process.env.REGIONS_TABLE, derived: process.env.REGIONS_DERIVED_TABLE, index: process.env.REGION_INDEX_TABLE,
    } });
    const hasCoordinates = latitude !== undefined || longitude !== undefined;
    if ((nearby || hasCoordinates) && (!String(latitude ?? '').trim() || !String(longitude ?? '').trim())) {
      return errorResponse(400, 'MISSING_PARAMETERS', 'latitude and longitude are required');
    }
    const radiusKm = Number(requestedRadius);
    if (nearby && (!Number.isFinite(radiusKm) || radiusKm <= 0)) return errorResponse(400,'INVALID_RADIUS','اختر مسافة بحث صالحة.');
    const point = hasCoordinates ? { latitude: Number(latitude), longitude: Number(longitude) } : null;
    const resolved = point ? await regionApi.resolve(point.latitude, point.longitude, requestedRegionId) : null;
    if (resolved) region_id = resolved.regionId;
    const deliveryCheck = buildNeighboringRestaurants({ db: dynamodb, sdk, regionApi,
      sourceIp: event.requestContext?.identity?.sourceIp || event.requestContext?.http?.sourceIp });
    if (deliveryCheck && !point) {
      return errorResponse(400, 'DELIVERY_POINT_REQUIRED', 'حدد نقطة التوصيل لعرض المطاعم المتاحة.');
    }
    let coverage;
    try { coverage = await deliveryCheck?.prepare(region_id, point); }
    catch (error) {
      console.warn('Delivery coverage lookup unavailable', { error: error.name });
      return errorResponse(503, 'DELIVERY_CHECK_UNAVAILABLE', 'تعذر التحقق من المطاعم التي توصل إلى عنوانك. حاول مجددًا.');
    }

    const regionPath = resolved?.path || await regionApi.ancestry(region_id);
    const footprint = regionPath[3].base.geometry;
    const box = coverage?.box ?? regions.bounds(footprint);
    const entries = [];
    const seen = new Set();
    const newSince = Date.now() - 30 * 24 * 60 * 60 * 1000;
    let cursor;
    if (!deliveryCheck || coverage) do {
      const batch = await dynamodb.send(new ScanCommand({ TableName: BUSINESSES_TABLE,
        FilterExpression: 'isActive = :active AND ((latitude BETWEEN :s AND :n AND longitude BETWEEN :w AND :e) OR (#addr.latitude BETWEEN :s AND :n AND #addr.longitude BETWEEN :w AND :e))',
        ExpressionAttributeNames: { '#addr': 'address' },
        ExpressionAttributeValues: { ':active': true, ':s': box.south, ':n': box.north, ':w': box.west, ':e': box.east },
        ...(cursor ? { ExclusiveStartKey: cursor } : {}),
      }));
      for (const business of batch.Items || []) {
        if (!business.businessId || seen.has(business.businessId) || (category && business.category !== category) ||
            (deliveryCheck && (business.acceptingOrders === false || business.ordersBlocked === true)) ||
            (nearby && business.acceptingOrders !== true) ||
            (newOnly === 'true' && !(business.createdAt > newSince))) continue;
        const lat = business.latitude ?? business.address?.latitude, lng = business.longitude ?? business.address?.longitude;
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
        const local = regions.contains(footprint, lat, lng);
        const entry = local ? {
          business: { ...business, regionId: region_id },
          distanceKm: point && haversineDistance(point.latitude, point.longitude, lat, lng),
        } : deliveryCheck?.candidate(coverage, business, lat, lng);
        if (entry && (!coverage || entry.distanceKm <= coverage.maxKm) && (!nearby || entry.distanceKm <= radiusKm)) {
          seen.add(business.businessId);
          entries.push(entry);
        }
      }
      cursor = batch.LastEvaluatedKey;
    } while (cursor);
    if (sort === 'rating') {
      entries.sort((a, b) => (b.business.customerRating ?? b.business.rating ?? 0) - (a.business.customerRating ?? a.business.rating ?? 0));
    } else if (coverage || nearby) {
      entries.sort((a, b) => a.distanceKm - b.distanceKm || a.business.businessId.localeCompare(b.business.businessId));
    } else if (sort === 'delivery_time') {
      entries.sort((a, b) => (a.business.deliveryTime || 999) - (b.business.deliveryTime || 999));
    }
    const limitNum = deliveryCheck ? Math.min(requestedLimit, previewPageSize) : requestedLimit;
    const start = pageNum * limitNum;
    const pageEntries = entries.slice(start, start + limitNum);
    let qualified = pageEntries.map(row => row.business);
    if (deliveryCheck && pageEntries.length) {
      try { qualified = await deliveryCheck.qualify(coverage, pageEntries); }
      catch (error) {
        console.warn('Delivery eligibility check unavailable', { error: error.name });
        return errorResponse(503, 'DELIVERY_CHECK_UNAVAILABLE', 'تعذر التحقق من المطاعم التي توصل إلى عنوانك. حاول مجددًا.');
      }
    }
    const byId = new Map(qualified.map(row => [row.businessId, row]));
    const businesses = pageEntries.flatMap(row => {
      const business = byId.get(row.business.businessId);
      return business ? [nearby ? { ...business, distance: Number(row.distanceKm.toFixed(2)) } : business] : [];
    });
    if (deliveryCheck && sort === 'delivery_time') businesses.sort((a, b) => (a.deliveryTime || 999) - (b.deliveryTime || 999));

    return successResponse({
      businesses,
      pagination: {
        page: pageNum, limit: limitNum, total: deliveryCheck ? null : entries.length,
        ...(deliveryCheck ? { candidateTotal: entries.length } : {}),
        hasMore: start + limitNum < entries.length,
      },
      region: { region_id, region_name_ar: null, listingVersion: Date.now() },
      ...(nearby ? { search: { center: point, radius_km: radiusKm, total: deliveryCheck ? null : entries.length, returned: businesses.length } } : {}),
      ...(deliveryCheck ? { includesNeighborRegions: qualified.some(business => business.isNeighborRegion) } : {}),
    });
  } catch (error) {
    if(error.status)return errorResponse(error.status,error.code,error.status===404?'الخدمة غير متاحة في هذه المنطقة حاليًا.':'تعذر التحقق من المنطقة.');
    console.error('❌ Error:', error);
    return errorResponse(500, 'INTERNAL_ERROR', 'Internal server error', {
      message: error.message,
    });
  }
}

exports.handler = event => list(event, false);
exports.nearby = event => list(event, true);

/**
 * Success response helper
 */
function successResponse(data) {
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type,Authorization',
      'Access-Control-Allow-Methods': 'GET,OPTIONS',
    },
    body: JSON.stringify({
      success: true,
      data: data,
      timestamp: new Date().toISOString(),
    }),
  };
}

/**
 * Error response helper
 */
function errorResponse(statusCode, error, message, details = null) {
  const response = {
    success: false,
    error: error,
    message: message,
    timestamp: new Date().toISOString(),
  };

  if (details) {
    response.details = details;
  }

  return {
    statusCode: statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type,Authorization',
      'Access-Control-Allow-Methods': 'GET,OPTIONS',
    },
    body: JSON.stringify(response),
  };
}
