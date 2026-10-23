/**
 * Lambda: Find Region By Coordinates
 * API: GET /api/regions/find-by-coordinates?latitude=32.0&longitude=44.3
 * 
 * Purpose: Convert GPS coordinates to region_id using H3 geospatial index
 * الغرض: تحويل إحداثيات GPS إلى region_id باستخدام فهرس H3 الجغرافي
 * 
 * Flow:
 * 1. Receive latitude/longitude
 * 2. Convert to H3 cell (resolution 9)
 * 3. Query REGION_INDEX_TABLE for region_id
 * 4. Query WizzCentral_Regions for region details
 * 5. Return region information
 */

const {DynamoDBClient} = require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand} = require('@aws-sdk/lib-dynamodb');
const { latLngToCell } = require('h3-js');

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

// Table names
const REGION_INDEX_TABLE = requireEnv('REGION_INDEX_TABLE');
const REGIONS_TABLE = process.env.REGIONS_TABLE || 'WizzCentral_Regions';

// H3 resolution (9 = ~0.1 km² cells)
const H3_RESOLUTION = 9;

/**
 * Lambda handler
 */
exports.handler = async (event) => {
  console.log('🗺️ Find Region By Coordinates');


  try {
    // Extract parameters
    const { latitude, longitude, resolution } = event.queryStringParameters || {};

    // Validate parameters
    if (!latitude || !longitude) {
      return errorResponse(400, 'MISSING_PARAMETERS', 'latitude and longitude are required');
    }

    const lat = parseFloat(latitude);
    const lng = parseFloat(longitude);
    const h3Resolution = resolution ? parseInt(resolution) : H3_RESOLUTION;

    // Validate coordinate ranges
    if (isNaN(lat) || lat < -90 || lat > 90) {
      return errorResponse(400, 'INVALID_LATITUDE', 'Latitude must be between -90 and 90');
    }

    if (isNaN(lng) || lng < -180 || lng > 180) {
      return errorResponse(400, 'INVALID_LONGITUDE', 'Longitude must be between -180 and 180');
    }

    console.log(`📍 Coordinates: ${lat}, ${lng}`);
    console.log(`🔍 H3 Resolution: ${h3Resolution}`);

    // Step 1: Convert coordinates to H3 cell
    const h3Cell = latLngToCell(lat, lng, h3Resolution);
    console.log(`🔢 H3 Cell: ${h3Cell}`);

    // Step 2: Query REGION_INDEX_TABLE
    const indexResult = await dynamodb.send(new GetCommand({
        TableName: REGION_INDEX_TABLE,
        Key: { index_cell_id: h3Cell },
      }));

    if (!indexResult.Item) {
      console.log('⚠️ No region found for this H3 cell');
      return errorResponse(404, 'REGION_NOT_FOUND', 'لا توجد منطقة خدمة لهذه الإحداثيات', {
        latitude: lat,
        longitude: lng,
        h3Cell,
      });
    }

    const regionId = indexResult.Item.regionId;
    console.log(`✅ Found region_id: ${regionId}`);

    // Step 3: Query WizzCentral_Regions for details
    const regionResult = await dynamodb.send(new GetCommand({
        TableName: REGIONS_TABLE,
        Key: { regionId: regionId },
      }));

    if (!regionResult.Item) {
      console.log('⚠️ Region metadata not found');
      return errorResponse(404, 'REGION_METADATA_NOT_FOUND', 'Region metadata not found');
    }

    const region = regionResult.Item;

    // Step 4: Build response
    const response = {
      region_id: regionId,
      region_name_ar: region.region_name_ar || regionId,
      region_name_en: region.region_name_en || regionId,
      city: region.city || 'غير محدد',
      h3Cell: h3Cell,
      coordinates: {
        latitude: lat,
        longitude: lng,
      },
      boundingBox: region.boundingBox || null,
    };

    console.log('✅ Region found successfully');
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
