/**
 * Lambda: Get Businesses By Region
 * API: GET /api/businesses?region_id=region_najaf_manathera&page=0&limit=20
 * 
 * Purpose: Fetch restaurants for a specific region using RegionListings
 * الغرض: جلب المطاعم لمنطقة محددة باستخدام RegionListings
 * 
 * Flow:
 * 1. Get region_id from query params
 * 2. Query WhizzMerchants_RegionListings
 * 3. Batch get businesses from WhizzMerchants_Businesses
 * 4. Filter active/open restaurants
 * 5. Apply pagination
 * 6. Return results with listingVersion
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, BatchGetCommand } = require('@aws-sdk/lib-dynamodb');

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });

// Table names
const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';

/**
 * Lambda handler
 */
exports.handler = async (event) => {
  console.log('🍽️ Get Businesses By Region');
  console.log('Event:', JSON.stringify(event, null, 2));

  try {
    // Extract parameters
    const {
      region_id,
      page = '0',
      limit = '20',
      category,
      new: newOnly,
      sort = 'default',
    } = event.queryStringParameters || {};

    // Validate region_id
    if (!region_id) {
      return errorResponse(400, 'MISSING_REGION_ID', 'region_id is required');
    }

    const pageNum = parseInt(page);
    const limitNum = Math.min(parseInt(limit), 50); // Max 50 per page

    console.log(`🗺️ Region: ${region_id}`);
    console.log(`📄 Page: ${pageNum}, Limit: ${limitNum}`);

    // Step 1: Scan WhizzMerchants_Businesses with filter on regionId
    // Note: This is not optimal - TODO: Add GSI on regionId for better performance
    console.log('⚡ Scanning businesses table with regionId filter...');
    
    const scanResult = await dynamodb.send(new ScanCommand({
        TableName: BUSINESSES_TABLE,
        FilterExpression: 'regionId = :rid AND isActive = :active',
        ExpressionAttributeValues: {
          ':rid': region_id,
          ':active': true,
        },
      }));

    let businesses = scanResult.Items || [];
    console.log(`📊 Found ${businesses.length} businesses in region ${region_id}`);

    if (businesses.length === 0) {
      return successResponse({
        businesses: [],
        pagination: {
          page: pageNum,
          limit: limitNum,
          total: 0,
          hasMore: false,
        },
        region: {
          region_id,
          region_name_ar: null,
          listingVersion: Date.now(),
        },
      });
    }

    // Step 2: Apply additional filters
    let filteredBusinesses = businesses;

    // Apply category filter
    if (category) {
      filteredBusinesses = filteredBusinesses.filter((b) => b.category === category);
    }

    // Apply new restaurants filter
    if (newOnly === 'true') {
      const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
      filteredBusinesses = filteredBusinesses.filter((b) => {
        const createdAt = b.createdAt || 0;
        return createdAt > thirtyDaysAgo;
      });
    }

    // Step 3: Sort businesses
    if (sort === 'rating') {
      filteredBusinesses.sort((a, b) => (b.rating || 0) - (a.rating || 0));
    } else if (sort === 'delivery_time') {
      filteredBusinesses.sort((a, b) => (a.deliveryTime || 999) - (b.deliveryTime || 999));
    }

    // Step 4: Apply pagination
    const total = filteredBusinesses.length;
    const startIndex = pageNum * limitNum;
    const endIndex = startIndex + limitNum;
    const paginatedBusinesses = filteredBusinesses.slice(startIndex, endIndex);

    console.log(`✅ Returning ${paginatedBusinesses.length} of ${total} businesses (page ${pageNum})`);

    // Step 5: Build response
    return successResponse({
      businesses: paginatedBusinesses,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total,
        hasMore: endIndex < total,
      },
      region: {
        region_id,
        region_name_ar: null,
        listingVersion: Date.now(),
      },
    });
  } catch (error) {
    console.error('❌ Error:', error);
    return errorResponse(500, 'INTERNAL_ERROR', 'Internal server error', {
      message: error.message,
    });
  }
};

/**
 * Batch get businesses from DynamoDB
 */
async function batchGetBusinesses(businessIds) {
  if (businessIds.length === 0) return [];

  const businesses = [];

  // DynamoDB batchGet limit is 100 items
  const chunks = chunkArray(businessIds, 100);

  for (const chunk of chunks) {
    const keys = chunk.map((id) => ({ businessId: id }));

    const result = await dynamodb.send(new BatchGetCommand({
        RequestItems: {
          [BUSINESSES_TABLE]: {
            Keys: keys,
          },
        },
      }));

    if (result.Responses && result.Responses[BUSINESSES_TABLE]) {
      businesses.push(...result.Responses[BUSINESSES_TABLE]);
    }
  }

  return businesses;
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
