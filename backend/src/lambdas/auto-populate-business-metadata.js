/**
 * Lambda Function: Auto-populate business metadata on create/update
 * Triggered by DynamoDB Stream on WhizzMerchants_Businesses table
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { 
  DynamoDBDocumentClient, 
  GetCommand,
  UpdateCommand,
  PutCommand
} = require('@aws-sdk/lib-dynamodb');
const h3 = require('h3-js');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const REGION_INDEX_TABLE = process.env.REGION_INDEX_TABLE;
const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';
const H3_RESOLUTION = 9;

if (!REGION_INDEX_TABLE) {
  throw new Error('Missing required env var: REGION_INDEX_TABLE');
}

/**
 * Find regionId using H3 index
 */
async function findRegionByH3(latitude, longitude) {
  try {
    const h3Cell = h3.latLngToCell(parseFloat(latitude), parseFloat(longitude), H3_RESOLUTION);
    
    // Try exact match first
    const result = await docClient.send(new GetCommand({
      TableName: REGION_INDEX_TABLE,
      Key: { index_cell_id: h3Cell }
    }));
    
    if (result.Item) {
      return {
        regionId: result.Item.regionId,
        h3Cell: h3Cell
      };
    }
    
    // Fallback to parent cells
    for (let res = H3_RESOLUTION - 1; res >= 6; res--) {
      const parentCell = h3.cellToParent(h3Cell, res);
      
      const parentResult = await docClient.send(new GetCommand({
        TableName: REGION_INDEX_TABLE,
        Key: { index_cell_id: parentCell }
      }));
      
      if (parentResult.Item) {
        return {
          regionId: parentResult.Item.regionId,
          h3Cell: parentCell
        };
      }
    }
    
    return null;
  } catch (error) {
    console.error('Error in findRegionByH3:', error);
    return null;
  }
}

/**
 * Process DynamoDB Stream event
 */
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  for (const record of event.Records) {
    try {
      // Only process INSERT and MODIFY events
      if (record.eventName !== 'INSERT' && record.eventName !== 'MODIFY') {
        continue;
      }
      
      const newImage = record.dynamodb.NewImage;
      const oldImage = record.dynamodb.OldImage;
      
      // Convert DynamoDB format to regular object
      const business = {
        businessId: newImage.businessId?.S,
        latitude: newImage.latitude?.N,
        longitude: newImage.longitude?.N,
        regionId: newImage.regionId?.S,
        menuVersion: newImage.menuVersion?.N,
        inventoryVersion: newImage.inventoryVersion?.N,
        isActive: newImage.isActive?.BOOL,
        acceptingOrders: newImage.acceptingOrders?.BOOL
      };
      
      // Skip if no coordinates
      if (!business.latitude || !business.longitude) {
        console.log('Skipping - no coordinates:', business.businessId);
        continue;
      }
      
      let needsUpdate = false;
      const updates = {};
      
      // 1. Check/update regionId if missing or coordinates changed
      const coordsChanged = oldImage && (
        oldImage.latitude?.N !== newImage.latitude?.N ||
        oldImage.longitude?.N !== newImage.longitude?.N
      );
      
      if (!business.regionId || coordsChanged || record.eventName === 'INSERT') {
        const region = await findRegionByH3(business.latitude, business.longitude);
        
        if (region) {
          updates.regionId = region.regionId;
          updates.h3Cell = region.h3Cell;
          needsUpdate = true;
          console.log(`Found region for ${business.businessId}: ${region.regionId}`);
        } else {
          console.warn(`No region found for ${business.businessId}`);
        }
      }
      
      // 2. Initialize version fields for new businesses
      if (record.eventName === 'INSERT') {
        const now = Date.now();
        const timestamp = new Date().toISOString();
        
        if (!business.menuVersion) {
          updates.menuVersion = now;
          updates.menuLastUpdated = timestamp;
          needsUpdate = true;
        }
        
        if (!business.inventoryVersion) {
          updates.inventoryVersion = now;
          updates.inventoryLastUpdated = timestamp;
          needsUpdate = true;
        }
      }
      
      // 3. Apply updates if needed
      if (needsUpdate) {
        const updateExpressions = [];
        const expressionAttributeValues = {};
        
        Object.entries(updates).forEach(([key, value]) => {
          updateExpressions.push(`${key} = :${key}`);
          expressionAttributeValues[`:${key}`] = value;
        });
        
        await docClient.send(new UpdateCommand({
          TableName: process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses',
          Key: { businessId: business.businessId },
          UpdateExpression: `SET ${updateExpressions.join(', ')}`,
          ExpressionAttributeValues: expressionAttributeValues
        }));
        
        console.log(`Updated ${business.businessId}:`, updates);
      }
      
      // 4. Update RegionListings if regionId exists
      if (updates.regionId || business.regionId) {
        const targetRegionId = updates.regionId || business.regionId;
        await updateRegionListing(targetRegionId);
        
        // If region changed, update old region too
        if (oldImage?.regionId?.S && oldImage.regionId.S !== targetRegionId) {
          await updateRegionListing(oldImage.regionId.S);
        }
      }
      
    } catch (error) {
      console.error('Error processing record:', error);
      // Don't throw - continue processing other records
    }
  }
  
  return { statusCode: 200, body: 'Processed' };
};

/**
 * Update RegionListings count for a specific region
 */
async function updateRegionListing(regionId) {
  try {
    // This will be called by a separate Lambda to avoid complexity
    // For now, just log
    console.log(`Should update RegionListing for: ${regionId}`);
    
    // In production, invoke another Lambda or use EventBridge
    // to trigger region listing updates in batch
  } catch (error) {
    console.error('Error updating region listing:', error);
  }
}
