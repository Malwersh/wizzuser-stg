/**
 * Lambda: Check Delivery Availability
 * API: POST /api/businesses/{businessId}/serves-address
 * 
 * Purpose: Check if a restaurant can deliver to a specific address
 * الغرض: التحقق من إمكانية توصيل مطعم لعنوان محدد
 * 
 * Flow:
 * 1. Get businessId from path parameters
 * 2. Get address coordinates from body
 * 3. Fetch business details
 * 4. Calculate distance
 * 5. Check against delivery range
 * 6. Calculate delivery fee (dynamic based on distance)
 * 7. Return availability result
 */

const AWS = require('aws-sdk');
const { haversineDistance } = require('../utils/haversine');

const dynamodb = new AWS.DynamoDB.DocumentClient();

// Table name
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';

// Default delivery settings
const DEFAULT_MAX_DELIVERY_DISTANCE = 20; // km
const DEFAULT_DELIVERY_FEE = 2000; // IQD
const ADDITIONAL_FEE_PER_KM = 500; // IQD per km beyond base distance
const BASE_DISTANCE = 10; // km (free delivery within this distance)

/**
 * Lambda handler
 */
exports.handler = async (event) => {
  console.log('🚚 Check Delivery Availability');
  console.log('Event:', JSON.stringify(event, null, 2));

  try {
    // Extract businessId from path
    const businessId = event.pathParameters?.businessId;
    if (!businessId) {
      return errorResponse(400, 'MISSING_BUSINESS_ID', 'businessId is required');
    }

    // Parse request body
    const body = JSON.parse(event.body || '{}');
    const { latitude, longitude, region_id } = body;

    if (!latitude || !longitude) {
      return errorResponse(400, 'MISSING_COORDINATES', 'latitude and longitude are required');
    }

    const lat = parseFloat(latitude);
    const lng = parseFloat(longitude);

    console.log(`🏪 Business: ${businessId}`);
    console.log(`📍 Address: ${lat}, ${lng}`);

    // Step 1: Get business details
    const businessResult = await dynamodb
      .get({
        TableName: BUSINESSES_TABLE,
        Key: { businessId },
      })
      .promise();

    if (!businessResult.Item) {
      return errorResponse(404, 'BUSINESS_NOT_FOUND', 'المطعم غير موجود');
    }

    const business = businessResult.Item;

    // Check if business is active and accepting orders
    if (!business.isActive || !business.acceptingOrders) {
      return successResponse({
        serves: false,
        businessId,
        businessName: business.businessName,
        distance: null,
        reason: 'BUSINESS_NOT_ACCEPTING_ORDERS',
        message: 'المطعم غير متاح حالياً',
        estimatedDeliveryTime: null,
        deliveryFee: null,
      });
    }

    // Step 2: Calculate distance
    const distance = haversineDistance(lat, lng, business.latitude, business.longitude);
    console.log(`📏 Distance: ${distance.toFixed(2)} km`);

    // Step 3: Check delivery range
    const maxDeliveryDistance = business.maxDeliveryDistance || DEFAULT_MAX_DELIVERY_DISTANCE;
    const serves = distance <= maxDeliveryDistance;

    console.log(`${serves ? '✅' : '❌'} Serves: ${serves} (max: ${maxDeliveryDistance} km)`);

    // Step 4: Calculate delivery fee
    let deliveryFee = null;
    if (serves) {
      deliveryFee = business.deliveryFee || DEFAULT_DELIVERY_FEE;

      // Add extra fee for distance beyond base distance
      if (distance > BASE_DISTANCE) {
        const extraDistance = distance - BASE_DISTANCE;
        const extraFee = Math.ceil(extraDistance) * ADDITIONAL_FEE_PER_KM;
        deliveryFee += extraFee;
        console.log(`💰 Extra fee: ${extraFee} IQD for ${extraDistance.toFixed(2)} km`);
      }
    }

    // Step 5: Build response
    const response = {
      serves,
      businessId,
      businessName: business.businessName,
      distance: parseFloat(distance.toFixed(2)),
      estimatedDeliveryTime: serves ? business.deliveryTime || '30-40 min' : null,
      deliveryFee,
      message: serves
        ? 'التوصيل متاح لهذا العنوان'
        : `العنوان خارج نطاق التوصيل (الحد الأقصى ${maxDeliveryDistance} كم)`,
      reason: serves ? null : 'OUTSIDE_DELIVERY_RANGE',
      maxDeliveryDistance,
    };

    return successResponse(response);
  } catch (error) {
    console.error('❌ Error:', error);
    return errorResponse(500, 'INTERNAL_ERROR', 'Internal server error', {
      message: error.message,
    });
  }
};

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
      'Access-Control-Allow-Methods': 'POST,OPTIONS',
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
      'Access-Control-Allow-Methods': 'POST,OPTIONS',
    },
    body: JSON.stringify(response),
  };
}
