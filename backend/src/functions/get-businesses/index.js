"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client = new client_dynamodb_1.DynamoDBClient({});
const docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'order-receiver-businesses-dev';

console.log('🚀 Get Businesses Function Started');
console.log('📊 Using table:', BUSINESSES_TABLE);
const handler = async (event) => {
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
    };
    try {
        console.log('🔍 Testing table access...');
        
        // Test table access first
        const testCommand = new lib_dynamodb_1.ScanCommand({
            TableName: BUSINESSES_TABLE,
            Limit: 3
        });
        
        const testResult = await docClient.send(testCommand);
        console.log('✅ Table accessible, items found:', testResult.Items?.length || 0);
        
        if (testResult.Items && testResult.Items.length > 0) {
            console.log('📋 Sample item structure:', Object.keys(testResult.Items[0]));
        }
        
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: '',
            };
        }
        const queryParams = event.queryStringParameters || {};
        const limit = parseInt(queryParams.limit || '20');
        const newOnly = queryParams.new === 'true';
        const category = queryParams.category;
        const regionId = queryParams.region_id; // ✅ استخدام regionId بدلاً من region_id
        const userLatitude = queryParams.lat ? parseFloat(queryParams.lat) : null;
        const userLongitude = queryParams.lng ? parseFloat(queryParams.lng) : null;
        const onlyAvailable = queryParams.available === 'true';
        
        console.log(`Fetching businesses list, limit: ${limit}, newOnly: ${newOnly}, category: ${category}, regionId: ${regionId}, location: ${userLatitude},${userLongitude}, onlyAvailable: ${onlyAvailable}`);
        
        // Enhanced scan with proper filtering
        let filterExpression = 'isActive = :isActive AND #status = :status';
        let expressionAttributeValues = {
            ':isActive': true,
            ':status': 'approved'
        };
        let expressionAttributeNames = {
            '#status': 'status'
        };

        // ✅ إضافة فلتر حسب المنطقة (regionId)
        if (regionId) {
            filterExpression += ' AND regionId = :regionId';
            expressionAttributeValues[':regionId'] = regionId;
            console.log(`📍 Filtering by regionId: ${regionId}`);
        }

        // Add category filter
        if (category) {
            filterExpression += ' AND businessType = :businessType';
            expressionAttributeValues[':businessType'] = category;
        }

        // Add accepting orders filter if requested
        if (onlyAvailable) {
            filterExpression += ' AND acceptingOrders = :acceptingOrders';
            expressionAttributeValues[':acceptingOrders'] = true;
        }

        // Add new restaurants filter (14 days)
        if (newOnly) {
            const fourteenDaysAgo = new Date();
            fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);
            filterExpression += ' AND createdAt >= :fourteenDaysAgo';
            expressionAttributeValues[':fourteenDaysAgo'] = fourteenDaysAgo.toISOString();
        }
        
        const command = new lib_dynamodb_1.ScanCommand({
            TableName: BUSINESSES_TABLE,
            FilterExpression: filterExpression,
            ExpressionAttributeValues: expressionAttributeValues,
            ExpressionAttributeNames: expressionAttributeNames,
            Limit: limit * 2, // Get more to account for filtering
        });
        
        console.log('📊 Executing enhanced DynamoDB scan with filters...');
        const result = await docClient.send(command);
        
        console.log('📈 Scan results:', {
            itemsCount: result.Items?.length || 0,
            scannedCount: result.ScannedCount
        });
        
        if (!result.Items || result.Items.length === 0) {
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({
                    success: true,
                    businesses: [],
                    count: 0,
                    filters: { category, newOnly, onlyAvailable }
                }),
            };
        }

        // Import store availability checker
        const { checkStoreAvailability } = require('../store-availability/index.js');
        
        // Transform and enrich businesses with availability data
        const businessesWithAvailability = await Promise.all(
            result.Items.map(async (item) => {
                const baseBusinessData = {
                    business_id: item.businessId || item.business_id,
                    business_name: item.businessName || item.business_name,
                    address: item.address || 'العنوان غير متوفر',
                    business_photo_url: item.businessPhotoUrl || item.business_photo_url,
                    business_type: item.businessType || item.business_type,
                    phone: item.phoneNumber || item.phone_number,
                    email: item.email,
                    rating: item.rating || 4.2,
                    delivery_time: item.delivery_time || '30-45 دقيقة',
                    delivery_fee: item.delivery_fee || '5000',
                    minimum_order: item.minimum_order || 0,
                    is_active: item.isActive !== false,
                    created_at: item.createdAt || item.created_at,
                    updated_at: item.updatedAt || item.updated_at,
                    owner_name: item.ownerName || item.owner_name,
                    status: item.status,
                    acceptingOrders: item.acceptingOrders ?? true,
                    latitude: item.latitude,
                    longitude: item.longitude,
                };

                try {
                    // Check real-time availability
                    const availabilityData = await checkStoreAvailability(
                        item.businessId || item.business_id,
                        userLatitude,
                        userLongitude
                    );

                    return {
                        ...baseBusinessData,
                        availability: {
                            status: availabilityData.status,
                            canOrderNow: availabilityData.canOrderNow,
                            canSchedule: availabilityData.canSchedule,
                            allowDelivery: availabilityData.allowDelivery,
                            allowPickup: availabilityData.allowPickup,
                            leadTimeMins: availabilityData.leadTimeMins,
                            dynamicLeadTime: availabilityData.dynamicLeadTime,
                            nextOpenAt: availabilityData.nextOpenAt,
                            estimatedDeliveryTime: availabilityData.estimatedDeliveryTime,
                            reasonCodes: availabilityData.reasonCodes,
                        },
                        pricing: availabilityData.pricing,
                        capacity: {
                            currentOrders: availabilityData.capacity.currentOrders,
                            utilizationPercent: availabilityData.capacity.utilizationPercent,
                            isNearCapacity: availabilityData.capacity.isNearCapacity,
                        },
                        delivery: {
                            available: availabilityData.delivery.available,
                            estimatedTime: availabilityData.delivery.estimatedTime,
                            dynamicFee: availabilityData.pricing.dynamicPricing ? availabilityData.pricing.deliveryFee : null,
                        }
                    };
                } catch (error) {
                    console.log(`Warning: Could not get availability for ${item.businessId}:`, error.message);
                    // Fallback to basic availability check
                    const isAvailable = item.isActive && 
                                      (item.acceptingOrders ?? true) && 
                                      item.status === 'approved';
                    
                    return {
                        ...baseBusinessData,
                        availability: {
                            status: isAvailable ? 'OPEN' : 'CLOSED_OVERRIDE',
                            canOrderNow: isAvailable,
                            canSchedule: isAvailable,
                            allowDelivery: isAvailable,
                            allowPickup: isAvailable,
                            leadTimeMins: 30,
                            reasonCodes: isAvailable ? [] : ['BASIC_CHECK_FAILED']
                        },
                        pricing: {
                            deliveryFee: parseFloat(baseBusinessData.delivery_fee) || 5,
                            dynamicPricing: false,
                            minimumOrder: baseBusinessData.minimum_order || 0
                        },
                        capacity: {
                            currentOrders: 0,
                            utilizationPercent: 0,
                            isNearCapacity: false
                        },
                        delivery: {
                            available: isAvailable,
                            estimatedTime: 30
                        }
                    };
                }
            })
        );

        // Filter businesses based on availability if requested
        let businesses = businessesWithAvailability;
        if (onlyAvailable) {
            businesses = businesses.filter(business => business.availability.canOrderNow);
        }

        // Sort businesses by availability and distance
        businesses.sort((a, b) => {
            // Prioritize available restaurants
            if (a.availability.canOrderNow && !b.availability.canOrderNow) return -1;
            if (!a.availability.canOrderNow && b.availability.canOrderNow) return 1;
            
            // Then by capacity (less busy first)
            if (a.capacity.utilizationPercent !== b.capacity.utilizationPercent) {
                return a.capacity.utilizationPercent - b.capacity.utilizationPercent;
            }
            
            // Finally by rating
            return (b.rating || 0) - (a.rating || 0);
        });

        // Limit results
        businesses = businesses.slice(0, limit);
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                businesses,
                count: businesses.length,
                totalScanned: result.ScannedCount,
                filters: { 
                    category, 
                    newOnly, 
                    onlyAvailable,
                    hasLocationData: !!(userLatitude && userLongitude)
                },
                availabilityInfo: {
                    totalBusinesses: businessesWithAvailability.length,
                    availableNow: businesses.filter(b => b.availability.canOrderNow).length,
                    busyBusinesses: businesses.filter(b => b.capacity.isNearCapacity).length,
                    dynamicPricingActive: businesses.filter(b => b.pricing.dynamicPricing).length
                }
            }),
        };
    }
    catch (error) {
        console.error('❌ Error fetching businesses:', error);
        console.error('📊 Error details:', {
            name: error.name,
            message: error.message,
            table: BUSINESSES_TABLE
        });
        
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                error: 'Internal server error',
                message: 'خطأ في الخادم الداخلي',
                details: error.message,
                timestamp: new Date().toISOString()
            }),
        };
    }
};
exports.handler = handler;
