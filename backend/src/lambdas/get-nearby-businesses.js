/**
 * Lambda: Get Nearby Businesses
 * API: GET /api/businesses/nearby?latitude=32.0&longitude=44.3&radius_km=20
 * 
 * Purpose: Fetch restaurants near coordinates using Haversine distance
 * الغرض: جلب المطاعم القريبة من إحداثيات باستخدام حساب المسافة Haversine
 * 
 * Flow:
 * 1. Get coordinates and radius from params
 * 2. Scan/Query WhizzMerchants_Businesses
 * 3. Calculate distance for each business
 * 4. Filter by radius
 * 5. Sort by distance
 * 6. Apply limit
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { haversineDistance, sortByDistance } = require('../utils/haversine');

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });

// Table name
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';

/**
 * Lambda handler
 */
exports.handler = async (event) => {
  console.log('🔍 Get Nearby Businesses');
  console.log('Event:', JSON.stringify(event, null, 2));

  try {
    // Extract parameters
    const {
      latitude,
      longitude,
      radius_km = '20',
      limit = '20',
      category,
      sort = 'distance',
    } = event.queryStringParameters || {};

    // Validate parameters
    if (!latitude || !longitude) {
      return errorResponse(400, 'MISSING_PARAMETERS', 'latitude and longitude are required');
    }

    const lat = parseFloat(latitude);
    const lng = parseFloat(longitude);
    const radiusKm = parseFloat(radius_km);
    const limitNum = Math.min(parseInt(limit), 100); // Max 100

    console.log(`📍 Center: ${lat}, ${lng}`);
    console.log(`📏 Radius: ${radiusKm} km`);
    console.log(`🔢 Limit: ${limitNum}`);

    const regionApi=require('../utils/customer-regions-313').create({db:dynamodb,sdk:{GetCommand,QueryCommand,ScanCommand},tables:{regions:process.env.REGIONS_TABLE,derived:process.env.REGIONS_DERIVED_TABLE,index:process.env.REGION_INDEX_TABLE}});
    const selected=await regionApi.resolve(lat,lng);

    // Step 1: Get all active businesses
    // Note: For production with large datasets, consider using GSI with geo-hashing
    const scanParams = {
      TableName: BUSINESSES_TABLE,
      FilterExpression: 'isActive = :active AND acceptingOrders = :accepting',
      ExpressionAttributeValues: {
        ':active': true,
        ':accepting': true,
      },
    };

    // Add category filter if provided
    if (category) {
      scanParams.FilterExpression += ' AND category = :category';
      scanParams.ExpressionAttributeValues[':category'] = category;
    }

    console.log('📊 Scanning businesses...');
    const businesses = (await scanAllItems(scanParams)).filter(b=>require('../utils/customer-regions-313').contains(selected.path[3].base.geometry,b.latitude??b.address?.latitude,b.longitude??b.address?.longitude)).map(b=>({...b,regionId:selected.regionId}));
    console.log(`📦 Found ${businesses.length} active businesses`);

    // Step 2: Calculate distance and filter
    let nearbyBusinesses = businesses
      .map((business) => {
        // Calculate distance
        const distance = haversineDistance(lat, lng, business.latitude, business.longitude);

        return {
          ...business,
          distance: parseFloat(distance.toFixed(2)),
        };
      })
      .filter((business) => business.distance <= radiusKm);

    console.log(`✅ ${nearbyBusinesses.length} businesses within ${radiusKm} km`);

    // Step 3: Sort businesses
    if (sort === 'distance') {
      nearbyBusinesses.sort((a, b) => a.distance - b.distance);
    } else if (sort === 'rating') {
      nearbyBusinesses.sort((a, b) => (b.customerRating ?? b.rating ?? 0) - (a.customerRating ?? a.rating ?? 0));
    }

    // Step 4: Apply limit
    const limitedBusinesses = nearbyBusinesses.slice(0, limitNum);

    // Step 5: Build response
    return successResponse({
      businesses: limitedBusinesses,
      search: {
        center: {
          latitude: lat,
          longitude: lng,
        },
        radius_km: radiusKm,
        total: nearbyBusinesses.length,
        returned: limitedBusinesses.length,
      },
    });
  } catch (error) {
    if(error.status)return errorResponse(error.status,error.code,error.status===404?'الخدمة غير متاحة في هذه المنطقة حاليًا.':'تعذر التحقق من المنطقة.');
    console.error('❌ Error:', error);
    return errorResponse(500, 'INTERNAL_ERROR', 'Internal server error', {
      message: error.message,
    });
  }
};

/**
 * Scan all items from DynamoDB (handles pagination)
 */
async function scanAllItems(params) {
  const items = [];
  let lastEvaluatedKey = null;

  do {
    const scanParams = { ...params };
    if (lastEvaluatedKey) {
      scanParams.ExclusiveStartKey = lastEvaluatedKey;
    }

    const result = await dynamodb.send(new ScanCommand(scanParams));

    if (result.Items) {
      items.push(...result.Items);
    }

    lastEvaluatedKey = result.LastEvaluatedKey;
  } while (lastEvaluatedKey);

  return items;
}

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
