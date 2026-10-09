/**
 * API: Check Listing Version
 * Endpoint: POST /api/check-listing-version
 * Purpose: التحقق من نسخة قائمة المطاعم في منطقة معينة
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';

/**
 * Handler function
 */
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    const body = JSON.parse(event.body);
    const { regionId, clientListingVersion } = body;
    
    // Validation
    if (!regionId) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'regionId is required'
        })
      };
    }
    
    // Get region listing
    const result = await docClient.send(new GetCommand({
      TableName: REGION_LISTINGS_TABLE,
      Key: {
        regionId: regionId,
        metadataType: 'LISTING_VERSION'
      }
    }));
    
    if (!result.Item) {
      return {
        statusCode: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Region not found',
          regionId: regionId
        })
      };
    }
    
    const listing = result.Item;
    
    // Compare versions
    const needsUpdate = clientListingVersion
      ? parseInt(clientListingVersion) < parseInt(listing.listingVersion)
      : true;
    
    const response = {
      regionId: listing.regionId,
      regionName: listing.regionName,
      regionName_ar: listing.regionName_ar,
      level: listing.level,
      
      // Version info
      listingVersion: listing.listingVersion,
      lastUpdated: listing.lastUpdated,
      needsUpdate: needsUpdate,
      
      // Business counts
      totalBusinesses: listing.totalBusinesses,
      activeBusinesses: listing.activeBusinesses,
      availableBusinesses: listing.availableBusinesses,
      
      // For UI display
      hasBusinesses: listing.totalBusinesses > 0,
      hasAvailableBusinesses: listing.availableBusinesses > 0
    };
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-cache, no-store, must-revalidate'
      },
      body: JSON.stringify(response)
    };
    
  } catch (error) {
    console.error('Error:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        message: error.message
      })
    };
  }
};
