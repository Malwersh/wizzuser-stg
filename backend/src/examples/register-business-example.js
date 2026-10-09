/**
 * Example: Business Registration API with Auto-Metadata
 * Shows how to use business-metadata-utils in Lambda functions
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { 
  enrichBusinessMetadata, 
  updateRegionListing 
} = require('../utils/business-metadata-utils');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body);
    
    // البيانات الأساسية من المستخدم
    const businessData = {
      businessId: `business_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      businessName: body.businessName,
      businessType: body.businessType,
      ownerId: body.ownerId,
      ownerName: body.ownerName,
      email: body.email,
      phoneNumber: body.phoneNumber,
      address: body.address,
      city: body.city,
      district: body.district,
      street: body.street,
      latitude: body.latitude,      // مطلوب
      longitude: body.longitude,    // مطلوب
      businessPhotoUrl: body.businessPhotoUrl,
      isActive: false,              // ينتظر الموافقة
      acceptingOrders: false,
      isClosed: false
    };
    
    // ✅ تحسين البيانات تلقائياً (إضافة regionId, h3Cell, versions)
    const enrichedData = await enrichBusinessMetadata(docClient, businessData);
    
    // حفظ في DynamoDB
    await docClient.send(new PutCommand({
      TableName: process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses',
      Item: enrichedData
    }));
    
    // ✅ تحديث RegionListings إذا تم تحديد المنطقة
    if (enrichedData.regionId) {
      await updateRegionListing(docClient, enrichedData.regionId);
    }
    
    return {
      statusCode: 201,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        message: 'Business registered successfully',
        businessId: enrichedData.businessId,
        regionId: enrichedData.regionId,
        regionAssigned: !!enrichedData.regionId
      })
    };
    
  } catch (error) {
    console.error('Error registering business:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Failed to register business',
        message: error.message
      })
    };
  }
};
