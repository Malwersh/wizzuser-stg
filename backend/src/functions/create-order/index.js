const {isTerminalOrderStatus}=require('../shared/legacy-order-policy');
const {customerOrderView} = require('../shared/customer-order-view');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, GetCommand, QueryCommand, TransactWriteCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const {offerContext} = require('../shared/offer-context');
const { createStagingQuoteOrder, QuoteOrderError } = require('./quote-runtime/deliveryQuoteOrder');
const { v4: uuidv4 } = require('uuid');
const https = require('https');
const {resolveDiscount} = require('../shared/discount-reservation');
const {createStagingDeliveryPromotionSelection}=require('./quote-runtime/deliveryPromotionSelection');
const {deliveryPromotionCustomerFacts}=require('./quote-runtime/deliveryPromotionCustomer');
const {createStagingCommercialSource} = require('./quote-runtime/orderCommercialSource');
const {createFinanceRollout}=require('./quote-runtime/financeRollout');
const {moneyFromMinor} = require('./quote-runtime/money');
const {createStagingOrderGoodsPricing} = require('./quote-runtime/orderGoodsPricing');

const CENTRAL_NOTIFICATIONS_BASE_URL = String(process.env.CENTRAL_NOTIFICATIONS_BASE_URL || '').trim();
const CENTRAL_NOTIFICATIONS_INTERNAL_KEY = String(process.env.CENTRAL_NOTIFICATIONS_INTERNAL_KEY || '').trim();

const client = new DynamoDBClient({});
const baseDynamoDb = DynamoDBDocumentClient.from(client, {
    marshallOptions: {
        removeUndefinedValues: true
    }
});

function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

// Use new WizzOrders table
const TABLE_NAME = process.env.WIZZORDERS_TABLE || 'WizzOrders';
// Businesses table (used as fallback to fetch store address when frontend doesn't provide one)
const BUSINESSES_TABLE = process.env.BUSINESSES_TABLE || 'WhizzMerchants_Businesses';
// Merchant discounts table (shared with the merchants app)
const DISCOUNTS_TABLE = process.env.DISCOUNTS_TABLE || 'WhizzMerchants_Discounts';
// Platform promo codes table (written by the central platform)
const PLATFORM_DISCOUNTS_TABLE = process.env.PLATFORM_DISCOUNTS_TABLE || 'WizzCentral_Platform_Discounts';
const MERCHANT_WEBHOOK_URL = process.env.MERCHANT_WEBHOOK_URL;

function postJson(urlString, headers, body, timeoutMs = 6000) {
    return new Promise((resolve, reject) => {
        const url = new URL(urlString);
        const req = https.request(
            {
                protocol: url.protocol,
                hostname: url.hostname,
                port: url.port || (url.protocol === 'https:' ? 443 : 80),
                path: url.pathname + url.search,
                method: 'POST',
                headers: {
                    'content-type': 'application/json',
                    ...headers
                },
                timeout: timeoutMs
            },
            (res) => {
                let data = '';
                res.setEncoding('utf8');
                res.on('data', (chunk) => (data += chunk));
                res.on('end', () => resolve({ statusCode: res.statusCode || 0, body: data }));
            }
        );

        req.on('timeout', () => {
            req.destroy(new Error('Request timed out'));
        });
        req.on('error', reject);
        req.write(JSON.stringify(body));
        req.end();
    });
}

async function sendMerchantOrderPush(payload) {
    if (!CENTRAL_NOTIFICATIONS_BASE_URL || !CENTRAL_NOTIFICATIONS_INTERNAL_KEY) {
        console.log('ℹ️ Central Notifications merchant push not configured; skipping', {
            hasBaseUrl: Boolean(CENTRAL_NOTIFICATIONS_BASE_URL),
            hasInternalKey: Boolean(CENTRAL_NOTIFICATIONS_INTERNAL_KEY)
        });
        return;
    }

    const url = `${CENTRAL_NOTIFICATIONS_BASE_URL.replace(/\/$/, '')}/push/send/merchant-order`;
    try {
        const resp = await postJson(
            url,
            { 'x-internal-key': CENTRAL_NOTIFICATIONS_INTERNAL_KEY },
            payload,
            6000
        );

        if (resp.statusCode < 200 || resp.statusCode >= 300) {
            console.error('❌ Central Notifications merchant push failed', { status: resp.statusCode, body: String(resp.body || '').slice(0, 500) });
            return;
        }
        console.log('✅ Central Notifications merchant push sent', String(resp.body || '').slice(0, 500));
    } catch (e) {
        console.error('❌ Central Notifications merchant push error', e?.message || String(e));
    }
}

/**
 * Format delivery address based on user type (registered vs guest)
 * @param {Object} addressData - The address data from request
 * @param {boolean} isGuestOrder - Whether this is a guest order
 * @returns {Object} Formatted address object
 */
function formatDeliveryAddress(addressData, isGuestOrder = false) {
    console.log('Delivery address formatting started');
    console.log('🏠 formatDeliveryAddress: isGuestOrder:', isGuestOrder);
    
    // Base address structure
    const formattedAddress = {
        // Common fields for both registered and guest users
        lat: addressData.latitude || addressData.lat || null,
        lng: addressData.longitude || addressData.lng || null,
        countryCode: addressData.countryCode || 'IQ',
    };
    
    if (isGuestOrder) {
        // Guest user format - use fullAddress directly if provided
        console.log('🏠 formatDeliveryAddress: Processing guest user address');
        
        // For guests, prioritize fullAddress from the input
        if (addressData.fullAddress && addressData.fullAddress.trim() !== '') {
            let finalAddress = addressData.fullAddress.trim();
            
            // Add landmark if provided separately
            if (addressData.landmark && addressData.landmark.trim() !== '') {
                finalAddress += '، قرب ' + addressData.landmark.trim();
            }
            
            formattedAddress.fullAddress = finalAddress;
            console.log('🏠 formatDeliveryAddress: Using provided fullAddress for guest:', formattedAddress.fullAddress);
        } else {
            // Fallback: try to build address from components
            const addressParts = [];
            if (addressData.province && addressData.province.trim() !== '') addressParts.push(addressData.province.trim());
            if (addressData.district && addressData.district.trim() !== '') addressParts.push(addressData.district.trim());
            if (addressData.neighborhood && addressData.neighborhood.trim() !== '') addressParts.push(addressData.neighborhood.trim());
            if (addressData.landmark && addressData.landmark.trim() !== '') addressParts.push('قرب ' + addressData.landmark.trim());
            if (addressData.street && addressData.street.trim() !== '') addressParts.push(addressData.street.trim());
            
            formattedAddress.fullAddress = addressParts.length > 0 ? addressParts.join('، ') : 'عنوان غير محدد';
            console.log('🏠 formatDeliveryAddress: Built fullAddress from parts for guest:', formattedAddress.fullAddress);
        }
        
        // Set simple fields for compatibility
        formattedAddress.addressLine1 = addressData.street || addressData.addressLine1 || '';
        formattedAddress.addressLine2 = addressData.addressLine2 || null;
        formattedAddress.city = addressData.district || addressData.city || '';
        formattedAddress.area = addressData.neighborhood || addressData.area || null;
        formattedAddress.postalCode = addressData.postalCode || addressData.zipCode || null;
        
        // أضافة حقل landmark للضيوف أيضاً
        formattedAddress.landmark = addressData.landmark || '';
        formattedAddress.name = addressData.name || '';
        formattedAddress.province = addressData.province || '';
        formattedAddress.district = addressData.district || '';
        formattedAddress.neighborhood = addressData.neighborhood || '';
        formattedAddress.phoneNumber = addressData.phoneNumber || null;
        
    } else {
        // Registered user format - detailed address fields
        console.log('🏠 formatDeliveryAddress: Processing registered user address');
        formattedAddress.name = addressData.name || 'عنوان غير محدد';
        formattedAddress.province = addressData.province || '';
        formattedAddress.district = addressData.district || '';
        formattedAddress.neighborhood = addressData.neighborhood || '';
        formattedAddress.landmark = addressData.landmark || '';
        formattedAddress.detailedAddress = addressData.detailedAddress || addressData.detailed_address || null;
        formattedAddress.buildingNumber = addressData.buildingNumber || addressData.building_number || null;
        formattedAddress.floorNumber = addressData.floorNumber || addressData.floor_number || null;
        formattedAddress.apartmentNumber = addressData.apartmentNumber || addressData.apartment_number || null;
        formattedAddress.phoneNumber = addressData.phoneNumber || addressData.phone_number || null;
        
        // Build full address for registered users
        const detailedParts = [];
        if (formattedAddress.detailedAddress) detailedParts.push(formattedAddress.detailedAddress);
        if (formattedAddress.neighborhood && formattedAddress.neighborhood !== 'غير محدد') detailedParts.push(formattedAddress.neighborhood);
        if (formattedAddress.district && formattedAddress.district !== 'غير محدد') detailedParts.push(formattedAddress.district);
        if (formattedAddress.province && formattedAddress.province !== 'غير محدد') detailedParts.push(formattedAddress.province);
        if (formattedAddress.landmark && formattedAddress.landmark !== 'غير محدد') detailedParts.push('قرب ' + formattedAddress.landmark);
        
        formattedAddress.fullAddress = addressData.fullAddress || detailedParts.join('، ') || formattedAddress.name;
        
        // Also include simple fields for backward compatibility
        formattedAddress.addressLine1 = formattedAddress.detailedAddress || '';
        formattedAddress.city = formattedAddress.district || '';
        formattedAddress.area = formattedAddress.neighborhood || null;
    }
    
    console.log('🏠 formatDeliveryAddress: Final formatted address:', JSON.stringify(formattedAddress, null, 2));
    return formattedAddress;
}

