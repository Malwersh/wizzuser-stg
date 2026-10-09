/**
 * API: Check Menu Version
 * Endpoint: POST /api/check-menu-version
 * Purpose: التحقق من نسخة المنيو والمخزون لمطعم معين
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';

/**
 * Handler function
 */
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    const body = JSON.parse(event.body);
    const { businessId, clientMenuVersion, clientInventoryVersion } = body;
    
    // Validation
    if (!businessId) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'businessId is required'
        })
      };
    }
    
    // Get business current versions
    const result = await docClient.send(new GetCommand({
      TableName: BUSINESSES_TABLE,
      Key: { businessId },
      ProjectionExpression: 'businessId, businessName, menuVersion, inventoryVersion, menuLastUpdated, inventoryLastUpdated, isActive, acceptingOrders, isClosed'
    }));
    
    if (!result.Item) {
      return {
        statusCode: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'Business not found'
        })
      };
    }
    
    const business = result.Item;
    
    // Compare versions
    const menuNeedsUpdate = clientMenuVersion 
      ? parseInt(clientMenuVersion) < parseInt(business.menuVersion)
      : true;
      
    const inventoryNeedsUpdate = clientInventoryVersion
      ? parseInt(clientInventoryVersion) < parseInt(business.inventoryVersion)
      : true;
    
    const response = {
      businessId: business.businessId,
      businessName: business.businessName,
      
      // Menu version info
      menuVersion: business.menuVersion,
      menuLastUpdated: business.menuLastUpdated,
      menuNeedsUpdate: menuNeedsUpdate,
      
      // Inventory version info
      inventoryVersion: business.inventoryVersion,
      inventoryLastUpdated: business.inventoryLastUpdated,
      inventoryNeedsUpdate: inventoryNeedsUpdate,
      
      // Business status
      isActive: business.isActive,
      acceptingOrders: business.acceptingOrders,
      isClosed: business.isClosed,
      
      // Summary
      needsUpdate: menuNeedsUpdate || inventoryNeedsUpdate
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
