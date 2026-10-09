"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client = new client_dynamodb_1.DynamoDBClient({});
const docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
const PRODUCTS_TABLE = process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products';
const GLOBAL_PRODUCTS_TABLE = 'WhizzMerchants_GlobalProducts';
const CATEGORIES_TABLE = 'WhizzMerchants_Categories'; // 🔥 إضافة جدول الفئات
const handler = async (event) => {
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS',
    };
    try {
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers,
                body: '',
            };
        }
        const businessId = event.pathParameters?.businessId;
        const page = parseInt(event.queryStringParameters?.page || '1');
        const limit = parseInt(event.queryStringParameters?.limit || '50');
        if (!businessId) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({
                    error: 'Business ID is required',
                    message: 'معرف المطعم مطلوب'
                }),
            };
        }
        console.log(`Fetching products for business: ${businessId}`);
        
        // Step 1: Query Products table by businessId using GSI
        const queryCommand = new lib_dynamodb_1.QueryCommand({
            TableName: PRODUCTS_TABLE,
            IndexName: 'BusinessIdIndex',
            KeyConditionExpression: 'businessId = :businessId',
            ExpressionAttributeValues: {
                ':businessId': businessId,
            },
        });
        const productsResult = await docClient.send(queryCommand);
        
        if (!productsResult.Items || productsResult.Items.length === 0) {
            console.log(`No products found for business: ${businessId}`);
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({
                    success: true,
                    products: [],
                    count: 0,
                    message: 'لا توجد منتجات لهذا المطعم'
                }),
            };
        }
        
        console.log(`Found ${productsResult.Items.length} products, fetching global product details...`);
        
        // Step 2: Extract unique globalProductIds (remove duplicates)
        const uniqueGlobalProductIds = [...new Set(
            productsResult.Items
                .filter(p => p.globalProductId)
                .map(p => p.globalProductId)
        )];
        
        const globalProductIds = uniqueGlobalProductIds.map(id => ({ globalProductId: id }));
        
        console.log(`Found ${uniqueGlobalProductIds.length} unique global product IDs`);
        
        // Step 3: Batch get GlobalProducts (handle up to 100 items)
        let globalProductsMap = new Map();
        
        if (globalProductIds.length > 0) {
            // Split into chunks of 100 for BatchGetItem limit
            const chunks = [];
            for (let i = 0; i < globalProductIds.length; i += 100) {
                chunks.push(globalProductIds.slice(i, i + 100));
            }
            
            for (const chunk of chunks) {
                const batchGetCommand = new lib_dynamodb_1.BatchGetCommand({
                    RequestItems: {
                        [GLOBAL_PRODUCTS_TABLE]: {
                            Keys: chunk
                        }
                    }
                });
                
                const globalProductsResult = await docClient.send(batchGetCommand);
                
                if (globalProductsResult.Responses && globalProductsResult.Responses[GLOBAL_PRODUCTS_TABLE]) {
                    globalProductsResult.Responses[GLOBAL_PRODUCTS_TABLE].forEach(gp => {
                        globalProductsMap.set(gp.globalProductId, gp);
                    });
                }
            }
        }
        
        console.log(`Fetched ${globalProductsMap.size} global products, merging data...`);
        
        // Step 4: Extract unique categoryIds and fetch category names
        const uniqueCategoryIds = [...new Set(
            productsResult.Items
                .filter(p => p.categoryId)
                .map(p => p.categoryId)
        )];
        
        console.log(`Found ${uniqueCategoryIds.length} unique category IDs`);
        
        // Step 5: Batch get Categories (handle up to 100 items)
        let categoriesMap = new Map();
        
        if (uniqueCategoryIds.length > 0) {
            const categoryKeys = uniqueCategoryIds.map(id => ({ categoryId: id }));
            
            // Split into chunks of 100 for BatchGetItem limit
            const categoryChunks = [];
            for (let i = 0; i < categoryKeys.length; i += 100) {
                categoryChunks.push(categoryKeys.slice(i, i + 100));
            }
            
            for (const chunk of categoryChunks) {
                const batchGetCommand = new lib_dynamodb_1.BatchGetCommand({
                    RequestItems: {
                        [CATEGORIES_TABLE]: {
                            Keys: chunk
                        }
                    }
                });
                
                const categoriesResult = await docClient.send(batchGetCommand);
                
                if (categoriesResult.Responses && categoriesResult.Responses[CATEGORIES_TABLE]) {
                    categoriesResult.Responses[CATEGORIES_TABLE].forEach(cat => {
                        categoriesMap.set(cat.categoryId, cat);
                    });
                }
            }
        }
        
        console.log(`Fetched ${categoriesMap.size} categories, merging all data...`);
        
        // Step 6: Merge data from all tables (Products + GlobalProducts + Categories)
        // Priority: Use data from Products table first, fallback to GlobalProducts if null/missing
        const products = productsResult.Items.map(product => {
            const globalProduct = globalProductsMap.get(product.globalProductId) || {};
            const category = categoriesMap.get(product.categoryId) || {};
            
            return {
                productId: product.productId,
                categoryId: product.categoryId || globalProduct.categoryId || '',
                categoryName: category.categoryName || category.name || '', // 🔥 إضافة اسم الفئة
                businessId: product.businessId,
                // Use product-specific name first, fallback to canonical name from global
                name: product.name || globalProduct.canonicalName || '',
                description: product.description || globalProduct.description || '',
                price: product.price,
                imageUrl: product.imageUrl || globalProduct.imageUrl || '',
                is_available: product.isAvailable !== undefined ? product.isAvailable : true,
                created_at: product.createdAt,
                updated_at: product.updatedAt,
            };
        });
        
        // Sort products by name
        products.sort((a, b) => a.name.localeCompare(b.name));
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                products,
                count: products.length
            }),
        };
    }
    catch (error) {
        console.error('Error fetching business products:', error);
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({
                error: 'Internal server error',
                message: 'خطأ في الخادم الداخلي',
                details: error instanceof Error ? error.message : 'Unknown error'
            }),
        };
    }
};
exports.handler = handler;
