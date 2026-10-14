/**
 * Lambda: Get Businesses With Neighbors
 * API: GET /api/businesses?region_id=X&include_neighbors=true&max_distance_km=10
 * 
 * Purpose: Fetch restaurants from current region + neighboring regions
 * الغرض: جلب المطاعم من المنطقة الحالية + المناطق المجاورة
 * 
 * Flow:
 * 1. Get primary region businesses
 * 2. Query REGION_NEIGHBORS_TABLE
 * 3. Get businesses from each neighbor region
 * 4. Merge and flag neighbor businesses
 * 5. Calculate additional delivery fees
 * 6. Return combined results
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, GetCommand, BatchGetCommand } = require('@aws-sdk/lib-dynamodb');

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

// Table names
const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
const REGION_NEIGHBORS_TABLE = requireEnv('REGION_NEIGHBORS_TABLE');

// Additional fee for neighbor region delivery
const NEIGHBOR_DELIVERY_FEE_BASE = 1000; // IQD per km distance

/**
 * Lambda handler
 */
exports.handler = async (event) => {
  console.log('🌐 Get Businesses With Neighbors');
  console.log('Event:', JSON.stringify(event, null, 2));

  try {
    // Extract parameters
    const {
      region_id,
      include_neighbors,
      max_distance_km = '10',
      page = '0',
      limit = '20',
    } = event.queryStringParameters || {};

    // Validate parameters
    if (!region_id) {
      return errorResponse(400, 'MISSING_REGION_ID', 'region_id is required');
    }

    if (include_neighbors !== 'true') {
      return errorResponse(400, 'INVALID_PARAMETER', 'include_neighbors must be true');
    }

    const maxDistanceKm = parseFloat(max_distance_km);
    const pageNum = parseInt(page);
    const limitNum = Math.min(parseInt(limit), 50);

    console.log(`🗺️ Primary Region: ${region_id}`);
    console.log(`📏 Max Neighbor Distance: ${maxDistanceKm} km`);

    // Step 1: Get primary region businesses
    console.log('📍 Fetching primary region businesses...');
    const primaryBusinesses = await getBusinessesByRegion(region_id);
    console.log(`✅ Primary: ${primaryBusinesses.length} businesses`);

    const allBusinesses = primaryBusinesses.map((b) => ({
      ...b,
      fromNeighborRegion: false,
      primaryRegion: true,
    }));

    // Step 2: Get neighbor regions
    console.log('🔍 Querying neighbor regions...');
    const neighborsResult = await dynamodb.send(new QueryCommand({
        TableName: REGION_NEIGHBORS_TABLE,
        KeyConditionExpression: 'region_id = :rid',
        FilterExpression: 'is_delivery_possible = :possible AND distance <= :maxDist',
        ExpressionAttributeValues: {
          ':rid': region_id,
          ':possible': true,
          ':maxDist': maxDistanceKm,
        },
      }));

    const neighbors = neighborsResult.Items || [];
    console.log(`🌐 Found ${neighbors.length} neighbor regions`);

    // Step 3: Get businesses from each neighbor
    const regionsSummary = {
      primary: {
        region_id,
        count: primaryBusinesses.length,
      },
      neighbors: [],
    };

    for (const neighbor of neighbors) {
      const neighborBusinesses = await getBusinessesByRegion(neighbor.neighbor_region_id);
      console.log(
        `   📍 ${neighbor.neighbor_region_id}: ${neighborBusinesses.length} businesses (${neighbor.distance} km)`
      );

      // Add neighbor flag and calculate additional fee
      const neighborBusinessesWithInfo = neighborBusinesses.map((b) => ({
        ...b,
        fromNeighborRegion: true,
        neighborRegionId: neighbor.neighbor_region_id,
        neighborRegionName: neighbor.neighbor_region_name,
        neighborDistance: neighbor.distance,
        additionalDeliveryFee: calculateAdditionalFee(neighbor.distance),
      }));

      allBusinesses.push(...neighborBusinessesWithInfo);

      regionsSummary.neighbors.push({
        region_id: neighbor.neighbor_region_id,
        region_name_ar: neighbor.neighbor_region_name,
        distance: neighbor.distance,
        count: neighborBusinesses.length,
      });
    }

    console.log(`✅ Total businesses: ${allBusinesses.length}`);

    // Step 4: Apply pagination
    const startIndex = pageNum * limitNum;
    const endIndex = startIndex + limitNum;
    const paginatedBusinesses = allBusinesses.slice(startIndex, endIndex);

    // Step 5: Build response
    return successResponse({
      businesses: paginatedBusinesses,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total: allBusinesses.length,
        hasMore: endIndex < allBusinesses.length,
      },
      regions: regionsSummary,
      includesNeighborRegions: true,
    });
  } catch (error) {
    console.error('❌ Error:', error);
    return errorResponse(500, 'INTERNAL_ERROR', 'Internal server error', {
      message: error.message,
    });
  }
};

/**
 * Get businesses for a region
 */
async function getBusinessesByRegion(regionId) {
  // Get listing
  const listingResult = await dynamodb.send(new GetCommand({
      TableName: REGION_LISTINGS_TABLE,
      Key: { region_id: regionId },
    }));

  if (!listingResult.Item || !listingResult.Item.businessIds) {
    return [];
  }

  const businessIds = listingResult.Item.businessIds;

  // Batch get businesses
  if (businessIds.length === 0) return [];

  const businesses = [];
  const chunks = chunkArray(businessIds, 100);

  for (const chunk of chunks) {
    const keys = chunk.map((id) => ({ businessId: id }));

    const result = await dynamodb
      .batchGet({
        RequestItems: {
          [BUSINESSES_TABLE]: {
            Keys: keys,
          },
        },
      })
      .promise();

    if (result.Responses && result.Responses[BUSINESSES_TABLE]) {
      businesses.push(...result.Responses[BUSINESSES_TABLE]);
    }
  }

  // Filter active businesses - ONLY based on region and isActive
  // No working hours or acceptingOrders filtering - display all restaurants in the region
  return businesses.filter((b) => b.isActive === true);
}

/**
 * Calculate additional delivery fee based on neighbor distance
 */
function calculateAdditionalFee(distanceKm) {
  return Math.ceil(distanceKm) * NEIGHBOR_DELIVERY_FEE_BASE;
}

/**
 * Split array into chunks
 */
function chunkArray(array, size) {
  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
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
