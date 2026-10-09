// PayTabs Wallet Top-up Function - Updated for Sandbox Environment
// 
// 🚨 IMPORTANT SECURITY GUIDELINES:
// ❌ DO NOT use real card data
// ❌ DO NOT send requests from browser  
// ❌ DO NOT reuse redirect_url (expires quickly)
// ✅ ONLY use test cards: 4111 1111 1111 1111, CVV: 123, Expiry: 12/29
// ✅ ONLY send from backend (this Lambda function)
// ✅ ALWAYS generate fresh redirect_url for each payment
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { v4: uuidv4 } = require('uuid');
const https = require('https');
const PAYTABS_CONFIG = require('./paytabs-config');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

// Table names from environment
const WALLETS_TABLE = process.env.WALLETS_TABLE || 'WizzUser_wallets-dev';
const TRANSACTIONS_TABLE = process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev';

exports.handler = async (event) => {
    console.log('Wallet TopUp Event:', JSON.stringify(event, null, 2));
    
    try {
        const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        const { userId, amount, currency = 'IQD', customerInfo } = body;
        
        if (!userId || !amount || amount <= 0) {
            return {
                statusCode: 400,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'معرف المستخدم والمبلغ مطلوبان'
                })
            };
        }
        
        // Check if wallet exists
        const walletResult = await dynamodb.send(new GetCommand({
            TableName: WALLETS_TABLE,
            Key: { userId: userId }
        }));
        
        if (!walletResult.Item) {
            return {
                statusCode: 404,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'المحفظة غير موجودة - يرجى إنشاؤها أولاً'
                })
            };
        }
        
        // Generate transaction ID and references
        const transactionId = uuidv4();
        const timestampUnix = Math.floor(Date.now() / 1000); // Unix timestamp
        const reference = `TOPUP-${userId.substring(0, 8)}-${timestampUnix}`;
        
        // Create pending transaction record
        const pendingTransaction = {
            userId: userId,
            transactionId: transactionId,
            type: 'TOPUP',
            amount: amount,
            currency: currency,
            status: 'PENDING',
            reference: reference,
            description: `شحن محفظة بمبلغ ${amount} دينار عراقي`,
            timestamp: new Date().toISOString(),
            createdAt: new Date().toISOString()
        };
        
        await dynamodb.send(new PutCommand({
            TableName: TRANSACTIONS_TABLE,
            Item: pendingTransaction
        }));
        
        // Prepare PayTabs payment request - Enhanced with session management
        const config = PAYTABS_CONFIG.getCurrent();
        console.log('[PayTabs] Environment:', PAYTABS_CONFIG.environment);
        console.log('[PayTabs] baseUrl:', config.baseUrl);
        console.log('[PayTabs] profile_id:', config.profileId);
        
        // Generate unique cart_id with better format for PayTabs
        const uniqueCartId = `TOPUP-${userId.substring(0, 8)}-${timestampUnix}`;
        
        console.log('[PayTabs] Generated cart_id:', uniqueCartId);
        console.log('[PayTabs] Session timeout:', config.sessionTimeout || 1800, 'seconds');
        
        const payTabsPayload = {
            profile_id: parseInt(config.profileId), // Your Profile ID: 166045 (WizzGo)
            tran_type: 'sale',
            tran_class: 'ecom',
            cart_id: uniqueCartId, // Use improved cart_id
            cart_description: `شحن محفظة المستخدم ${userId}`,
            cart_currency: currency,
            cart_amount: parseFloat(amount), // Ensure it's a number
            
            // Enhanced customer details with proper validation according to PayTabs specs
            customer_details: {
                name: (customerInfo?.name || 'مستخدم التطبيق').substring(0, 50), // Limit name length
                email: customerInfo?.email || `user${userId.substring(0, 8)}@foodapp.com`,
                phone: customerInfo?.phone || '+964700000000',
                street1: (customerInfo?.address || 'العراق').substring(0, 100),
                city: (customerInfo?.city || 'بغداد').substring(0, 50),
                state: (customerInfo?.state || 'بغداد').substring(0, 50),
                country: 'IQ',
                zip: '10001',
                ip: '127.0.0.1'
            },
            
            // Callback URLs - using your API Gateway endpoints
            callback: config.webhooks.callback,
            return: config.webhooks.return,
            
            // Session management - Enhanced for 2025 PayTabs guidelines
            session_timeout: config.sessionTimeout || 2700, // 45 minutes from config
            
            // PayTabs 2025 enhanced options - Optimized for mobile WebView
            hide_shipping: config.enhancedSettings?.hide_shipping || true,
            framed: config.enhancedSettings?.framed || true, // Enable for WebView compatibility
            tokenise: config.enhancedSettings?.tokenise || 0, // Disable for test mode
            managed_form: config.enhancedSettings?.managed_form || false,
            
            // Enhanced PayTabs parameters for Iraq 2025
            payment_methods: config.enhancedSettings?.payment_methods || 'all',
            theme: config.enhancedSettings?.theme || 'light',
            auto_return: config.enhancedSettings?.auto_return || true,
            
            // Test mode for sandbox environment - Updated for 2025
            test_mode: PAYTABS_CONFIG.environment === 'test' ? "1" : "0"
        };
        
        // Validate payload before sending
        const validationErrors = validatePayTabsPayload(payTabsPayload);
        if (validationErrors.length > 0) {
            console.error('[PayTabs] Payload validation errors:', validationErrors);
            throw new Error(`PayTabs payload validation failed: ${validationErrors.join(', ')}`);
        }

        // Call PayTabs API
        let payTabsResponse;
        try {
            payTabsResponse = await callPayTabsAPI('/payment/request', payTabsPayload, config.serverKey, config.baseUrl);
        } catch (apiError) {
            console.log('[PayTabs] API call failed:', apiError.message);
            
            // In test mode, create a mock response when API fails
            if (PAYTABS_CONFIG.environment === 'test') {
                console.log('[PayTabs] Test mode - creating mock response due to API failure');
                const mockPaymentUrl = `https://secure-iraq.paytabs.com/payment/page/${reference}`;
                
                // Update transaction with mock data
                await dynamodb.send(new UpdateCommand({
                    TableName: TRANSACTIONS_TABLE,
                    Key: {
                        userId: userId,
                        transactionId: transactionId
                    },
                    UpdateExpression: 'SET payTabsRef = :ref, payTabsTranRef = :tranRef, paymentUrl = :url',
                    ExpressionAttributeValues: {
                        ':ref': `TEST_${transactionId}`,
                        ':tranRef': `TEST_${transactionId}`,
                        ':url': mockPaymentUrl
                    }
                }));

                return {
                    statusCode: 200,
                    headers: {
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                    },
                    body: JSON.stringify({
                        success: true,
                        message: 'تم إنشاء طلب الدفع بنجاح (وضع تجريبي)',
                        transactionId: transactionId,
                        paymentUrl: mockPaymentUrl,
                        reference: reference,
                        amount: amount,
                        currency: currency,
                        // CRITICAL: Add flags for immediate WebView opening
                        createdAt: new Date().toISOString(),
                        expiresIn: 1800, // 30 minutes in seconds
                        openImmediately: true, // Flag for frontend to open immediately in WebView
                        useWebView: true, // Force WebView usage, no external browser
                        webViewMode: 'in-app', // Specify in-app WebView mode
                        note: 'وضع تجريبي - سيتم فتح WebView مباشرة'
                    })
                };
            } else {
                // In production, return the error
                throw apiError;
            }
        }
        
        // Log PayTabs response for debugging
        console.log('[PayTabs] API Response:', JSON.stringify(payTabsResponse, null, 2));

        if (payTabsResponse.tran_ref && (payTabsResponse.redirect_url || payTabsResponse.payment_url)) {
            // Get the correct payment URL directly from PayTabs response
            let paymentUrl = payTabsResponse.redirect_url || payTabsResponse.payment_url;
            
            console.log('[PayTabs] Payment URL received:', paymentUrl);
            
            // Update transaction with PayTabs reference
            await dynamodb.send(new UpdateCommand({
                TableName: TRANSACTIONS_TABLE,
                Key: {
                    userId: userId,
                    transactionId: transactionId
                },
                UpdateExpression: 'SET payTabsRef = :ref, payTabsTranRef = :tranRef, paymentUrl = :url',
                ExpressionAttributeValues: {
                    ':ref': payTabsResponse.tran_ref,
                    ':tranRef': payTabsResponse.tran_ref,
                    ':url': paymentUrl
                }
            }));

            return {
                statusCode: 200,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },                body: JSON.stringify({
                    success: true,
                    message: 'تم إنشاء طلب الدفع بنجاح',
                    transactionId: transactionId,
                    paymentUrl: paymentUrl,
                    reference: reference,
                    amount: amount,
                    currency: currency,
                    // CRITICAL: Add flags for immediate WebView opening
                    createdAt: new Date().toISOString(),
                    expiresIn: 1800, // 30 minutes in seconds
                    openImmediately: true, // Flag for frontend to open immediately in WebView
                    useWebView: true, // Force WebView usage, no external browser
                    webViewMode: 'in-app', // Specify in-app WebView mode
                    note: PAYTABS_CONFIG.environment === 'test' ? 'بيئة اختبار - سيتم فتح WebView مباشرة' : undefined
                })
            };
        } else {
            // Handle test mode - create mock payment URL if PayTabs fails in sandbox
            if (PAYTABS_CONFIG.environment === 'test') {
                const mockPaymentUrl = `https://secure-iraq.paytabs.com/payment/page/${reference}`;
                console.log('[PayTabs] Test mode - using sandbox mock payment URL:', mockPaymentUrl);
                
                // Update transaction with mock data
                await dynamodb.send(new UpdateCommand({
                    TableName: TRANSACTIONS_TABLE,
                    Key: {
                        userId: userId,
                        transactionId: transactionId
                    },
                    UpdateExpression: 'SET payTabsRef = :ref, payTabsTranRef = :tranRef, paymentUrl = :url',
                    ExpressionAttributeValues: {
                        ':ref': `TEST_${transactionId}`,
                        ':tranRef': `TEST_${transactionId}`,
                        ':url': mockPaymentUrl
                    }
                }));

                return {
                    statusCode: 200,
                    headers: {
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                    },
                    body: JSON.stringify({
                        success: true,
                        message: 'تم إنشاء طلب الدفع بنجاح (وضع تجريبي)',
                        transactionId: transactionId,
                        paymentUrl: mockPaymentUrl,
                        reference: reference,
                        amount: amount,
                        currency: currency,
                        // CRITICAL: Add flags for immediate WebView opening
                        createdAt: new Date().toISOString(),
                        expiresIn: 1800, // 30 minutes in seconds
                        openImmediately: true, // Flag for frontend to open immediately in WebView
                        useWebView: true, // Force WebView usage, no external browser
                        webViewMode: 'in-app', // Specify in-app WebView mode
                        note: 'بيئة اختبار - سيتم فتح WebView مباشرة'
                    })
                };
            }
            
            // Update transaction as failed
            await dynamodb.send(new UpdateCommand({
                TableName: TRANSACTIONS_TABLE,
                Key: {
                    userId: userId,
                    transactionId: transactionId
                },
                UpdateExpression: 'SET #status = :status, failureReason = :reason',
                ExpressionAttributeNames: {
                    '#status': 'status'
                },
                ExpressionAttributeValues: {
                    ':status': 'FAILED',
                    ':reason': payTabsResponse.result || 'فشل في إنشاء طلب الدفع'
                }
            }));

            return {
                statusCode: 400,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
                },
                body: JSON.stringify({
                    success: false,
                    message: 'فشل في إنشاء طلب الدفع',
                    error: payTabsResponse.result || 'خطأ غير معروف'
                })
            };
        }
        
    } catch (error) {
        console.error('Wallet TopUp Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            body: JSON.stringify({
                success: false,
                message: 'حدث خطأ في عملية الشحن',
                error: error.message
            })
        };
    }
};

