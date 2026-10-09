/**
 * Example: Update Menu/Product with Version Increment
 * Shows how menu changes automatically increment menuVersion
 */

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { incrementBusinessVersion } = require('../utils/business-metadata-utils');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

/**
 * إضافة منتج جديد
 */
exports.addProduct = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { businessId } = event.pathParameters;
    
    const product = {
      productId: `product_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      businessId: businessId,
      categoryId: body.categoryId,
      name: body.name,
      name_ar: body.name_ar,
      description: body.description,
      description_ar: body.description_ar,
      price: body.price,
      imageUrl: body.imageUrl,
      isAvailable: body.isAvailable !== false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    
    // حفظ المنتج
    await docClient.send(new PutCommand({
      TableName: process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products',
      Item: product
    }));
    
    // ✅ زيادة menuVersion تلقائياً
    const newVersion = await incrementBusinessVersion(docClient, businessId, 'menu');
    
    return {
      statusCode: 201,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        message: 'Product added successfully',
        productId: product.productId,
        menuVersion: newVersion  // إرجاع النسخة الجديدة
      })
    };
    
  } catch (error) {
    console.error('Error adding product:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Failed to add product',
        message: error.message
      })
    };
  }
};

/**
 * تحديث منتج موجود
 */
exports.updateProduct = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { businessId, productId } = event.pathParameters;
    
    const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
    
    // تحديث المنتج
    await docClient.send(new UpdateCommand({
      TableName: process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products',
      Key: { productId },
      UpdateExpression: 'SET #name = :name, price = :price, isAvailable = :isAvailable, updatedAt = :updatedAt',
      ExpressionAttributeNames: {
        '#name': 'name'
      },
      ExpressionAttributeValues: {
        ':name': body.name,
        ':price': body.price,
        ':isAvailable': body.isAvailable,
        ':updatedAt': new Date().toISOString()
      }
    }));
    
    // ✅ زيادة menuVersion
    const newVersion = await incrementBusinessVersion(docClient, businessId, 'menu');
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        message: 'Product updated successfully',
        menuVersion: newVersion
      })
    };
    
  } catch (error) {
    console.error('Error updating product:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Failed to update product',
        message: error.message
      })
    };
  }
};

/**
 * حذف منتج
 */
exports.deleteProduct = async (event) => {
  try {
    const { businessId, productId } = event.pathParameters;
    
    // حذف المنتج
    await docClient.send(new DeleteCommand({
      TableName: process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products',
      Key: { productId }
    }));
    
    // ✅ زيادة menuVersion
    const newVersion = await incrementBusinessVersion(docClient, businessId, 'menu');
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        message: 'Product deleted successfully',
        menuVersion: newVersion
      })
    };
    
  } catch (error) {
    console.error('Error deleting product:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Failed to delete product',
        message: error.message
      })
    };
  }
};

/**
 * تحديث حالة التوفر (inventory)
 */
exports.updateProductAvailability = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { businessId, productId } = event.pathParameters;
    
    const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
    
    // تحديث التوفر
    await docClient.send(new UpdateCommand({
      TableName: process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products',
      Key: { productId },
      UpdateExpression: 'SET isAvailable = :isAvailable, updatedAt = :updatedAt',
      ExpressionAttributeValues: {
        ':isAvailable': body.isAvailable,
        ':updatedAt': new Date().toISOString()
      }
    }));
    
    // ✅ زيادة inventoryVersion (وليس menuVersion)
    const newVersion = await incrementBusinessVersion(docClient, businessId, 'inventory');
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        message: 'Product availability updated',
        inventoryVersion: newVersion
      })
    };
    
  } catch (error) {
    console.error('Error updating availability:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Failed to update availability',
        message: error.message
      })
    };
  }
};