/**
 * Send order to merchant backend webhook
 * @param {Object} order - The order object
 * @returns {Promise} - Promise that resolves with webhook response
 */
function sendOrderToMerchant(order) {
    if (!MERCHANT_WEBHOOK_URL) {
        console.log('ℹ️ MERCHANT_WEBHOOK_URL not configured; skipping merchant webhook');
        return Promise.resolve({ skipped: true });
    }
    return new Promise((resolve, reject) => {
        console.log('📨 Sending order to merchant webhook:', order.orderId);
        
        // Send complete WizzOrders schema to merchant
        const webhookPayload = {
            orderId: order.orderId,
            orderNumber: order.orderNumber_gsi,
            storeId: order.storeId,
            userId: order.userId,
            isGuestOrder: order.isGuestOrder,
            customerName: order.customerName,
            customerPhone: order.customerPhone,
            deliveryAddress: order.deliveryAddress,
            items: order.items,
            pricing: order.pricing,
            discountId: order.discountId,
            notes: order.notes,
            deliveryType: order.deliveryType,
            paymentMethod: order.paymentMethod,
            paymentChannel: order.paymentChannel,
            createdAt: order.createdAt,
            status: order.status,
            // Additional context
            channel: order.channel,
            currency: order.currency,
            deliveryInstructions: order.deliveryInstructions
        };

        const postData = JSON.stringify(webhookPayload);
        console.log('📨 Webhook payload (WizzOrders Schema):', JSON.stringify(webhookPayload, null, 2));

        const url = new URL(MERCHANT_WEBHOOK_URL);
        const options = {
            hostname: url.hostname,
            port: 443,
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
                'User-Agent': 'WizzUser-Backend/1.0',
                'x-merchant-webhook-key': process.env.MERCHANT_WEBHOOK_INTERNAL_KEY || ''
            },
            timeout: 10000 // 10 second timeout
        };

        const req = https.request(options, (res) => {
            let responseBody = '';
            
            res.on('data', (chunk) => {
                responseBody += chunk;
            });
            
            res.on('end', () => {
                console.log('📨 Webhook response status:', res.statusCode);
                console.log('📨 Webhook response body:', responseBody);
                
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        const response = JSON.parse(responseBody);
                        resolve(response);
                    } catch (parseError) {
                        console.warn('📨 Webhook response not JSON:', responseBody);
                        resolve({ success: true, message: responseBody });
                    }
                } else {
                    console.error('📨 Webhook failed with status:', res.statusCode);
                    reject(new Error(`Webhook failed with status ${res.statusCode}: ${responseBody}`));
                }
            });
        });

        req.on('error', (error) => {
            console.error('📨 Webhook request error:', error);
            reject(error);
        });

        req.on('timeout', () => {
            console.error('📨 Webhook request timeout');
            req.destroy();
            reject(new Error('Webhook request timeout'));
        });

        req.write(postData);
        req.end();
    });
}

/**
 * Lambda handler for creating a new order
 */