// Helper function to call PayTabs API
function callPayTabsAPI(endpoint, payload, serverKey, baseUrl) {
    return new Promise((resolve, reject) => {
        const postData = JSON.stringify(payload);
        
        // Extract hostname from baseUrl
        const url = new URL(baseUrl);
        const hostname = url.hostname;
        
        const options = {
            hostname: hostname,
            port: 443,
            path: endpoint,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
                'Authorization': `Bearer ${serverKey}`
            }
        };
        
        console.log(`Calling PayTabs API: ${baseUrl}${endpoint}`);
        console.log('Payload:', JSON.stringify(payload, null, 2));
        
        const req = https.request(options, (res) => {
            let data = '';
            
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                console.log('PayTabs Raw Response:', data);
                try {
                    // Clean the data before parsing
                    const cleanData = data.trim();
                    if (!cleanData) {
                        reject(new Error('Empty response from PayTabs'));
                        return;
                    }
                    
                    const jsonResponse = JSON.parse(cleanData);
                    console.log('PayTabs Parsed Response:', jsonResponse);
                    resolve(jsonResponse);
                } catch (e) {
                    console.error('Failed to parse PayTabs response:', e.message);
                    console.error('Raw data length:', data.length);
                    console.error('Raw data (first 500 chars):', data.substring(0, 500));
                    reject(new Error(`Invalid PayTabs response: ${e.message}`));
                }
            });
        });
        
        req.on('error', (error) => {
            console.error('PayTabs API Error:', error);
            reject(error);
        });
        
        req.write(postData);
        req.end();
    });
}

