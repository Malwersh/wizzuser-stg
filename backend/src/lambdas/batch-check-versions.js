/**
 * API: Batch Check Versions
 * Endpoint: POST /api/batch-check-versions
 * Purpose: التحقق من عدة نسخ دفعة واحدة (menu versions + listing versions)
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, BatchGetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';

/**
 * Handler function
 */
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    const body = JSON.parse(event.body);
    const { businesses, regions } = body;
    
    // Validation
    if (!businesses && !regions) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'At least one of businesses or regions is required',
          example: {
            businesses: [
              { businessId: 'business_123', menuVersion: 1234567890, inventoryVersion: 1234567890 }
            ],
            regions: [
              { regionId: 'region_123', listingVersion: 1234567890 }
            ]
          }
        })
      };
    }
    
    const response = {
      businesses: [],
      regions: [],
      summary: {
        totalChecked: 0,
        needsUpdate: 0
      }
    };
    
    // Check businesses in batches
    if (businesses && businesses.length > 0) {
      const businessIds = businesses.map(b => b.businessId);
      const businessVersions = new Map(businesses.map(b => [b.businessId, b]));
      
      // BatchGet with max 100 items
      const batchSize = 100;
      for (let i = 0; i < businessIds.length; i += batchSize) {
        const batch = businessIds.slice(i, i + batchSize);
        
        const result = await docClient.send(new BatchGetCommand({
          RequestItems: {
            [BUSINESSES_TABLE]: {
              Keys: batch.map(id => ({ businessId: id })),
              ProjectionExpression: 'businessId, businessName, menuVersion, inventoryVersion, isActive, acceptingOrders'
            }
          }
        }));
        
        const items = result.Responses[BUSINESSES_TABLE] || [];
        
        for (const business of items) {
          const clientVersions = businessVersions.get(business.businessId);
          
          const menuNeedsUpdate = clientVersions?.menuVersion
            ? parseInt(clientVersions.menuVersion) < parseInt(business.menuVersion)
            : true;
            
          const inventoryNeedsUpdate = clientVersions?.inventoryVersion
            ? parseInt(clientVersions.inventoryVersion) < parseInt(business.inventoryVersion)
            : true;
          
          const needsUpdate = menuNeedsUpdate || inventoryNeedsUpdate;
          
          response.businesses.push({
            businessId: business.businessId,
            businessName: business.businessName,
            menuVersion: business.menuVersion,
            inventoryVersion: business.inventoryVersion,
            menuNeedsUpdate,
            inventoryNeedsUpdate,
            needsUpdate,
            isActive: business.isActive,
            acceptingOrders: business.acceptingOrders
          });
          
          if (needsUpdate) response.summary.needsUpdate++;
        }
      }
      
      response.summary.totalChecked += response.businesses.length;
    }
    
    // Check regions in batches
    if (regions && regions.length > 0) {
      const regionIds = regions.map(r => r.regionId);
      const regionVersions = new Map(regions.map(r => [r.regionId, r]));
      
      const batchSize = 100;
      for (let i = 0; i < regionIds.length; i += batchSize) {
        const batch = regionIds.slice(i, i + batchSize);
        
        const result = await docClient.send(new BatchGetCommand({
          RequestItems: {
            [REGION_LISTINGS_TABLE]: {
              Keys: batch.map(id => ({ regionId: id, metadataType: 'LISTING_VERSION' })),
              ProjectionExpression: 'regionId, regionName, regionName_ar, listingVersion, totalBusinesses, activeBusinesses, availableBusinesses'
            }
          }
        }));
        
        const items = result.Responses[REGION_LISTINGS_TABLE] || [];
        
        for (const region of items) {
          const clientVersion = regionVersions.get(region.regionId);
          
          const needsUpdate = clientVersion?.listingVersion
            ? parseInt(clientVersion.listingVersion) < parseInt(region.listingVersion)
            : true;
          
          response.regions.push({
            regionId: region.regionId,
            regionName: region.regionName,
            regionName_ar: region.regionName_ar,
            listingVersion: region.listingVersion,
            needsUpdate,
            totalBusinesses: region.totalBusinesses,
            activeBusinesses: region.activeBusinesses,
            availableBusinesses: region.availableBusinesses
          });
          
          if (needsUpdate) response.summary.needsUpdate++;
        }
      }
      
      response.summary.totalChecked += response.regions.length;
    }
    
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