async function handleOrder321(event, pointDb=null) {
    let dynamoDb=pointDb??baseDynamoDb;
    console.log('Create order request received', {requestId:event.requestContext?.requestId});
    console.log('TABLE_NAME:', TABLE_NAME);
    console.log('Environment variables:', {
        WIZZORDERS_TABLE: process.env.WIZZORDERS_TABLE,
        NODE_ENV: process.env.NODE_ENV
    });
    
    const headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    };
    
    try {
        // Early validation of environment variables
        if (!TABLE_NAME) {
            console.error('TABLE_NAME is not set!');
            return {
                statusCode: 500,
                headers: headers,
                body: JSON.stringify({
                    error: 'Configuration error: TABLE_NAME is not set',
                    success: false
                })
            };
        }
        
        // Handle preflight requests
        if (event.httpMethod === 'OPTIONS') {
            return {
                statusCode: 200,
                headers: headers,
                body: ''
            };
        }

        // Parse request body
        let body;
        if (typeof event.body === 'string') {
            body = JSON.parse(event.body);
        } else {
            body = event.body;
        }

        // Support both 'items' and 'cartItems' for backward compatibility
        if (body.cartItems && !body.items) {
            body.items = body.cartItems;
        }

        // Validate required fields (userId can be null for guest users)
        const requiredFields = ['storeId', 'storeName', 'storeAddress', 'deliveryAddress', 'paymentMethod'];
        for (const field of requiredFields) {
            if (!body[field]) {
                return {
                    statusCode: 400,
                    headers: headers,
                    body: JSON.stringify({
                        error: `Missing required field: ${field}`,
                        success: false
                    })
                };
            }
        }
        
        // userId validation - can be null for guest users but must be present in the request
        if (body.userId === undefined) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Missing required field: userId (can be null for guest users)',
                    success: false
                })
            };
        }

        const profilesTable = requireEnv('USERS_TABLE');
        requireEnv('USER_POOL_ID');
        requireEnv('USER_POOL_CLIENT_ID');
        const readOfferContext = () => offerContext(dynamoDb,event,body);
        const currentOffers = await readOfferContext();
        // Quote revalidation receives the same live profile/audience fences.
        const readAccount = async () => (await readOfferContext()).guarded;
        const userSub = currentOffers.identity?.sub || null;

        // Validate items array
        if (!Array.isArray(body.items) || body.items.length === 0) {
            return {
                statusCode: 400,
                headers: headers,
                body: JSON.stringify({
                    error: 'Items array is required and must not be empty',
                    success: false
                })
            };
        }

        // Local quoted flow is disabled until Quote API, checkout and deletion/IAM are deployed together.
        const quoteMode = process.env.DELIVERY_QUOTE_MODE || 'OFF';
        if (!['OFF', 'REQUIRED'].includes(quoteMode)) throw Object.assign(Error('QUOTE_NOT_CONFIGURED'), {statusCode: 503});
        if (quoteMode === 'OFF' && body.quoteId !== undefined) throw Object.assign(Error('QUOTE_NOT_ENABLED'), {statusCode: 409});
        const commercialMode = process.env.COMMERCIAL_PRICING_MODE || 'OFF';
        if ((commercialMode==='REQUIRED'||body.discountId||body.promoCode||body.platformDiscountId) &&
            require('../shared/discount-contract').hasDiscountCustomizations(body.items))
            throw Object.assign(Error('UNSUPPORTED_DISCOUNT_ITEMS'),{statusCode:409});
        if (!['OFF','REQUIRED'].includes(commercialMode) || (commercialMode==='REQUIRED' && quoteMode!=='REQUIRED'))
            throw Object.assign(Error('COMMERCIAL_NOT_CONFIGURED'),{statusCode:503});
        const deliveryPromotionMode=process.env.DELIVERY_PROMOTION_MODE||'OFF';
        if(!['OFF','REQUIRED'].includes(deliveryPromotionMode)||(deliveryPromotionMode==='REQUIRED'&&commercialMode!=='REQUIRED'))
            throw Object.assign(Error('DELIVERY_PROMOTION_NOT_CONFIGURED'),{statusCode:503});
        const previewRoute = event.resource === '/orders/commercial-preview';
        if ((body.action==='preview_commercial') !== previewRoute) throw Object.assign(Error('INVALID_ORDER_ACTION'),{statusCode:400});
        if (body.action !== undefined && body.action !== 'preview_commercial') throw Object.assign(Error('INVALID_ORDER_ACTION'),{statusCode:400});
        if (commercialMode==='OFF' && (body.action==='preview_commercial'||body.commercialConsent!==undefined))
            throw Object.assign(Error('COMMERCIAL_NOT_ENABLED'),{statusCode:409});
        if(quoteMode==='REQUIRED'){const rollout=createFinanceRollout({db:dynamoDb});rollout.customer(body.storeId,userSub);if(body.action==='preview_commercial')rollout.admit(body.storeId,userSub);dynamoDb=rollout.db;}
        let quotedOrder = null;
        const quotedResponse = (saved, replayed) => ({statusCode: replayed ? 200 : 201, headers,
            body: JSON.stringify({success: true, message: replayed ? 'Order already created' : 'Order created successfully',
                orderId: saved.orderId, orderNumber: saved.orderNumber, order: customerOrderView(saved), replayed})});
        if (quoteMode === 'REQUIRED') {
            if (process.env.AWS_REGION !== 'us-east-1' || process.env.USER_POOL_ID !== 'us-east-1_TpyyrVkEE' || profilesTable !== 'WizzUser_users_staging' ||
                TABLE_NAME !== 'WizzOrders' || BUSINESSES_TABLE !== 'WhizzMerchants_Businesses') {
                throw Object.assign(Error('QUOTE_NOT_CONFIGURED'), {statusCode: 503});
            }
            const service = createStagingQuoteOrder({enableFullCash:process.env.FINANCIAL_SETTLEMENT_MODEL==='FULL_CASH_AT_DELIVERY_V1',db: dynamoDb, enableDeliveryFunding:deliveryPromotionMode==='REQUIRED', authenticateCustomer: async () => {
                const live = await readAccount();
                return {userId: body.userId, subjectId: live.sub, condition: live.condition};
            }});
            quotedOrder = await service.prepare({quoteId: body.quoteId, branchId: body.storeId,
                addressId: body.deliveryAddress?.id, requestId: body.idempotencyKey, requestContent: body});
            // Replay precedes the active-order query, which would otherwise reject this same persisted order.
            if (quotedOrder.replayedOrder) return quotedResponse(quotedOrder.replayedOrder, true);
        }

        // CRITICAL BUSINESS RULE: Check for active orders
        // Don't allow creating a new order if user has an active (incomplete) order
        if (body.action !== 'preview_commercial' && body.userId && body.userId !== null && body.userId !== 'guest') {
            console.log('🔍 Checking for active orders for user:', body.userId);
            
            try {
                const { QueryCommand } = require('@aws-sdk/lib-dynamodb');
                
                // Define TERMINAL (completed) order statuses. Any order whose status
                // is NOT terminal is considered active. This is intentionally an
                // allow-list of "finished" states so that new/intermediate statuses
                // (e.g. ready_for_pickup, assigned, accepted, picked_up,
                // heading_to_customer, ...) are treated as active by default.
                // This enforces the "one active order per user" rule and reduces
                // fraud (important for cash-on-delivery markets).
                // Query user's orders using GSI_User
                const queryCommand = {
                    TableName: TABLE_NAME,
                    IndexName: 'GSI_User',
                    KeyConditionExpression: 'userId_gsi = :userId',
                    ExpressionAttributeValues: {
                        ':userId': body.userId
                    },
                    ScanIndexForward: false, // Latest orders first
                    Limit: 10 // Check last 10 orders should be enough
                };

                const result = await dynamoDb.send(new QueryCommand(queryCommand));
                
                if (result.Items && result.Items.length > 0) {
                    // Check if any order is active (not in a terminal/completed state)
                    const activeOrder = result.Items.find(order => 
                        !isTerminalOrderStatus(order.status)
                    );
                    
                    if (activeOrder) {
                        console.log('❌ Active order found:', activeOrder.orderId, 'Status:', activeOrder.status);
                        
                        return {
                            statusCode: 409, // Conflict
                            headers: headers,
                            body: JSON.stringify({
                                error: 'لديك طلب نشط بالفعل. يجب انتظار إتمام الطلب الحالي قبل إنشاء طلب جديد.',
                                success: false,
                                activeOrder: {
                                    orderId: activeOrder.orderId,
                                    orderNumber: activeOrder.orderNumber_gsi || activeOrder.orderNumber,
                                    status: activeOrder.status,
                                    createdAt: activeOrder.createdAt,
                                    storeName: activeOrder.storeName
                                }
                            })
                        };
                    }
                }
                
                console.log('✅ No active orders found. User can create new order.');
                
            } catch (error) {
                console.error('⚠️ Error checking active orders:', error);
                // In case of error checking active orders, we should still allow order creation
                // but log the error for monitoring
                console.warn('Proceeding with order creation despite active order check error');
            }
        }

        // Generate order ID and order number
        const orderId = quotedOrder ? quotedOrder.orderId : uuidv4();
        const timestamp = Date.now();
        const orderNumber = `ORD${timestamp}`;
        const tripNumber = `TRP${timestamp}`;
        const createdAt = new Date().toISOString();
        let merchantResponseBranch = null;

        // Helper function to generate bucket (b0-b9) from orderId hash for GSI distribution
        const generateBucket = (id) => {
            let hash = 0;
            for (let i = 0; i < id.length; i++) {
                hash = ((hash << 5) - hash) + id.charCodeAt(i);
                hash = hash & hash; // Convert to 32bit integer
            }
            return `b${Math.abs(hash) % 10}`;
        };

        const bucket = generateBucket(orderId);

        // Process items with complete WizzOrders schema - INCLUDING IMAGES
        const processedItems = body.items.map((item, index) => {
            const lineId = item.lineId || `line_${index + 1}`;
            const unitPrice = Math.round((item.price || item.base_price || 0) * 1000); // Convert to IQD fils
            const quantity = item.quantity || 1;
            
            return {
                lineId: lineId,
                skuId: item.id || item.skuId || item.productId,
                itemId: item.id || item.itemId || item.productId,
                categoryId: item.categoryId || item.category_id || null,
                name: item.name || item.dishName || 'عنصر غير محدد',
                quantity: quantity,
                unitPrice: unitPrice,
                // ✅ إضافة صورة الطبق من تطبيق المستخدم
                imageUrl: item.image || item.imageUrl || null,
                ...(Object.keys(require('../shared/discount-contract').discountOptionSelection(item)).length?{selectedOptions:require('../shared/discount-contract').discountOptionSelection(item)}:{}),
                modifiers: (item.modifiers || []).map(mod => ({
                    id: mod.id || uuidv4(),
                    name: mod.name || '',
                    price: Math.round((mod.price || 0) * 1000) // Convert to IQD fils
                })),
                notes: item.notes || item.specialInstructions || null
            };
        });

        // Calculate pricing in IQD fils according to schema
        const goodsSubtotal = processedItems.reduce((sum, item) => {
            const itemTotal = item.unitPrice * item.quantity;
            const modifiersTotal = (item.modifiers || []).reduce((modSum, mod) => 
                modSum + (mod.price * item.quantity), 0);
            return sum + itemTotal + modifiersTotal;
        }, 0);
        
        const minimumPolicy=require('../shared/branch-minimum-order');
        const minimumBranch=await minimumPolicy.read(dynamoDb,body.storeId);
        let serviceFee = Math.round((body.serviceFee || 0) * 1000);
        const packagingFee = Math.round((body.packagingFee || 0) * 1000);
        let deliveryFee = quotedOrder ? quotedOrder.deliveryFeeMinor : Math.round((body.deliveryFee ?? 10) * 1000); // Legacy only while quote mode is OFF
        const tax = Math.round((body.tax || 0) * 1000);
        const tip = Math.round((body.tip || 0) * 1000);
        const rounding = Math.round((body.rounding || 0) * 1000);

        const {orderOperation,catalogItems} = require('../shared/offer-eligibility');
        const accountOrder = await orderOperation(currentOffers.customer);
        let discountOperations = [
            ...(currentOffers.guarded.condition ? [currentOffers.guarded.condition] : []),
            ...(accountOrder ? [accountOrder] : []),
            ...(currentOffers.addressCondition ? [currentOffers.addressCondition] : [])
        ];
        let discountItems = [];
        if (body.discountId || body.promoCode || body.platformDiscountId || body.deliveryBenefitId || minimumPolicy.minimumOrderIqd(minimumBranch)!==null) {
            if (require('../shared/discount-contract').hasDiscountCustomizations(body.items)) throw Object.assign(Error('UNSUPPORTED_DISCOUNT_ITEMS'),{statusCode:409});
            const catalog = await createStagingOrderGoodsPricing({db:dynamoDb}).price({branchId:body.storeId,
                items:body.items.map(require('../shared/discount-contract').discountGoodsSelection)});
            if (catalog.goodsGross.minorAmount !== goodsSubtotal || catalog.lines.some((l,n)=>
                processedItems[n]?.itemId!==l.productId || processedItems[n]?.unitPrice !== l.unitPrice.minorAmount))
                throw Object.assign(Error('CART_PRICE_CHANGED'),{statusCode:409});
            if(commercialMode!=='REQUIRED')minimumPolicy.assertMinimumOrder(minimumBranch,catalog.goodsGross.minorAmount);
            catalog.lines.forEach((line,n)=>{if(line.lineId)processedItems[n].lineId=line.lineId;});
            discountItems = catalogItems(catalog);
            discountOperations.push(...catalog.conditions);
        }
        const resolvedDiscount = await resolveDiscount({db:dynamoDb,branchId:body.storeId,discountId:body.discountId,
            promoCode:body.promoCode,platformDiscountId:body.platformDiscountId,subtotal:goodsSubtotal,
            items:discountItems,deliveryFee,orderId,preview:body.action==='preview_commercial',...currentOffers});
        discountOperations.push(...resolvedDiscount.operations,
            ...await require('../shared/offer-attribution').attribution(dynamoDb,body.offerSlideId,resolvedDiscount.snapshot));
        if(body.deliveryBenefitId&&resolvedDiscount.platformDeliveryBenefit)throw Object.assign(Error('BENEFIT_STACKING_DENIED'),{statusCode:409});
        const selectedDeliveryBenefit=body.deliveryBenefitId?await require('../shared/platform-benefits').loadDelivery(dynamoDb,body.deliveryBenefitId,currentOffers):resolvedDiscount.platformDeliveryBenefit;
        if(selectedDeliveryBenefit&&resolvedDiscount.snapshot)require('../shared/platform-benefits').assertStacking(resolvedDiscount.campaign,selectedDeliveryBenefit.campaign);
        const discountFils = resolvedDiscount.amount;
        if (resolvedDiscount.snapshot &&
            (typeof body.discount !== 'number' || !Number.isFinite(body.discount) || Math.round(body.discount*1000) !== discountFils))
            throw Object.assign(Error('DISCOUNT_PREVIEW_CHANGED'),{statusCode:409});
        // Enforce pricing equation: total = goodsSubtotal + serviceFee + packagingFee + deliveryFee + tax + tip + rounding - discount
        let total = Math.max(0, goodsSubtotal + serviceFee + packagingFee + deliveryFee + tax + tip + rounding - discountFils);

        let commercial = null;
        if (commercialMode === 'REQUIRED') {
            if (!['cod','cash','cash_on_delivery'].includes(String(body.paymentMethod).toLowerCase()) ||
                processedItems.some(i=>i.modifiers.length) || packagingFee!==0 || tax!==0 || rounding!==0)
                throw Object.assign(Error('COMMERCIAL_ORDER_UNSUPPORTED'),{statusCode:409});
            const pricingReads=body.action==='preview_commercial'?require('./checkout-pricing-reads').createCheckoutPricingReads(dynamoDb):null;
            const pricingDb=pricingReads?.db??dynamoDb;
            // Commercial agreements are base terms, not stackable promotional benefits.
            const agreementAwareSelection=deliveryPromotionMode==='REQUIRED'?createStagingDeliveryPromotionSelection({db:pricingDb,lifecycleReadMode:'CONDITION_CHECK',previewOnly:body.action==='preview_commercial',
                agreementsOnly:!!selectedDeliveryBenefit||!!(resolvedDiscount.benefitReceipt&&!resolvedDiscount.campaign.benefit.allowGoodsStacking),
                pricingRequest:quotedOrder.deliveryPromotionPricingRequest(),
                customerFacts:()=>deliveryPromotionCustomerFacts(currentOffers,accountOrder)}):undefined;
            const deliveryPromotion=selectedDeliveryBenefit?require('../shared/platform-benefits').deliverySelection(pricingDb,selectedDeliveryBenefit,quotedOrder.deliveryPromotionPricingRequest(),body.action==='preview_commercial',agreementAwareSelection):agreementAwareSelection;
            commercial = await createStagingCommercialSource({cashRoundingRequired:process.env.CASH_ROUNDING_POLICY_MODE==='REQUIRED',db:pricingDb,deliveryPromotion,enableFullCash:process.env.FINANCIAL_SETTLEMENT_MODEL==='FULL_CASH_AT_DELIVERY_V1'}).prepare({orderId,branchId:body.storeId,
                items:body.items.map(require('../shared/discount-contract').discountGoodsSelection),
                quote:{createdAt:quotedOrder.createdAt,expiresAt:quotedOrder.expiresAt,deliveryFeeMinor:deliveryFee,
                    origin:quotedOrder.origin,destination:quotedOrder.destination,destinationRegionId:quotedOrder.destinationRegionId},
                discount:resolvedDiscount.snapshot?{snapshot:resolvedDiscount.snapshot,campaign:resolvedDiscount.campaign}:null,
                tip:moneyFromMinor(tip)});
            if(commercial.calculation.allocationInput.goodsGross.minorAmount!==goodsSubtotal || commercial.goodsLines.some((l,n)=>processedItems[n]?.itemId!==l.productId || processedItems[n]?.unitPrice!==l.unitPrice.minorAmount))
                throw Object.assign(Error('CART_PRICE_CHANGED'),{statusCode:409});
            commercial.goodsLines.forEach((line,n)=>{if(line.lineId)processedItems[n].lineId=line.lineId;});
            deliveryFee=commercial.calculation.allocationInput.customerDeliveryFee.minorAmount;
            // Legacy compatibility only. A published cash policy supplies the audited
            // effective service fee; disabled policy deliberately keeps exact totals.
            if(!commercial.cashRounding && commercial.calculation.customerTotal.minorAmount % 250000 !== 0)
                throw Object.assign(Error('CASH_TOTAL_DENOMINATION_UNSUPPORTED'),{statusCode:409});
            if(body.action==='preview_commercial') return {statusCode:200,headers,body:JSON.stringify({success:true,
                commercial:{schemaVersion:commercial.deliveryFunding?(commercial.deliveryAgreement?3:2):1,...(commercial.deliveryAgreement?{deliveryAgreement:commercial.deliveryAgreement}:{}),...(commercial.deliveryFunding?{referenceDeliveryFee:moneyFromMinor(quotedOrder.deliveryFeeMinor)}:{}),quoteId:body.quoteId,requestId:body.idempotencyKey,digest:commercial.digest,expiresAt:commercial.expiresAt,
                    customerTotal:commercial.calculation.customerTotal,goodsGross:commercial.calculation.allocationInput.goodsGross,
                    serviceFee:commercial.calculation.serviceFee.amount,discount:moneyFromMinor(discountFils),deliveryFee:moneyFromMinor(deliveryFee),driverTip:moneyFromMinor(tip)}})};
            if(body.commercialConsent?.digest!==commercial.digest ||
                body.commercialConsent?.customerTotalMinor!==commercial.calculation.customerTotal.minorAmount)
                throw Object.assign(Error('COMMERCIAL_CONSENT_REQUIRED'),{statusCode:409});
            serviceFee=commercial.calculation.serviceFee.amount.minorAmount;
            total=commercial.calculation.customerTotal.minorAmount;
            discountOperations.push(...commercial.operations,commercial.branchCondition);
        }

        // Determine user fields and generate guestToken for guest orders
        const isGuestOrder = body.userId === null || body.userId === 'guest' || !body.userId;
        let userIdForGSI;
        let guestToken = null;
        
        if (isGuestOrder) {
            // Generate unique guestToken for guest users
            guestToken = `GUEST_${Date.now()}_${Math.random().toString(36).substring(2, 15)}`;
            userIdForGSI = guestToken; // Use guestToken in GSI for efficient querying
        } else {
            userIdForGSI = body.userId;
        }
        
        // Format customer phone to E.164 format
        const formatPhoneToE164 = (phone) => {
            if (!phone) return null;
            
            // Remove all non-digit characters
            const digits = phone.replace(/\D/g, '');
            
            // If starts with 964, assume it's already international
            if (digits.startsWith('964')) {
                return `+${digits}`;
            }
            
            // If starts with 0, assume it's Iraq national format
            if (digits.startsWith('0')) {
                return `+964${digits.substring(1)}`;
            }
            
            // If 10 digits, assume Iraq national without leading 0
            if (digits.length === 10) {
                return `+964${digits}`;
            }
            
            // Otherwise, return as is with +
            return `+${digits}`;
        };

        const customerPhone = formatPhoneToE164(body.customerPhone);

        // Validate coordinates are within Iraq and not (0,0)
        const deliveryAddress = body.deliveryAddress ? formatDeliveryAddress(body.deliveryAddress, isGuestOrder) : null;
        if (deliveryAddress && deliveryAddress.lat && deliveryAddress.lng) {
            if (deliveryAddress.lat === 0 && deliveryAddress.lng === 0) {
                return {
                    statusCode: 400,
                    headers: headers,
                    body: JSON.stringify({
                        error: 'Invalid coordinates: (0,0) is not allowed',
                        success: false
                    })
                };
            }
            
            // Basic Iraq boundaries check (approximate)
            if (deliveryAddress.lat < 29 || deliveryAddress.lat > 38 || 
                deliveryAddress.lng < 38 || deliveryAddress.lng > 49) {
                console.warn('🚨 Coordinates might be outside Iraq boundaries:', {
                    lat: deliveryAddress.lat,
                    lng: deliveryAddress.lng
                });
            }
        }

        // Create complete WizzOrders schema compliant order
        // Ensure we have a real store address - enhanced fallback system
        let storeAddressToUse = body.storeAddress || '';
        let pickupRegionId = null; // 🆕 سيتم جلبه من جدول المطاعم
        let restaurantLat = null; // 🆕 إحداثيات المطعم
        let restaurantLng = null; // 🆕 إحداثيات المطعم
        let merchantPushSubjectId = null; // 🆕 Cognito sub used for merchant push notifications
        const placeholderValues = new Set(['العنوان غير محدد', 'عنوان غير محدد', '', null, undefined]);
        
        console.log('🏪 STORE INFO DEBUG:');
        console.log('Original storeAddress from frontend:', body.storeAddress);
        console.log('storeId:', body.storeId);
        console.log('storeName:', body.storeName);
        
        // 🆕 جلب معلومات المطعم من جدول المطاعم (للحصول على regionId والعنوان والإحداثيات)
        try {
            console.log('📍 Fetching restaurant details from Businesses table for storeId:', body.storeId);
            const getCmd = new GetCommand({
                TableName: BUSINESSES_TABLE,
                Key: { businessId: body.storeId }
            });
            const businessResult = await dynamoDb.send(getCmd);
            
            if (businessResult && businessResult.Item) {
                const business = businessResult.Item;
                merchantResponseBranch = business;

                // 🆕 Merchant push targeting
                // Central Notifications stores device tokens keyed by a separate `subjectId`.
                // Prefer an explicit mapping on the business record to avoid misrouting (e.g., to driver/user apps).
                const explicitPushSubjectId =
                    (typeof business.merchantPushSubjectId === 'string' && business.merchantPushSubjectId.trim())
                        ? business.merchantPushSubjectId.trim()
                        : (typeof business.pushSubjectId === 'string' && business.pushSubjectId.trim())
                            ? business.pushSubjectId.trim()
                            : null;

                if (explicitPushSubjectId) {
                    merchantPushSubjectId = explicitPushSubjectId;
                    console.log('✅ Found merchantPushSubjectId (explicit):', merchantPushSubjectId);
                } else if (typeof business.cognitoUserId === 'string' && business.cognitoUserId.trim()) {
                    merchantPushSubjectId = business.cognitoUserId.trim();
                    console.log('⚠️ Using merchantPushSubjectId fallback (cognitoUserId):', merchantPushSubjectId);
                } else if (typeof business.ownerId === 'string' && business.ownerId.trim()) {
                    merchantPushSubjectId = business.ownerId.trim();
                    console.log('⚠️ Using merchantPushSubjectId fallback (ownerId):', merchantPushSubjectId);
                } else {
                    console.warn('⚠️ Business record missing merchantPushSubjectId/pushSubjectId/cognitoUserId/ownerId; merchant push may be skipped');
                }
                
                // 🆕 جلب regionId من المطعم
                if (business.regionId) {
                    pickupRegionId = business.regionId;
                    console.log('✅ Found pickupRegionId from restaurant:', pickupRegionId);
                } else {
                    console.warn('⚠️ Restaurant does not have regionId field');
                }
                
                // 🆕 جلب إحداثيات المطعم من latitude, longitude
                if (business.latitude && business.longitude) {
                    restaurantLat = business.latitude;
                    restaurantLng = business.longitude;
                    console.log('✅ Found restaurant coordinates from Businesses table:', {
                        lat: restaurantLat,
                        lng: restaurantLng
                    });
                } else {
                    console.warn('⚠️ Restaurant does not have latitude/longitude fields');
                }
                
                // جلب العنوان إذا كان مفقوداً
                if (business.address && (!storeAddressToUse || placeholderValues.has(storeAddressToUse) || (typeof storeAddressToUse === 'string' && storeAddressToUse.trim() === ''))) {
                    storeAddressToUse = business.address;
                    console.log('✅ Found business address from Businesses table:', storeAddressToUse);
                }
            } else {
                console.warn('⚠️ No restaurant found in Businesses table for storeId:', body.storeId);
            }
        } catch (err) {
            console.error('❌ Error fetching restaurant details:', err);
        }
        
        // Fallback للعنوان إذا لم يتم العثور عليه
        if (!storeAddressToUse || placeholderValues.has(storeAddressToUse) || (typeof storeAddressToUse === 'string' && storeAddressToUse.trim() === '')) {
            const storeName = body.storeName || 'مطعم غير محدد';
            const fallbackAddresses = [
                `${storeName} - شارع الكرادة، بغداد، العراق`,
                `${storeName} - منطقة الجادرية، بغداد، العراق`,
                `${storeName} - شارع فلسطين، بغداد، العراق`,
                `${storeName} - منطقة الحارثية، بغداد، العراق`,
                `${storeName} - شارع الرشيد، بغداد المركز، العراق`,
                `${storeName} - منطقة المنصور، بغداد، العراق`
            ];
            const addressIndex = (body.storeId || 'default').length % fallbackAddresses.length;
            storeAddressToUse = fallbackAddresses[addressIndex];
            console.log('🔄 Using enhanced fallback address:', storeAddressToUse);
        }
        const order = {
            // Primary Keys - WizzOrders Schema
            PK: `ORDER#${orderId}`,
            SK: 'META',
            
            // Identity and Source (أ)
            orderId: orderId,
            orderNumber: orderNumber,
            tripNumber: tripNumber,
            currency: 'IQD',
            channel: body.channel || 'android', // ios | android | web | call_center | webhook | pos
            sourceSystem: body.sourceSystem || 'wizzuser', // When channel=webhook
            externalOrderId: body.externalOrderId || null,
            idempotencyKey: body.idempotencyKey || orderId,
            createdBy: 'wizzuser_app',
            updatedBy: 'wizzuser_app',
            rev: 1, // Version for optimistic locking
            
            // Customer and Merchant (ب)
            userId: isGuestOrder ? null : body.userId, // Keep legacy user id value
            userSub: userSub, // Cognito subject (sub) used for push token targeting
            guestToken: guestToken, // Token for guest order tracking
            isGuestOrder: isGuestOrder,
            customerName: body.customerName || (isGuestOrder ? 'ضيف' : null),
            customerPhone: customerPhone,
            storeId: body.storeId,
            storeName: body.storeName,
            storeAddress: storeAddressToUse, // عنوان المطعم للسائقين (مع fallback)
            // ✅ إضافة صورة المطعم من تطبيق المستخدم
            storeImage: body.storeImage || null,
            // 🆕 إضافة pickupRegionId للمطعم (حيوي لنظام توزيع الطلبات على السائقين)
            pickupRegionId: pickupRegionId,
            // 🆕 إضافة إحداثيات المطعم (لنظام Wave System)
            restaurantLat: restaurantLat,
            restaurantLng: restaurantLng,
            
            // Status and Timestamps (ج)
            status: 'pending',
            createdAt: createdAt,
            confirmedAt: null,
            inKitchenAt: null,
            readyAt: null,
            pickupAt: null,
            // deliveredAt: null, // ❌ REMOVED: Cannot be NULL because of GSI driverId-deliveredAt-index (sort key)
            // Note: deliveredAt will be added when order is delivered, not on order creation
            canceledAt: null,
            cancelReason: null,
            canceledBy: null,
            updatedAt: createdAt,
            
            // Delivery Type and Address (د)
            deliveryType: body.deliveryType || 'delivery', // delivery | pickup
            deliveryAddress: deliveryAddress,
            deliveryInstructions: body.deliveryInstructions || null,
            deliveryProvider: body.deliveryProvider || 'platform',
            
            // Cart Snapshot (ه)
            items: processedItems,
            
            // Pricing - Complete Schema (و)
            pricing: {
                goodsSubtotal: goodsSubtotal,
                serviceFee: serviceFee,
                packagingFee: packagingFee,
                deliveryFee: deliveryFee,
                tax: tax,
                tip: tip,
                rounding: rounding,
                discount: discountFils,
                total: total
            },

            // Applied merchant discount (if any)
            discountId: resolvedDiscount.snapshot?.source === 'MERCHANT' ? resolvedDiscount.snapshot.discountId : null,
            promoCode: resolvedDiscount.snapshot?.source === 'PLATFORM' ? resolvedDiscount.campaign?.code || null : null,
            offerSnapshot: resolvedDiscount.snapshot,
            platformBenefitReceipt: resolvedDiscount.benefitReceipt || commercial?.platformBenefitReceipt || null,
            platformDeliveryBenefitReceipt: commercial?.platformBenefitReceipt || null,
            offerUsageReservation: {
                schemaVersion: 1, userSub,
                accountReserved: !!accountOrder,
                customerReserved: resolvedDiscount.operations.some(op => op.Put?.TableName === 'staging-WizzOfferJourney' && op.Put.Item.sk?.startsWith('OFFER#')),
                campaign: resolvedDiscount.snapshot && !resolvedDiscount.benefitReceipt ? {
                    id: resolvedDiscount.snapshot.discountId, source: resolvedDiscount.snapshot.source,
                    createdAt: resolvedDiscount.campaign.createdAt ?? resolvedDiscount.campaign.created_at ?? null
                } : null
            },
            offerSlideId: body.offerSlideId || null,
            
            // Payment (ز)
            paymentMethod: body.paymentMethod || 'cod',
            paymentChannel: body.paymentChannel || 'cod',
            paymentStatus: 'pending',
            paymentIntentId: null,
            authorizedAt: null,
            capturedAt: null,
            voidedAt: null,
            
            // COD specific fields
            codCollectedAt: null,
            collectorId: null,
            cashReceived: null,
            changeGiven: null,
            
            // Driver/Delivery Fields (ح) - Only populated when driver is assigned
            // driverId: null, // ❌ REMOVED: Cannot be NULL because of GSI driverId-deliveredAt-index
            // Note: driverId will be added when driver is assigned, not on order creation
            deliveryJobId: null,
            eta: null,
            distanceMeters: body.distanceMeters || null,
            assignedAt: null,
            pickupAt: null, // Duplicate for driver tracking
            deliveryOTPUsed: false,
            recipientSignature: null,
            podPhotos: null,
            driverPayoutIQD: null,
            dispatchCostIQD: null,
            
            // Scheduling (ط)
            scheduled: body.scheduled || false,
            scheduledDate: body.scheduledDate || null,
            
            // GSI Helper Fields (ي)
            userId_gsi: userIdForGSI, // For GSI_User - use guestToken for guests, userId for registered users
            storeStatus: `${body.storeId}#pending#${bucket}`, // For GSI_StoreStatus
            paymentStatus_gsi: `pending#${bucket}`, // For GSI_Payment
            orderNumber_gsi: orderNumber, // For GSI_OrderNumber
            
            // Additional Fields
            metadata: body.metadata || null,
            notes: body.notes || body.specialInstructions || null,
            ttlEpoch: isGuestOrder ? (Math.floor(Date.now() / 1000) + (90 * 24 * 3600)) : (body.ttlEpoch || null), // Auto-delete guest orders after 90 days
            
            // Legacy Compatibility (keep for backward compatibility)
            total: Math.round(total / 1000), // Convert fils back to IQD for compatibility
            subtotal: Math.round(goodsSubtotal / 1000),
            deliveryFee_legacy: Math.round(deliveryFee / 1000),
            tax_legacy: Math.round(tax / 1000)
        };

        // Add scheduledDate_gsi and scheduledAt only for scheduled orders (sparse index)
        if (body.scheduledDate && body.scheduledDate.trim() !== '') {
            order.scheduledDate_gsi = body.scheduledDate;
            console.log('✅ Added scheduledDate_gsi for scheduled order:', body.scheduledDate);
        } else {
            console.log('✅ Omitting scheduledDate_gsi for non-scheduled order (sparse index)');
        }

        if (body.scheduledAt && body.scheduledAt.trim() !== '') {
            order.scheduledAt = body.scheduledAt;
            console.log('✅ Added scheduledAt for scheduled order:', body.scheduledAt);
        } else {
            console.log('✅ Omitting scheduledAt for non-scheduled order (sparse index)');
        }

        if (quotedOrder) {
            // Bind operational routing to the same points priced by the server.
            order.restaurantLat = quotedOrder.origin.latitude;
            order.restaurantLng = quotedOrder.origin.longitude;
            order.deliveryAddress.lat = quotedOrder.destination.latitude;
            order.deliveryAddress.lng = quotedOrder.destination.longitude;
            order.distanceMeters = quotedOrder.distanceMeters;
        }

        if (resolvedDiscount.snapshot) order.appliedDiscount = resolvedDiscount.snapshot;
        if (commercial) {
            order.merchantId=commercial.merchantId;
            order.financialSnapshot=commercial.financialSnapshot;
            if(commercial.settlementModel==='FULL_CASH_AT_DELIVERY_V1')order.exceptionPolicy=require('./quote-runtime/orderExceptionPolicy').createOrderExceptionPolicy(order.createdAt);
            order.commercialPricing={schemaVersion:commercial.schemaVersion,...(commercial.cashRounding?{cashRounding:commercial.cashRounding}:{}),...(commercial.deliveryAgreement?{deliveryAgreement:commercial.deliveryAgreement}:{}),...(commercial.deliveryCashRounding?{deliveryCashRounding:commercial.deliveryCashRounding}:{}),...(commercial.deliveryFunding?{deliveryFunding:commercial.deliveryFunding}:{}),digest:commercial.digest,agreement:commercial.agreement,
                calculation:commercial.calculation,funding:{...commercial.funding,state:commercial.settlementModel==='FULL_CASH_AT_DELIVERY_V1'?'BUDGET_COMMITTED_WITH_ORDER':commercial.funding.holdId?'RESERVED_WITH_ORDER':'NOT_REQUIRED'}};
        }

        const receptionEnabled=process.env.MERCHANT_RESPONSE_MODE==='REQUIRED'&&!order.scheduled&&!order.scheduledAt;
        if(receptionEnabled){
            if(!merchantResponseBranch)throw Object.assign(Error('MERCHANT_RESPONSE_POLICY_UNAVAILABLE'),{statusCode:503});
            if(merchantResponseBranch.ordersPausedUntil&&Date.parse(merchantResponseBranch.ordersPausedUntil)>Date.now())throw Object.assign(Error('BUSINESS_TEMPORARILY_PAUSED'),{statusCode:409});
            const receptionPlatform=(await baseDynamoDb.send(new GetCommand({TableName:'staging-PlatformStaff',Key:{pk:'OPERATIONAL_SETTINGS#ORDER_RECEPTION',sk:'CURRENT'},ConsistentRead:true}))).Item;
            Object.assign(order,require('../shared/merchant-response-policy').pendingFields(order,merchantResponseBranch,receptionPlatform));
        }
        console.log('Creating order', {orderId});

        // Save order to DynamoDB


        // Fence order creation against concurrent merchant/business closure,
        // including guest orders. A read before the write is not sufficient.
        const businessFences = [
            {ConditionCheck: {TableName: 'staging-AccountDeletion', Key: {pk: 'BUSINESS_LIFECYCLE#MERCHANT#' + body.storeId, sk: 'META'}, ConditionExpression: 'attribute_not_exists(pk)'}},
            {ConditionCheck: {TableName: BUSINESSES_TABLE, Key: {businessId: body.storeId}, ConditionExpression: 'attribute_exists(businessId) AND attribute_not_exists(deletionRequestId) AND isActive=:merchantActive AND (#merchantStatus=:merchantApproved OR #merchantStatus=:merchantLive) AND (attribute_not_exists(onboardingSchemaVersion) OR (onboardingComplete=:merchantActive AND acceptingOrders=:merchantActive)) AND (attribute_not_exists(platformSuspended) OR platformSuspended=:merchantBlocked) AND (attribute_not_exists(ordersBlocked) OR ordersBlocked=:merchantBlocked)', ExpressionAttributeNames: {'#merchantStatus':'status'}, ExpressionAttributeValues: {':merchantActive':true,':merchantApproved':'approved',':merchantLive':'active',':merchantBlocked':false}}},
        ];
        minimumPolicy.guard(businessFences[1].ConditionCheck,minimumBranch);
        if(receptionEnabled){
            const p=order.merchantResponsePolicy;
            const due=p.autoAccept?Date.parse(createdAt):Date.parse(order.merchantAcceptanceDeadlineAt);
            discountOperations.push({Put:{TableName:'staging-WalletLifecycle',Item:{operationId:'MERCHANT_RESPONSE#'+orderId,kind:'MERCHANT_RESPONSE',merchantResponseSchemaVersion:1,orderId,branchId:order.storeId,ownerId:merchantResponseBranch.ownerId,status:'PENDING',queuePartition:'MERCHANT_RESPONSE',nextAttemptAt:Math.floor(due/1000),createdAt},ConditionExpression:'attribute_not_exists(operationId)'}});
            const condition={TableName:BUSINESSES_TABLE,Key:{businessId:order.storeId},ConditionExpression:'attribute_not_exists(#mrPaused)',ExpressionAttributeNames:{'#mrPaused':'ordersPausedUntil','#mrSettings':'orderReceptionSettings'},ExpressionAttributeValues:{}};
            if(merchantResponseBranch.ordersPausedUntil!==undefined){condition.ConditionExpression='#mrPaused=:mrPaused AND #mrPaused<=:mrNow';Object.assign(condition.ExpressionAttributeValues,{':mrPaused':merchantResponseBranch.ordersPausedUntil,':mrNow':createdAt});}
            if(merchantResponseBranch.orderReceptionSettings===undefined)condition.ConditionExpression+=' AND attribute_not_exists(#mrSettings)';
            else {condition.ConditionExpression+=' AND #mrSettings=:mrSettings';condition.ExpressionAttributeValues[':mrSettings']=merchantResponseBranch.orderReceptionSettings;}
            if(!Object.keys(condition.ExpressionAttributeValues).length)delete condition.ExpressionAttributeValues;
            if(quotedOrder)discountOperations.push({ConditionCheck:condition});
            else {const c=businessFences[1].ConditionCheck;c.ConditionExpression+=' AND ('+condition.ConditionExpression+')';Object.assign(c.ExpressionAttributeNames,condition.ExpressionAttributeNames);Object.assign(c.ExpressionAttributeValues,condition.ExpressionAttributeValues||{});}
        }
        try {
            if (commercial && Date.now() >= Date.parse(commercial.expiresAt)) throw Object.assign(Error('COMMERCIAL_QUOTE_EXPIRED'),{statusCode:409});
            if (resolvedDiscount.expiresAt !== null && resolvedDiscount.expiresAt !== undefined && Date.now() >= resolvedDiscount.expiresAt)
                throw Object.assign(Error('DISCOUNT_EXPIRED'), {statusCode:409});
            discountOperations = await require('./quote-runtime/productInventory').reserveProductInventory(dynamoDb,order,discountOperations);
            if (quotedOrder) {
                const saved = await quotedOrder.commit(order, discountOperations, commercial?.deliveryFunding);
                if (saved.replayed) return quotedResponse(saved.order, true);
                Object.assign(order, saved.order);
            } else await dynamoDb.send(new TransactWriteCommand({TransactItems: [
                ...businessFences,
                ...discountOperations,
                {Put: {TableName: TABLE_NAME, Item: order, ConditionExpression: 'attribute_not_exists(orderId)'}},
            ]}));
        } catch (e) {
            if (e.name === 'TransactionCanceledException') throw Object.assign(new Error('ACCOUNT_OR_BUSINESS_UNAVAILABLE'), {statusCode: 409});
            throw e;
        }

        console.log('Order created successfully:', orderId);

        // Send order to merchant backend webhook (non-blocking)
        try {
            console.log('📨 Sending order to merchant backend...');
            const webhookResponse = await sendOrderToMerchant(order);
            console.log('📨 Merchant webhook response:', webhookResponse);
        } catch (webhookError) {
            // Don't fail the order creation if webhook fails
            console.error('📨 Merchant webhook failed (non-blocking):', webhookError.message);
            console.error('📨 Order creation will continue despite webhook failure');
        }

        // Send real-time notification to merchant's WebSocket (non-blocking)
        try {
            console.log('📡 Sending real-time notification to merchant...');
            await sendMerchantNotification(order);
            console.log('📡 Merchant notification sent successfully');
        } catch (notificationError) {
            // Don't fail the order creation if notification fails
            console.error('📡 Merchant notification failed (non-blocking):', notificationError.message);
        }

        // Send push notification to merchant (works when app is terminated) (non-blocking)
        // Prefer businessId targeting (storeId) to avoid cross-system subjectId mismatches.
        try {
            const businessId = order.storeId || '';
            if (!businessId) {
                console.log('ℹ️ Merchant push skipped (no businessId/storeId on order)');
            } else {
                const payload = {
                    action: 'new_order',
                    orderId: order.orderId,
                    orderNumber: order.orderNumber_gsi || order.orderNumber || '',
                    businessId,
                    businessName: order.storeName || '',
                    customerName: order.customerName || '',
                    totalAmount: order?.pricing?.total ? Math.round(order.pricing.total / 1000) : undefined,
                    updatedAt: new Date().toISOString()
                };

                if (merchantPushSubjectId) {
                    payload.subjectId = merchantPushSubjectId;
                }

                console.log('📲 Sending merchant push...', {
                    businessId,
                    subjectId: merchantPushSubjectId || null,
                    orderId: order.orderId
                });

                await sendMerchantOrderPush(payload);
            }
        } catch (pushError) {
            console.error('📲 Merchant push failed (non-blocking):', pushError?.message || String(pushError));
        }

        const response = {
            success: true,
            message: 'Order created successfully',
            orderId: orderId,
            orderNumber: orderNumber,
            order: customerOrderView(order)
        };

        // Add guestToken to response for guest orders
        if (isGuestOrder && guestToken) {
            response.guestToken = guestToken;
            console.log('🎫 Guest token generated for order:', guestToken);
        }

        return {
            statusCode: 201,
            headers: headers,
            body: JSON.stringify(response)
        };

    } catch (error) {
        console.error('Error creating order:', error);
        console.error('Error stack:', error.stack);
        console.error('Error name:', error.name);
        
        return {
            statusCode: error.statusCode || (['INSUFFICIENT_STOCK','GOODS_UNAVAILABLE'].includes(error.code||error.message)?409:error.name === 'DeliveryFundingReaderError' ? 503 : 500),
            headers: headers,
            body: JSON.stringify({
                error: 'Failed to create order',
                message: error.message,
                errorName: error.name,
                ...(error instanceof QuoteOrderError ? {code: error.code} :
                    ['INSUFFICIENT_STOCK','GOODS_UNAVAILABLE','DELIVERY_POLICY_UNAVAILABLE','DELIVERY_POLICY_AUTHORITY_REVOKED','DELIVERY_POLICY_HISTORY_MISMATCH','PLATFORM_GOODS_EXPOSURE_LIMIT_REQUIRED','BENEFIT_EXHAUSTED', 'BENEFIT_EXPIRED', 'BENEFIT_PAUSED', 'BENEFIT_NOT_ELIGIBLE', 'BENEFIT_WRONG_BRANCH', 'BENEFIT_WRONG_REGION', 'BENEFIT_MINIMUM_ORDER', 'BENEFIT_DELIVERY_CAP_EXCEEDED', 'BENEFIT_DISTANCE_EXCEEDED', 'BENEFIT_NO_SAVINGS', 'BENEFIT_STACKING_DENIED', 'BENEFIT_LOGIN_REQUIRED','MINIMUM_ORDER_NOT_MET','INVALID_MINIMUM_ORDER','FINANCE_ROLLOUT_OUT_OF_SCOPE','FINANCE_ROLLOUT_ADMISSION_CLOSED','FINANCE_ROLLOUT_NOT_CONFIGURED','OFFER_ACCOUNT_REQUIRED','OFFER_ADDRESS_UNAVAILABLE','OFFER_HISTORY_UNAVAILABLE','OFFER_AUDIENCE_UNSUPPORTED','OFFER_NOT_ELIGIBLE','OFFER_WRONG_MERCHANT','OFFER_WRONG_REGION','OFFER_FIRST_ORDER_ONLY','OFFER_ALREADY_USED','OFFER_NO_SAVINGS','OFFER_LOGIN_REQUIRED','OFFER_CUSTOMER_LIMIT_UNSUPPORTED','OFFER_DELIVERY_POLICY_REQUIRED','OFFER_REGION_UNSUPPORTED','OFFER_MERCHANT_UNSUPPORTED','QUOTE_NOT_ENABLED','QUOTE_NOT_CONFIGURED','CART_PRICE_CHANGED','CASH_TOTAL_DENOMINATION_UNSUPPORTED','CASH_ROUNDING_POLICY_UNAVAILABLE','UNSUPPORTED_DISCOUNT_ITEMS','DISCOUNT_PREVIEW_CHANGED','DISCOUNT_UNAVAILABLE','COMMERCIAL_NOT_CONFIGURED','COMMERCIAL_NOT_ENABLED','COMMERCIAL_CONSENT_REQUIRED','COMMERCIAL_ORDER_UNSUPPORTED','COMMERCIAL_QUOTE_EXPIRED','COMMERCIAL_SOURCE_UNAVAILABLE','DISCOUNT_FUNDING_TERMS_CHANGED','DISCOUNT_FUNDING_UNAVAILABLE','FUNDING_WALLET_PRECISION_UNSUPPORTED','COMMERCIAL_DISCOUNT_UNSUPPORTED','DISCOUNT_FUNDING_UNAUTHORIZED','OTHER_COMMERCIAL_CHARGES_UNSUPPORTED'].includes(error.message) ? {code: error.message} : {}),
                success: false
            })
        };
    }
};