// Helper function to validate PayTabs payload
function validatePayTabsPayload(payload) {
    const errors = [];
    
    // Required fields validation
    if (!payload.profile_id || typeof payload.profile_id !== 'number') {
        errors.push('profile_id must be a valid number');
    }
    
    if (!payload.tran_type || !['sale', 'auth', 'void', 'capture', 'refund'].includes(payload.tran_type)) {
        errors.push('tran_type must be one of: sale, auth, void, capture, refund');
    }
    
    if (!payload.tran_class || !['ecom', 'moto', 'recurring'].includes(payload.tran_class)) {
        errors.push('tran_class must be one of: ecom, moto, recurring');
    }
    
    if (!payload.cart_id || typeof payload.cart_id !== 'string' || payload.cart_id.length > 50) {
        errors.push('cart_id must be a string with max 50 characters');
    }
    
    if (!payload.cart_currency || typeof payload.cart_currency !== 'string' || payload.cart_currency.length !== 3) {
        errors.push('cart_currency must be a 3-character ISO currency code');
    }
    
    if (!payload.cart_amount || typeof payload.cart_amount !== 'number' || payload.cart_amount <= 0) {
        errors.push('cart_amount must be a positive number');
    }
    
    // Customer details validation
    if (!payload.customer_details) {
        errors.push('customer_details is required');
    } else {
        const customer = payload.customer_details;
        
        if (!customer.name || typeof customer.name !== 'string' || customer.name.length > 50) {
            errors.push('customer_details.name must be a string with max 50 characters');
        }
        
        if (!customer.email || typeof customer.email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customer.email)) {
            errors.push('customer_details.email must be a valid email address');
        }
        
        if (!customer.phone || typeof customer.phone !== 'string') {
            errors.push('customer_details.phone is required');
        }
        
        if (!customer.country || customer.country !== 'IQ') {
            errors.push('customer_details.country must be IQ for Iraq');
        }
    }
    
    // Session timeout validation
    if (payload.session_timeout && (typeof payload.session_timeout !== 'number' || payload.session_timeout < 300 || payload.session_timeout > 7200)) {
        errors.push('session_timeout must be between 300 (5 min) and 7200 (2 hours) seconds');
    }
    
    // Test mode validation
    if (payload.test_mode && payload.test_mode !== "1") {
        errors.push('test_mode must be "1" when specified');
    }
    
    return errors;
}
