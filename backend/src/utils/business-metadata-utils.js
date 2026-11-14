/**
 * Business Metadata Utilities
 * Helper functions to auto-populate business metadata fields
 */

const { DynamoDBDocumentClient, GetCommand, QueryCommand, PutCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const h3 = require('h3-js');

const H3_RESOLUTION = 9;
function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

const REGION_INDEX_TABLE = requireEnv('REGION_INDEX_TABLE');
const REGIONS_TABLE = process.env.REGIONS_TABLE || 'WizzCentral_Regions';
const REGION_LISTINGS_TABLE = process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';

/**
 * Find regionId using H3 index lookup
 * @param {DynamoDBDocumentClient} docClient 
 * @param {number} latitude 
 * @param {number} longitude 
 * @returns {Promise<{regionId: string, h3Cell: string} | null>}
 */
async function findRegionByH3(docClient, latitude, longitude) {
  const lat=Number(latitude),lng=Number(longitude);
  if(!Number.isFinite(lat)||!Number.isFinite(lng))return null;
  const resolve=require('./region-coverage-runtime-312').createRegionResolver({db:docClient,sdk:{GetCommand,QueryCommand},
    tables:{regions:REGIONS_TABLE,derived:requireEnv('REGIONS_DERIVED_TABLE'),index:REGION_INDEX_TABLE}});
  const region=await resolve({latitude:lat,longitude:lng});
  if(!region)return null;
  const metadata=(await docClient.send(new GetCommand({TableName:REGIONS_TABLE,Key:{regionId:region.regionId},ConsistentRead:true}))).Item;
  return {regionId:region.regionId,h3Cell:region.cellId,regionPath:region.regionPath,regionName:metadata?.name_ar||metadata?.name||region.regionId};
}

/**
 * Enrich business data with required metadata fields
 * @param {DynamoDBDocumentClient} docClient 
 * @param {Object} businessData - Raw business data
 * @returns {Promise<Object>} Enhanced business data
 */
async function enrichBusinessMetadata(docClient, businessData) {
  const enhanced = { ...businessData };
  const now = Date.now();
  const timestamp = new Date().toISOString();
  
  // 1. Find and set regionId if coordinates provided
  if (businessData.latitude && businessData.longitude && !businessData.regionId) {
    const region = await findRegionByH3(docClient, businessData.latitude, businessData.longitude);
    
    if (region) {
      enhanced.regionId = region.regionId;
      enhanced.h3Cell = region.h3Cell;
      console.log(`Assigned region: ${region.regionName} (${region.regionId})`);
    } else {
      console.warn('Could not determine region for business');
    }
  }
  
  // 2. Initialize version fields if not present
  if (!businessData.menuVersion) {
    enhanced.menuVersion = now;
    enhanced.menuLastUpdated = timestamp;
  }
  
  if (!businessData.inventoryVersion) {
    enhanced.inventoryVersion = now;
    enhanced.inventoryLastUpdated = timestamp;
  }
  
  // 3. Set timestamps
  if (!businessData.createdAt) {
    enhanced.createdAt = timestamp;
  }
  enhanced.updatedAt = timestamp;
  
  return enhanced;
}

/**
 * Update business version when menu changes
 * @param {DynamoDBDocumentClient} docClient 
 * @param {string} businessId 
 * @param {'menu' | 'inventory'} versionType 
 */
async function incrementBusinessVersion(docClient, businessId, versionType = 'menu') {
  const now = Date.now();
  const timestamp = new Date().toISOString();
  
  const versionField = versionType === 'menu' ? 'menuVersion' : 'inventoryVersion';
  const timestampField = versionType === 'menu' ? 'menuLastUpdated' : 'inventoryLastUpdated';
  
  try {
    const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
    
    await docClient.send(new UpdateCommand({
      TableName: BUSINESSES_TABLE,
      Key: { businessId },
      UpdateExpression: `SET ${versionField} = :version, ${timestampField} = :timestamp`,
      ExpressionAttributeValues: {
        ':version': now,
        ':timestamp': timestamp
      }
    }));
    
    console.log(`Incremented ${versionType}Version for ${businessId}: ${now}`);
    return now;
    
  } catch (error) {
    console.error(`Error incrementing ${versionType}Version:`, error);
    throw error;
  }
}

/**
 * Update RegionListings for a specific region
 * @param {DynamoDBDocumentClient} docClient 
 * @param {string} regionId 
 */
async function updateRegionListing(docClient, regionId) {
  try {
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
    
    console.log(`Updated RegionListing for ${regionId}: ${counts.total} businesses`);
    return version;
    
  } catch (error) {
    console.error('Error updating RegionListing:', error);
    throw error;
  }
}

/**
 * Get current version info for a business
 * @param {DynamoDBDocumentClient} docClient 
 * @param {string} businessId 
 * @returns {Promise<{menuVersion: number, inventoryVersion: number}>}
 */
async function getBusinessVersions(docClient, businessId) {
  try {
    const result = await docClient.send(new GetCommand({
      TableName: BUSINESSES_TABLE,
      Key: { businessId },
      ProjectionExpression: 'menuVersion, inventoryVersion, menuLastUpdated, inventoryLastUpdated'
    }));
    
    if (!result.Item) {
      throw new Error(`Business not found: ${businessId}`);
    }
    
    return {
      menuVersion: result.Item.menuVersion,
      inventoryVersion: result.Item.inventoryVersion,
      menuLastUpdated: result.Item.menuLastUpdated,
      inventoryLastUpdated: result.Item.inventoryLastUpdated
    };
  } catch (error) {
    console.error('Error getting business versions:', error);
    throw error;
  }
}

module.exports = {
  findRegionByH3,
  enrichBusinessMetadata,
  incrementBusinessVersion,
  updateRegionListing,
  getBusinessVersions
};
