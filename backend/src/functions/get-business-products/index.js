"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client = new client_dynamodb_1.DynamoDBClient({});
const docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
const PRODUCTS_TABLE = process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products';
const PLATFORM_TABLE = process.env.MERCHANT_PLATFORM_TABLE || 'staging-MerchantPlatform';
const GLOBAL_PRODUCTS_TABLE = 'WhizzMerchants_GlobalProducts';
const LEGACY_CATEGORY_IDS = Object.freeze({
  'fb-main-courses-002': '4d3e103e-a8e7-4361-88ca-11219ed884b5',
  'fb-desserts-003': 'd7438f4e-9dda-4915-bbf3-29327101ae7d',
  'fb-beverages-004': '4cccf116-24fe-46f0-a10f-e7d0ebc44cf1',
});
const categoryReference = id => LEGACY_CATEGORY_IDS[id] || id;
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
        
        // Prefer the immutable published menu. Branches not migrated yet keep the
        // legacy live-table behavior until their first explicit publish.
        const activeMenu=(await docClient.send(new lib_dynamodb_1.GetCommand({
            TableName:PLATFORM_TABLE,Key:{pk:`BRANCH#${businessId}`,sk:'MENU_VERSION#ACTIVE'},ConsistentRead:true
        }))).Item;
        const publishedVersion=activeMenu?.publishedVersion;
        const queryInput = publishedVersion ? {
            TableName:PLATFORM_TABLE,
            KeyConditionExpression:'pk = :pk AND begins_with(sk, :prefix)',
            ExpressionAttributeValues:{':pk':`BRANCH#${businessId}`,':prefix':`MENU_VERSION#${publishedVersion}#PRODUCT#`},
            ConsistentRead:true,
        } : {
            TableName: PRODUCTS_TABLE,
            IndexName: 'BusinessIdIndex',
            KeyConditionExpression: 'businessId = :businessId',
            ExpressionAttributeValues: { ':businessId': businessId },
        };
        const productItems=[];let productCursor;
        do {
            const productsResult=await docClient.send(new lib_dynamodb_1.QueryCommand({...queryInput,ExclusiveStartKey:productCursor}));
            productItems.push(...(productsResult.Items||[]).map(row=>publishedVersion?row.product:row));productCursor=productsResult.LastEvaluatedKey;
        } while(productCursor);
        
        if (productItems.length === 0) {
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
        
        console.log(`Found ${productItems.length} products, fetching global product details...`);

        // Published prices/content remain immutable; current availability can only restrict them.
        const liveProducts = new Map();
        if (publishedVersion) {
            const keys = [...new Set(productItems.map(p=>p.productId))].map(productId=>({productId}));
            for(let offset=0;offset<keys.length;offset+=100){
                let request={[PRODUCTS_TABLE]:{Keys:keys.slice(offset,offset+100),ConsistentRead:true}};
                for(let attempt=0;attempt<3;attempt++){
                    const result=await docClient.send(new lib_dynamodb_1.BatchGetCommand({RequestItems:request}));
                    for(const row of result.Responses?.[PRODUCTS_TABLE]||[])liveProducts.set(row.productId,row);
                    request=result.UnprocessedKeys||{};
                    if(!Object.keys(request).length)break;
                    if(attempt===2)throw Error('MENU_AVAILABILITY_UNAVAILABLE');
                }
            }
        }
        // Step 2: Extract unique globalProductIds (remove duplicates)
        const uniqueGlobalProductIds = publishedVersion ? [] : [...new Set(
            productItems
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
            productItems
                .filter(p => p.categoryId)
                .map(p => p.categoryId)
        )];
        
        console.log(`Found ${uniqueCategoryIds.length} unique category IDs`);
        
        // Step 5: Batch get Categories (handle up to 100 items)
        let categoriesMap = new Map();
        
        if (publishedVersion) {
            productItems.forEach(product=>{if(product.publishedCategory)categoriesMap.set(product.categoryId,product.publishedCategory);});
        } else if (uniqueCategoryIds.length > 0) {
            const categoryKeys = [...new Set(uniqueCategoryIds.map(categoryReference))].map(id => ({ categoryId: id }));
            
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
        const products = productItems.map(product => {
            const globalProduct = globalProductsMap.get(product.globalProductId) || {};
            const category = categoriesMap.get(categoryReference(product.categoryId)) || {};
            const live=liveProducts.get(product.productId);
            const liveAvailable=!publishedVersion||(live?.businessId===businessId&&live.isAvailable===true&&!live.isDeleted&&live.deletedAt==null);
            const categoryVisible=(!category.businessId||category.businessId===businessId)&&category.isActive!==false&&category.is_active!==false;
            
            return {
                productId: product.productId,
                categoryId: product.categoryId || globalProduct.categoryId || '',
                categoryName: category.name_ar || category.categoryName || category.name || '', // 🔥 إضافة اسم الفئة
                businessId: product.businessId,
                // Use product-specific name first, fallback to canonical name from global
                name: product.name || globalProduct.canonicalName || '',
                description: product.description || globalProduct.description || '',
                price: product.price,
                imageUrl: product.imageUrl || globalProduct.imageUrl || '',
                is_available: liveAvailable && categoryVisible && (product.isAvailable !== undefined ? product.isAvailable : true) && !(Array.isArray(product.optionGroups) && product.optionGroups.some(g=>g.required===true && (!Array.isArray(g.options)||!g.options.some(o=>o.isAvailable===true)))),
                is_featured: product.isFeatured !== undefined ? product.isFeatured : (globalProduct.isFeatured === true),
                addons: product.optionGroups ?? product.addons ?? [],
                variations: product.variations || [],
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
                count: products.length,
                menuVersion: activeMenu?.menuVersion,
                publishedVersion
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
