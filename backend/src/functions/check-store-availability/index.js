// Single Store Availability API - Direct availability check for individual restaurants
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { checkStoreAvailability } = require('../store-availability/index.js');

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
};

exports.handler = async (event) => {
  console.log('🔍 Single Store Availability Check:', JSON.stringify(event, null, 2));

  try {
    // Handle preflight requests
    if (event.httpMethod === 'OPTIONS') {
      return {
        statusCode: 200,
        headers,
        body: '',
      };
    }

    if (event.httpMethod !== 'GET') {
      return {
        statusCode: 405,
        headers,
        body: JSON.stringify({
          success: false,
          message: 'Method not allowed'
        }),
      };
    }

    const storeId = event.pathParameters?.storeId || event.pathParameters?.businessId;
    const queryParams = event.queryStringParameters || {};
    const userLatitude = queryParams.lat ? parseFloat(queryParams.lat) : null;
    const userLongitude = queryParams.lng ? parseFloat(queryParams.lng) : null;
    const includeScheduling = queryParams.includeScheduling === 'true';
    const includePricing = queryParams.includePricing === 'true';
    
    if (!storeId) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({
          success: false,
          message: 'Store ID is required'
        }),
      };
    }

    console.log(`🏪 Checking availability for store: ${storeId}`);
    console.log(`📍 User location: ${userLatitude ? `${userLatitude},${userLongitude}` : 'not provided'}`);

    // Get comprehensive availability data
    const availability = await checkStoreAvailability(storeId, userLatitude, userLongitude);

    // Filter response based on requested data
    const response = {
      success: true,
      storeId,
      availability: {
        status: availability.status,
        canOrderNow: availability.canOrderNow,
        canSchedule: availability.canSchedule,
        allowPickup: availability.allowPickup,
        allowDelivery: availability.allowDelivery,
        leadTimeMins: availability.leadTimeMins,
        reasonCodes: availability.reasonCodes,
        nextOpenAt: availability.nextOpenAt,
        estimatedDeliveryTime: availability.estimatedDeliveryTime,
        metadata: {
          currentTime: availability.metadata.currentTime,
          timezone: availability.metadata.timezone,
          isPaused: availability.metadata.isPaused,
          isWithinHours: availability.metadata.isWithinHours,
          lastUpdated: availability.metadata.lastUpdated
        }
      }
    };

    // Add pricing info if requested
    if (includePricing) {
      response.availability.pricing = availability.pricing;
      response.availability.delivery = {
        available: availability.delivery.available,
        estimatedTime: availability.delivery.estimatedTime,
        radius: availability.delivery.radius
      };
    }

    // Add scheduling info if requested
    if (includeScheduling) {
      response.availability.scheduling = availability.scheduling;
      response.availability.businessHours = availability.metadata.businessHours;
    }

    // Add capacity info for merchants or detailed requests
    if (queryParams.detailed === 'true') {
      response.availability.capacity = availability.capacity;
      response.availability.fullMetadata = availability.metadata;
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify(response),
    };

  } catch (error) {
    console.error('❌ Error checking store availability:', error);
    
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        message: 'Internal server error',
        error: process.env.NODE_ENV === 'development' ? error.message : undefined,
        timestamp: new Date().toISOString()
      }),
    };
  }
};