/**
 * Send real-time notification to merchant's WebSocket connection
 * @param {Object} order - The order object
 * @returns {Promise} - Promise that resolves when notification is sent
 */
async function sendMerchantNotification(order) {
    console.log('📡 Preparing merchant notification for order:', order.orderId);
    
    // Use shared WizzUser WebSocket infrastructure for merchant notifications
    // This is the correct endpoint from WizzBusiness app_config.dart
    const WEBSOCKET_ENDPOINT = process.env.WEBSOCKET_ENDPOINT;
    const CONNECTIONS_TABLE = process.env.WEBSOCKET_CONNECTIONS_TABLE || process.env.CONNECTIONS_TABLE;

    if (!WEBSOCKET_ENDPOINT || !CONNECTIONS_TABLE) {
        console.warn('⚠️ Merchant WebSocket notification skipped (missing WEBSOCKET_ENDPOINT or WEBSOCKET_CONNECTIONS_TABLE/CONNECTIONS_TABLE env vars)');
        return;
    }
    
    try {
        const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
        const { DynamoDBDocumentClient, QueryCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
        const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');
        
        const dynamoClient = new DynamoDBClient({});
        const docClient = DynamoDBDocumentClient.from(dynamoClient);
        
        // Find active WebSocket connections for this merchant/business
        // We need to scan with FilterExpression because businessId is not in any GSI key
        // Alternative: query by userId if we can get it, but businessId is more reliable
        const { ScanCommand } = require('@aws-sdk/lib-dynamodb');
        
        const scanParams = {
            TableName: CONNECTIONS_TABLE,
            FilterExpression: 'businessId = :businessId AND isActive = :active',
            ExpressionAttributeValues: {
                ':businessId': order.storeId,
                ':active': true
            }
        };
        
        console.log('📡 Scanning for merchant WebSocket connections:', JSON.stringify(scanParams, null, 2));
        
        const scanResult = await docClient.send(new ScanCommand(scanParams));
        let connections = scanResult.Items || [];
        
        // Filter out expired connections based on TTL
        const currentTime = Math.floor(Date.now() / 1000);
        connections = connections.filter(conn => !conn.ttl || conn.ttl > currentTime);
        
        console.log(`📡 Found ${connections.length} active WebSocket connections for merchant ${order.storeId}`);
        
        if (connections.length === 0) {
            console.log('📡 No active WebSocket connections found for merchant, skipping notification');
            return;
        }
        
        // Initialize WebSocket API client with correct endpoint
        const apiGwClient = new ApiGatewayManagementApiClient({
            endpoint: WEBSOCKET_ENDPOINT.replace('wss://', 'https://'),
            region: process.env.AWS_REGION || 'us-east-1'
        });
        
        // Prepare notification message matching the format expected by RealtimeOrderService
        const notification = {
            type: 'NEW_ORDER',
            action: 'new_order', // For compatibility
            data: {
                orderId: order.orderId,
                orderNumber: order.orderNumber_gsi,
                storeId: order.storeId,
                storeName: order.storeName,
                customerName: order.customerName,
                customerPhone: order.customerPhone,
                items: order.items,
                pricing: order.pricing,
                total: order.pricing.total / 1000, // Convert fils to IQD for display
                deliveryAddress: order.deliveryAddress,
                deliveryType: order.deliveryType,
                paymentMethod: order.paymentMethod,
                notes: order.notes,
                createdAt: order.createdAt,
                status: order.status,
                isGuestOrder: order.isGuestOrder,
                channel: order.channel,
                currency: order.currency
            },
            timestamp: new Date().toISOString(),
            priority: 'HIGH' // Mark as high priority for immediate processing
        };
        
        const messageData = JSON.stringify(notification);
        console.log('📡 Prepared notification message:', messageData.substring(0, 300) + '...');
        
        // Send notification to all active connections
        const sendPromises = connections.map(async (connection) => {
            try {
                const command = new PostToConnectionCommand({
                    ConnectionId: connection.connectionId,
                    Data: messageData
                });
                
                await apiGwClient.send(command);
                console.log(`📡 ✅ Notification sent successfully to merchant connection: ${connection.connectionId}`);
                
            } catch (error) {
                console.error(`📡 ❌ Failed to send notification to connection ${connection.connectionId}:`, error);
                
                // If connection is stale (410 Gone error), mark it as inactive
                if (error.statusCode === 410 || error.$metadata?.httpStatusCode === 410) {
                    console.log(`📡 Marking stale connection as inactive: ${connection.connectionId}`);
                    try {
                        await docClient.send(new UpdateCommand({
                            TableName: CONNECTIONS_TABLE,
                            Key: {
                                connectionId: connection.connectionId
                            },
                            UpdateExpression: 'SET isActive = :active',
                            ExpressionAttributeValues: {
                                ':active': false
                            }
                        }));
                        console.log(`📡 Marked connection ${connection.connectionId} as inactive`);
                    } catch (updateError) {
                        console.error('📡 Failed to mark connection as inactive:', updateError);
                    }
                }
            }
        });
        
        await Promise.allSettled(sendPromises);
        console.log(`📡 Merchant notification completed for ${connections.length} connections`);
        
    } catch (error) {
        console.error('📡 Error sending merchant notification:', error);
        throw error;
    }
}

// No HTTP field or Lambda context can supply a database override. Only this
// module's point-preview composition invokes the private handler with one.
exports.handler=async event=>{
 let body;
 if(event.httpMethod==='POST'&&!event.isBase64Encoded&&typeof event.body==='string'&&Buffer.byteLength(event.body)<=64000){try{body=JSON.parse(event.body);}catch(_){}}
 if(body?.action==='preview_commercial')return handleOrder321(event,require('./point-invoice-321').readOnlyInvoiceDb323(baseDynamoDb));
 if(body?.action!=='preview_commercial_point')return handleOrder321(event);
 try{return await require('./point-invoice-321').prepare321({event,body,base:baseDynamoDb,run:handleOrder321,runtime:require('./point-invoice-runtime-321')});}
 catch(e){console.warn('POINT_INVOICE_UNAVAILABLE',{code:e.code||e.name});return{statusCode:e.statusCode||503,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*'},body:JSON.stringify({success:false,code:e.code||'POINT_INVOICE_UNAVAILABLE'})};}
};
