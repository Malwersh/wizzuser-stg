/**
 * Lambda Function: Update RegionListings counts
 * Triggered periodically or by events to update business counts per region
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { 
  DynamoDBDocumentClient, 
  ScanCommand,
  PutCommand,
  GetCommand
} = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
const REGIONS_TABLE = process.env.REGIONS_TABLE || 'WizzCentral_Regions';
const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';

/**
 * Main handler
 */
exports.handler = async (event) => {
  console.log('Updating RegionListings...');
  
  try {
    // Get specific regionId from event if provided, otherwise update all
    const regionId = event.regionId;
    
    if (regionId) {
      await updateSingleRegion(regionId);
    } else {
      await updateAllRegions();
    }
    
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'RegionListings updated successfully' })
    };
  } catch (error) {
    console.error('Error updating RegionListings:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
};

/**
 * Update a single region's listing
 */
async function updateSingleRegion(regionId) {
  console.log(`Updating region: ${regionId}`);
  
  // Get region details
  const regionResult = await docClient.send(new GetCommand({
    TableName: REGIONS_TABLE,
    Key: { regionId }
  }));
  
  if (!regionResult.Item) {
    console.warn(`Region not found: ${regionId}`);
    return;
  }
  
  const region = regionResult.Item;
  
  // Count businesses in this region
  const businessResult = await docClient.send(new ScanCommand({
    TableName: BUSINESSES_TABLE,
    FilterExpression: 'regionId = :regionId',
    ExpressionAttributeValues: {
      ':regionId': regionId
    },
    ProjectionExpression: 'businessId, isActive, acceptingOrders'
  }));
  
  const businesses = businessResult.Items || [];
  const counts = {
    total: businesses.length,
    active: businesses.filter(b => b.isActive).length,
    available: businesses.filter(b => b.isActive && b.acceptingOrders).length
  };
  
  // Update RegionListings
  const timestamp = new Date().toISOString();
  const version = Date.now();
  
  await docClient.send(new PutCommand({
    TableName: REGION_LISTINGS_TABLE,
    Item: {
      regionId: regionId,
      metadataType: 'LISTING_VERSION',
      listingVersion: version,
      lastUpdated: timestamp,
      totalBusinesses: counts.total,
      activeBusinesses: counts.active,
      availableBusinesses: counts.available,
      regionName: region.name,
      regionName_ar: region.name_ar,
      level: region.level,
      parent_id: region.parent_id,
      createdAt: timestamp,
      updatedAt: timestamp
    }
  }));
  
  console.log(`Updated ${regionId}: ${counts.total} businesses`);
}

/**
 * Update all regions
 */
async function updateAllRegions() {
  console.log('Updating all regions...');
  
  // Get all businesses grouped by region
  const businessResult = await docClient.send(new ScanCommand({
    TableName: BUSINESSES_TABLE,
    ProjectionExpression: 'businessId, regionId, isActive, acceptingOrders'
  }));
  
  const businesses = businessResult.Items || [];
  
  // Count by region
  const regionCounts = new Map();
  businesses.forEach(b => {
    if (!b.regionId) return;
    
    if (!regionCounts.has(b.regionId)) {
      regionCounts.set(b.regionId, { total: 0, active: 0, available: 0 });
    }
    
    const counts = regionCounts.get(b.regionId);
    counts.total++;
    if (b.isActive) counts.active++;
    if (b.isActive && b.acceptingOrders) counts.available++;
  });
  
  // Get all regions
  const regionsResult = await docClient.send(new ScanCommand({
    TableName: REGIONS_TABLE,
    FilterExpression: 'is_active = :active',
    ExpressionAttributeValues: {
      ':active': true
    }
  }));
  
  const regions = regionsResult.Items || [];
  const timestamp = new Date().toISOString();
  const version = Date.now();
  
  // Update each region
  for (const region of regions) {
    const counts = regionCounts.get(region.regionId) || { total: 0, active: 0, available: 0 };
    
    await docClient.send(new PutCommand({
      TableName: REGION_LISTINGS_TABLE,
      Item: {
        regionId: region.regionId,
        metadataType: 'LISTING_VERSION',
        listingVersion: version,
        lastUpdated: timestamp,
        totalBusinesses: counts.total,
        activeBusinesses: counts.active,
        availableBusinesses: counts.available,
        regionName: region.name,
        regionName_ar: region.name_ar,
        level: region.level,
        parent_id: region.parent_id,
        createdAt: timestamp,
        updatedAt: timestamp
      }
    }));
  }
  
  console.log(`Updated ${regions.length} regions`);
}
