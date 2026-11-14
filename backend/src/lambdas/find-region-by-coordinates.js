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
const {DynamoDBDocumentClient,GetCommand,QueryCommand,ScanCommand} = require('@aws-sdk/lib-dynamodb');
const { latLngToCell } = require('h3-js');

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {marshallOptions:{removeUndefinedValues:true}});

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
    const publicRegions=require('../utils/customer-regions-313').create({db:dynamodb,sdk:{GetCommand,QueryCommand,ScanCommand},tables:{regions:REGIONS_TABLE,derived:requireEnv('REGIONS_DERIVED_TABLE'),index:REGION_INDEX_TABLE}});
    if(event.queryStringParameters?.view==='active-tree')return successResponse(await publicRegions.catalog());
    if(event.queryStringParameters?.view==='boundary'){
      const id=event.queryStringParameters.region_id;
      if(typeof id!=='string'||!id||id.length>100)return errorResponse(400,'INVALID_REGION','اختر منطقة صحيحة.');
      const path=await publicRegions.ancestry(id);const leaf=path[3].base;
      return successResponse({regionId:id,nameAr:leaf.name_ar||leaf.name,geometry:leaf.geometry,bounds:require('../utils/customer-regions-313').bounds(leaf.geometry),version:leaf.version??null});
    }
    // Extract parameters
    const { latitude, longitude, resolution } = event.queryStringParameters || {};

    // Validate parameters
    if (!latitude || !longitude) {
      return errorResponse(400, 'MISSING_PARAMETERS', 'latitude and longitude are required');
    }

    const lat = Number(latitude);
    const lng = Number(longitude);
    const h3Resolution = resolution ? parseInt(resolution) : H3_RESOLUTION;

    // Validate coordinate ranges
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
      return errorResponse(400, 'INVALID_LATITUDE', 'Latitude must be between -90 and 90');
    }

    if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
      return errorResponse(400, 'INVALID_LONGITUDE', 'Longitude must be between -180 and 180');
    }

    console.log(`📍 Coordinates: ${lat}, ${lng}`);
    console.log(`🔍 H3 Resolution: ${h3Resolution}`);

    // H3 identifies candidates; the actual polygon and active hierarchy decide.
    const resolve=require('../utils/region-coverage-runtime-312').createRegionResolver({db:dynamodb,sdk:{GetCommand,QueryCommand},
      tables:{regions:REGIONS_TABLE,derived:requireEnv('REGIONS_DERIVED_TABLE'),index:REGION_INDEX_TABLE}});
    const coverage=await resolve({latitude:lat,longitude:lng});
    if(!coverage)return errorResponse(404,'REGION_NOT_FOUND','لا توجد منطقة خدمة متاحة لهذه الإحداثيات');
    const regionId=coverage.regionId,h3Cell=coverage.cellId;

    // Step 3: Query WizzCentral_Regions for details
    const regionResult = await dynamodb.send(new GetCommand({
        TableName: REGIONS_TABLE,
        Key: { regionId: regionId }, ConsistentRead:true,
      }));

    if (!regionResult.Item) {
      console.log('⚠️ Region metadata not found');
      return errorResponse(404, 'REGION_METADATA_NOT_FOUND', 'Region metadata not found');
    }

    const region = regionResult.Item;

    // Step 4: Build response
    const chain=await publicRegions.ancestry(regionId);
    const response = {
      schemaVersion:313,
      region_path:chain.map(r=>r.base.regionId),
      level:3,
      effective:{isActive:true,service:chain[3].derived.effective_config},
      region_id: regionId,
      region_name_ar: region.name_ar || region.region_name_ar || region.name || regionId,
      region_name_en: region.name || region.region_name_en || region.name_ar || regionId,
      city: chain[1].base.name_ar || chain[1].base.name,
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
    if(error.status===404)return errorResponse(404,'REGION_NOT_FOUND','الخدمة غير متاحة في هذه المنطقة حاليًا.');
    if(error.code==='AMBIGUOUS_COVERAGE')return errorResponse(409,'REGION_BOUNDARIES_REVIEW_REQUIRED','حدود منطقة الخدمة تحتاج مراجعة من الإدارة.');
    console.error('REGION_LOOKUP_UNAVAILABLE',{code:error.code||error.name});
    return errorResponse(503,'REGION_LOOKUP_UNAVAILABLE','تعذر التحقق من منطقة الخدمة الآن. حاول مجددًا.');
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
