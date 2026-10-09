/**
 * Version Management Utilities
 * دوال مساعدة لإدارة إصدارات المنيو والمخزون
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, UpdateCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

/**
 * توليد رقم نسخة جديد (Unix timestamp)
 * @returns {number} رقم النسخة الجديد
 */
function generateVersion() {
  return Date.now();
}

/**
 * التحقق من تغيير النسخة
 * @param {number} clientVersion - النسخة الموجودة لدى العميل
 * @param {number} serverVersion - النسخة الحالية في السيرفر
 * @returns {boolean} true إذا تغيرت النسخة
 */
function hasVersionChanged(clientVersion, serverVersion) {
  if (!clientVersion || !serverVersion) {
    return true; // اعتبار أي قيمة null كتغيير
  }
  return serverVersion > clientVersion;
}

/**
 * تحديث نسخة المنيو أو المخزون للمطعم
 * @param {string} businessId - معرف المطعم
 * @param {string} type - نوع التحديث: 'menu' أو 'inventory'
 * @param {string} tableName - اسم الجدول (اختياري)
 * @returns {Promise<number>} رقم النسخة الجديد
 */
async function updateBusinessVersion(businessId, type, tableName = null) {
  const table = tableName || process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
  const version = generateVersion();
  const timestamp = new Date().toISOString();
  
  let updateExpression = '';
  let expressionAttributeValues = {};
  
  if (type === 'menu') {
    updateExpression = 'SET menuVersion = :version, menuLastUpdated = :timestamp, updatedAt = :timestamp';
    expressionAttributeValues = {
      ':version': version,
      ':timestamp': timestamp
    };
  } else if (type === 'inventory') {
    updateExpression = 'SET inventoryVersion = :version, inventoryLastUpdated = :timestamp, updatedAt = :timestamp';
    expressionAttributeValues = {
      ':version': version,
      ':timestamp': timestamp
    };
  } else {
    throw new Error(`Invalid type: ${type}. Must be 'menu' or 'inventory'`);
  }
  
  try {
    const command = new UpdateCommand({
      TableName: table,
      Key: { businessId },
      UpdateExpression: updateExpression,
      ExpressionAttributeValues: expressionAttributeValues,
      ReturnValues: 'ALL_NEW'
    });
    
    const result = await docClient.send(command);
    
    console.log(`✅ Updated ${type} version for business ${businessId}: ${version}`);
    
    return version;
  } catch (error) {
    console.error(`❌ Error updating ${type} version for business ${businessId}:`, error);
    throw error;
  }
}

/**
 * تحديث نسخة قائمة المطاعم في منطقة معينة
 * @param {string} regionId - معرف المنطقة
 * @param {Object} stats - إحصائيات المطاعم (اختياري)
 * @param {string} tableName - اسم الجدول (اختياري)
 * @returns {Promise<number>} رقم النسخة الجديد
 */
async function updateRegionListingVersion(regionId, stats = {}, tableName = null) {
  const table = tableName || process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';
  const version = generateVersion();
  const timestamp = new Date().toISOString();
  
  try {
    // تحديث أو إنشاء سجل النسخة للمنطقة
    const updateExpression = `SET 
      listingVersion = :version, 
      lastUpdated = :timestamp, 
      updatedAt = :timestamp
      ${stats.totalBusinesses !== undefined ? ', totalBusinesses = :total' : ''}
      ${stats.activeBusinesses !== undefined ? ', activeBusinesses = :active' : ''}
      ${stats.availableBusinesses !== undefined ? ', availableBusinesses = :available' : ''}
    `;
    
    const expressionAttributeValues = {
      ':version': version,
      ':timestamp': timestamp
    };
    
    if (stats.totalBusinesses !== undefined) {
      expressionAttributeValues[':total'] = stats.totalBusinesses;
    }
    if (stats.activeBusinesses !== undefined) {
      expressionAttributeValues[':active'] = stats.activeBusinesses;
    }
    if (stats.availableBusinesses !== undefined) {
      expressionAttributeValues[':available'] = stats.availableBusinesses;
    }
    
    const command = new UpdateCommand({
      TableName: table,
      Key: { 
        regionId,
        metadataType: 'LISTING_VERSION'
      },
      UpdateExpression: updateExpression.replace(/\s+/g, ' ').trim(),
      ExpressionAttributeValues: expressionAttributeValues,
      ReturnValues: 'ALL_NEW'
    });
    
    const result = await docClient.send(command);
    
    console.log(`✅ Updated listing version for region ${regionId}: ${version}`);
    
    return version;
  } catch (error) {
    console.error(`❌ Error updating listing version for region ${regionId}:`, error);
    throw error;
  }
}

/**
 * الحصول على نسخ المطعم الحالية
 * @param {string} businessId - معرف المطعم
 * @param {string} tableName - اسم الجدول (اختياري)
 * @returns {Promise<Object>} كائن يحتوي على menuVersion و inventoryVersion
 */
async function getBusinessVersions(businessId, tableName = null) {
  const { GetCommand } = require('@aws-sdk/lib-dynamodb');
  const table = tableName || process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
  
  try {
    const command = new GetCommand({
      TableName: table,
      Key: { businessId },
      ProjectionExpression: 'menuVersion, inventoryVersion, menuLastUpdated, inventoryLastUpdated'
    });
    
    const result = await docClient.send(command);
    
    return {
      menuVersion: result.Item?.menuVersion || 0,
      inventoryVersion: result.Item?.inventoryVersion || 0,
      menuLastUpdated: result.Item?.menuLastUpdated || null,
      inventoryLastUpdated: result.Item?.inventoryLastUpdated || null
    };
  } catch (error) {
    console.error(`❌ Error getting versions for business ${businessId}:`, error);
    throw error;
  }
}

/**
 * الحصول على نسخة قائمة المنطقة
 * @param {string} regionId - معرف المنطقة
 * @param {string} tableName - اسم الجدول (اختياري)
 * @returns {Promise<Object>} كائن يحتوي على listingVersion ومعلومات أخرى
 */
async function getRegionListingVersion(regionId, tableName = null) {
  const { GetCommand } = require('@aws-sdk/lib-dynamodb');
  const table = tableName || process.env.REGION_LISTINGS_TABLE || 'WhizzMerchants_RegionListings';
  
  try {
    const command = new GetCommand({
      TableName: table,
      Key: { 
        regionId,
        metadataType: 'LISTING_VERSION'
      }
    });
    
    const result = await docClient.send(command);
    
    return result.Item || {
      listingVersion: 0,
      lastUpdated: null
    };
  } catch (error) {
    console.error(`❌ Error getting listing version for region ${regionId}:`, error);
    throw error;
  }
}

module.exports = {
  generateVersion,
  hasVersionChanged,
  updateBusinessVersion,
  updateRegionListingVersion,
  getBusinessVersions,
  getRegionListingVersion
};
