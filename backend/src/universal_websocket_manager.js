#!/usr/bin/env node

/**
 * Universal WebSocket Connection Manager
 * النظام الموحد لإدارة اتصالات WebSocket لجميع التطبيقات
 * 
 * Features:
 * 1. إنشاء سجل واحد بمعلومات كاملة عند الاتصال
 * 2. تحديث status (connect/disconnect) بدلاً من الحذف
 * 3. منع الاتصالات المتعددة للمستخدم الواحد
 * 4. تنظيف دوري للسجلات القديمة
 * 5. دعم جميع أنواع التطبيقات (driver, customer, business)
 */

const { DynamoDBClient, DescribeTableCommand } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand, DeleteCommand, QueryCommand, ScanCommand, BatchWriteCommand } = require('@aws-sdk/lib-dynamodb');
const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');

class UniversalWebSocketManager {
    constructor() {
        this.dynamoClient = new DynamoDBClient({
            region: process.env.AWS_REGION || 'us-east-1'
        });
        this.dynamoDB = DynamoDBDocumentClient.from(this.dynamoClient);
        this.connectionsTable =
            process.env.WEBSOCKET_CONNECTIONS_TABLE ||
            process.env.WIZZUSER_CONNECTIONS_TABLE ||
            process.env.CONNECTIONS_TABLE ||
            process.env.WEBSOCKET_TABLE ||
            'WizzUser_websocket_connections_dev';
        this.subscriptionsTable =
            process.env.WEBSOCKET_SUBSCRIPTIONS_TABLE ||
            process.env.SUBSCRIPTIONS_TABLE ||
            'WizzUser_websocket_subscriptions_dev';
        
        // تكوين API Gateway WebSocket endpoint حسب التطبيق
        this.apiGatewayEndpoints = {
            driver: process.env.DRIVER_WEBSOCKET_ENDPOINT,
            customer: process.env.CUSTOMER_WEBSOCKET_ENDPOINT,
            business: process.env.BUSINESS_WEBSOCKET_ENDPOINT
        };

        console.log('🔧 UniversalWebSocketManager tables:', {
            connectionsTable: this.connectionsTable,
            subscriptionsTable: this.subscriptionsTable
        });

        // Cached table schema detection (to support different DynamoDB key schemas across envs)
        this._connectionsSchema = null;
        this._connectionsSchemaPromise = null;
    }

    getEnvironmentName() {
        const explicit =
            process.env.WEBSOCKET_STAGE ||
            process.env.WEBSOCKET_ENV ||
            process.env.ENVIRONMENT ||
            process.env.Environment ||
            process.env.STAGE ||
            process.env.STAGE_NAME;

        if (explicit) return explicit;

        const table = this.connectionsTable || '';
        if (table.endsWith('_staging')) return 'staging';
        if (table.endsWith('_prod')) return 'prod';
        if (table.endsWith('_dev')) return 'dev';

        return 'dev';
    }

    isInvalidId(value) {
        if (value === undefined || value === null) return true;
        const s = String(value).trim().toLowerCase();
        return s === '' || s === 'unknown' || s === 'null' || s === 'undefined' || s === 'none';
    }

    async detectConnectionsSchemaByProbe() {
        // If DescribeTable is not allowed by IAM, probe both key styles.
        // - connectionId-only tables will accept Key: { connectionId }
        // - legacy tables will accept Key: { PK, SK }
        // We use a random/non-existent id; success here means "valid key schema".
        const probeId = `schema_probe_${Date.now()}_${Math.random().toString(16).slice(2)}`;

        try {
            await this.dynamoDB.send(new GetCommand({
                TableName: this.connectionsTable,
                Key: { connectionId: probeId }
            }));
            return { keyType: 'connectionId', userIndexName: null, detectedBy: 'probe' };
        } catch (error) {
            const msg = error?.message || '';
            // If key is wrong, DynamoDB returns ValidationException about missing key schema.
            if (msg.includes('missed key schema') || msg.includes('ValidationException')) {
                // keep probing legacy
            } else {
                console.warn('⚠️ Probe (connectionId) failed unexpectedly:', msg);
            }
        }

        try {
            await this.dynamoDB.send(new GetCommand({
                TableName: this.connectionsTable,
                Key: { PK: `CONNECTION#${probeId}`, SK: `CONNECTION#${probeId}` }
            }));
            return { keyType: 'pk_sk', userIndexName: 'GSI1', detectedBy: 'probe' };
        } catch (error) {
            console.warn('⚠️ Probe (PK/SK) failed; defaulting to connectionId schema:', error?.message || error);
            return { keyType: 'connectionId', userIndexName: null, detectedBy: 'probe_fallback' };
        }
    }

    async getConnectionsSchema() {
        if (this._connectionsSchema) {
            return this._connectionsSchema;
        }

        if (this._connectionsSchemaPromise) {
            return await this._connectionsSchemaPromise;
        }

        this._connectionsSchemaPromise = (async () => {
            try {
                const result = await this.dynamoClient.send(new DescribeTableCommand({
                    TableName: this.connectionsTable
                }));

                const keySchema = result?.Table?.KeySchema || [];
                const gsi = result?.Table?.GlobalSecondaryIndexes || [];

                const isConnectionIdOnly =
                    keySchema.length === 1 &&
                    keySchema[0]?.KeyType === 'HASH' &&
                    keySchema[0]?.AttributeName === 'connectionId';

                const hasLegacyGSI1 = gsi.some(i => i?.IndexName === 'GSI1');
                const hasUserIdConnectedAt = gsi.some(i => i?.IndexName === 'userId-connectedAt-index');

                const schema = {
                    keyType: isConnectionIdOnly ? 'connectionId' : 'pk_sk',
                    userIndexName: hasUserIdConnectedAt ? 'userId-connectedAt-index' : (hasLegacyGSI1 ? 'GSI1' : null)
                };

                console.log('🔧 Detected connections table schema:', {
                    table: this.connectionsTable,
                    ...schema
                });

                this._connectionsSchema = schema;
                return schema;
            } catch (error) {
                console.warn('⚠️ Failed to describe connections table, probing schema:', error?.message || error);
                const probed = await this.detectConnectionsSchemaByProbe();
                console.log('🔧 Detected connections table schema by probe:', {
                    table: this.connectionsTable,
                    ...probed
                });
                this._connectionsSchema = { keyType: probed.keyType, userIndexName: probed.userIndexName };
                return this._connectionsSchema;
            }
        })();

        return await this._connectionsSchemaPromise;
    }

    buildConnectionKey(connectionId, record) {
        if (this._connectionsSchema?.keyType === 'connectionId') {
            return { connectionId };
        }

        // Legacy PK/SK schema
        const pk = record?.PK || `CONNECTION#${connectionId}`;
        const sk = record?.SK || `CONNECTION#${connectionId}`;
        return { PK: pk, SK: sk };
    }

    /**
     * إنشاء اتصال جديد مع معلومات كاملة
     * يدعم جميع أنواع التطبيقات
     */
    async handleConnect(connectionId, event) {
        try {
            // 🔍 DEBUG: سجل كل شيء من event
            console.log(`🔍 [DEBUG] Full event object:`, JSON.stringify(event, null, 2));
            
            const queryParams = event.queryStringParameters || {};
            const headers = event.headers || {};
            
            // 🔍 DEBUG: سجل query params بوضوح
            console.log(`🔍 [DEBUG] Query params object:`, JSON.stringify(queryParams, null, 2));
            console.log(`🔍 [DEBUG] Query params keys:`, Object.keys(queryParams));
            
            // استخراج المعلومات الأساسية
            const {
                token,
                userId,
                userType,
                entityType,
                businessId,
                driverId,
                deviceId,
                platform,
                appVersion
            } = queryParams;

            // 🔍 DEBUG: سجل كل parameter بشكل منفصل
            console.log(`🔍 [DEBUG] Extracted parameters:`, {
                token: token ? `EXISTS (${token.length} chars)` : 'UNDEFINED',
                userId: userId ? `EXISTS (${userId})` : 'UNDEFINED',
                userType: userType || 'UNDEFINED',
                entityType: entityType || 'UNDEFINED',
                businessId: businessId || 'UNDEFINED',
                driverId: driverId || 'UNDEFINED'
            });

            console.log(`🔌 اتصال جديد: ${connectionId}`, {
                userType, entityType, userId, businessId, driverId
            });

            // تحديد نوع الكيان أولاً
            const finalEntityType = this.determineEntityType(userType, entityType, queryParams);
            console.log(`🔍 نوع الكيان المحدد: ${finalEntityType}`);

            // التحقق من الـ JWT والمستخدمين المسجلين والضيوف
            let verified = null;
            let finalUserId = null;
            let userCategory = 'guest'; // 'registered' أو 'guest' أو 'business'
            
            // === معالجة حسب نوع الكيان ===
            
            // 1. إذا كان تاجر (Business/Merchant)
            if (finalEntityType === 'business' || finalEntityType === 'merchant') {
                if (!businessId) {
                    throw new Error('businessId مطلوب لاتصالات التجار');
                }
                
                // محاولة التحقق من JWT للتاجر أولاً
                if (token) {
                    try {
                        verified = await this.verifyJwt(token);
                        console.log(`🔐 تم التحقق من JWT للتاجر`);
                        
                        // ✅ استخدام verified.sub من JWT (Cognito User ID)
                        if (verified && verified.sub) {
                            finalUserId = verified.sub;
                            userCategory = 'business';
                            console.log(`🏢 اتصال تاجر من JWT: businessId=${businessId}, cognitoUserId=${finalUserId}`);
                        }
                    } catch (error) {
                        console.warn(`⚠️ فشل التحقق من JWT للتاجر: ${error.message}`);
                    }
                }
                
                // ✅ Fallback: استخدم userId من query params إذا كان Cognito User ID صحيح
                // Validation: يجب أن يكون UUID (صيغة: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
                // وليس businessId (يبدأ بـ business_)
                if (!finalUserId && userId) {
                    const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId);
                    if (isUUID && !userId.startsWith('business_')) {
                        finalUserId = userId;
                        userCategory = 'business';
                        console.log(`🏢 اتصال تاجر من userId (UUID validated): businessId=${businessId}, cognitoUserId=${finalUserId}`);
                    } else {
                        console.warn(`⚠️ userId غير صالح للتاجر - يجب أن يكون Cognito User ID (UUID): ${userId}`);
                    }
                }
                
                // إذا فشل كل شيء، ارمِ خطأ
                if (!finalUserId) {
                    throw new Error('userId (Cognito User ID) مطلوب لاتصالات التجار - يجب تقديم JWT token صالح أو userId بصيغة UUID');
                }
            }
            
            // 2. إذا كان سائق (Driver)
            else if (finalEntityType === 'driver') {
                // Prefer explicit driverId if it's not a placeholder (unknown/null)
                if (!this.isInvalidId(driverId)) {
                    finalUserId = driverId;
                    userCategory = 'driver';
                    console.log(`🚗 اتصال سائق من driverId: ${finalUserId}`);
                }

                // Try JWT (Cognito sub) when driverId is missing/invalid
                if (!finalUserId && token) {
                    try {
                        verified = await this.verifyJwt(token);
                        console.log(`🔐 تم التحقق من JWT للسائق`);
                        if (verified?.sub && !this.isInvalidId(verified.sub)) {
                            finalUserId = verified.sub;
                            userCategory = 'driver';
                            console.log(`🚗 اتصال سائق من JWT.sub: ${finalUserId}`);
                        }
                    } catch (error) {
                        console.warn(`⚠️ فشل التحقق من JWT للسائق: ${error.message}`);
                    }
                }

                // Fallback: accept userId if present and valid
                if (!finalUserId && !this.isInvalidId(userId)) {
                    finalUserId = userId;
                    userCategory = 'driver';
                    console.log(`🚗 اتصال سائق من userId: ${finalUserId}`);
                }

                // Best-effort JWT parsing for authenticated flag + cognitoSub, even if driverId is already known
                if (!verified && token) {
                    try {
                        verified = await this.verifyJwt(token);
                        if (verified?.sub) {
                            console.log(`🔐 Parsed driver JWT.sub for connection record: ${verified.sub}`);
                        }
                    } catch (error) {
                        console.warn(`⚠️ Failed to parse JWT for driver connection record: ${error.message}`);
                    }
                }

                // If we still can't identify the driver, keep the connection but do not pretend it's a real driver
                if (!finalUserId) {
                    throw new Error('driverId أو JWT token صالح مطلوب لاتصالات السائقين');
                }

                // Ensure saved record fields are consistent
                queryParams.driverId = finalUserId;
                if (this.isInvalidId(queryParams.userId)) {
                    queryParams.userId = finalUserId;
                }
            }
            
            // 3. إذا كان عميل (Customer/User/Guest)
            else if (finalEntityType === 'customer' || finalEntityType === 'user' || finalEntityType === 'guest') {
                
                // أ) محاولة التحقق من JWT للمستخدمين المسجلين
                if (token) {
                    try {
                        verified = await this.verifyJwt(token);
                        if (verified && (verified.sub || verified.email || verified.username)) {
                            finalUserId = verified.sub || verified.email || verified.username;
                            userCategory = 'registered';
                            console.log(`🔐 عميل مسجل من JWT: ${finalUserId}`);
                        }
                    } catch (error) {
                        console.warn(`⚠️ فشل التحقق من JWT: ${error.message}`);
                        // 🔒 CRITICAL FIX: إذا فشل JWT ولا يوجد معرف ضيف صريح، ارفض الاتصال
                        if (!userId && userType !== 'guest' && entityType !== 'guest' && !queryParams.guestId) {
                            console.error(`❌ رفض الاتصال: JWT غير صالح ولا يوجد معرف ضيف`);
                            throw new Error('JWT token is invalid and no guest identifier provided');
                        }
                    }
                }
                
                // ب) إذا لم يكن هناك token صحيح، لكن هناك userId
                if (!finalUserId && userId) {
                    // 🔧 إصلاح: التحقق من أن userId يبدأ بـ "user_" للمستخدمين المسجلين
                    if (userId.startsWith('user_')) {
                        // 🔒 CRITICAL FIX: يجب التحقق من JWT قبل قبول userId مسجل
                        if (!token) {
                            console.error(`❌ رفض الاتصال: userId مسجل بدون JWT token`);
                            throw new Error('Registered userId requires valid JWT token');
                        }
                        finalUserId = userId;
                        userCategory = 'registered';
                        console.log(`👤 عميل مسجل من userId: ${finalUserId}`);
                    } 
                    // إذا كان userId يبدأ بـ "GUEST#" أو "guest-" فهو ضيف
                    else if (userId.startsWith('GUEST#') || userId.startsWith('guest-')) {
                        finalUserId = userId;
                        userCategory = 'guest';
                        console.log(`👤 عميل ضيف من userId: ${finalUserId}`);
                    }
                    // خلاف ذلك، اعتبره مسجل (userId عادي) - يتطلب JWT
                    else {
                        // 🔒 CRITICAL FIX: userId عادي (مسجل) يتطلب JWT
                        if (!token) {
                            console.error(`❌ رفض الاتصال: userId غير ضيف بدون JWT token`);
                            throw new Error('Non-guest userId requires valid JWT token');
                        }
                        finalUserId = userId;
                        userCategory = 'registered';
                        console.log(`👤 عميل مسجل (معرف عادي): ${finalUserId}`);
                    }
                }
                
                // ج) التحقق من طلب صريح لاتصال ضيف
                if (!finalUserId && (userType === 'guest' || entityType === 'guest')) {
                    // استخدام guestId من params أو إنشاء جديد
                    finalUserId = queryParams.guestId || this.generateGuestId();
                    userCategory = 'guest';
                    console.log(`👤 عميل ضيف صريح: ${finalUserId}`);
                }
                
                // د) إذا لم يتم توفير أي معرف، إنشاء معرف ضيف جديد فقط إذا لم يكن هناك محاولة تسجيل
                if (!finalUserId) {
                    // 🔒 CRITICAL FIX: لا تنشئ ضيف تلقائياً إذا كان هناك token فاشل
                    if (token) {
                        console.error(`❌ رفض الاتصال: JWT موجود لكن فشل التحقق ولا يوجد fallback`);
                        throw new Error('JWT token provided but failed verification');
                    }
                    finalUserId = this.generateGuestId();
                    userCategory = 'guest';
                    console.log(`👤 عميل ضيف جديد: ${finalUserId}`);
                }
            }
            
            // 4. إذا لم يتم تحديد معرف حتى الآن، فشل الاتصال
            if (!finalUserId) {
                throw new Error(`لا يمكن تحديد معرف المستخدم لنوع الكيان: ${finalEntityType}`);
            }

            console.log(`✅ تم تحديد المستخدم: ${finalUserId} (${userCategory})`);

            const connectionsSchema = await this.getConnectionsSchema();

            // 🔒 فحص: هل يوجد اتصال نشط بنفس connectionId؟
            const existingConn = await this.dynamoDB.send(new GetCommand({
                TableName: this.connectionsTable,
                Key: connectionsSchema.keyType === 'connectionId'
                    ? { connectionId }
                    : { PK: `CONNECTION#${connectionId}`, SK: `CONNECTION#${connectionId}` }
            }));

            if (existingConn.Item) {
                const existing = existingConn.Item;
                // إذا كان الاتصال موجود ونشط ولنفس المستخدم، تجاهل هذا الطلب
                if (existing.isActive && existing.userId === finalUserId) {
                    console.log(`⏭️ اتصال نشط موجود بالفعل لـ ${finalUserId} - تجاهل`);
                    return { statusCode: 200, body: 'Already connected' };
                }
                // إذا كان موجود لكن لمستخدم مختلف، ارفض الطلب الجديد
                if (existing.isActive && existing.userId !== finalUserId) {
                    console.warn(`⚠️ محاولة استبدال connectionId ${connectionId} من ${existing.userId} إلى ${finalUserId} - مرفوض!`);
                    return { statusCode: 409, body: 'Connection ID already in use by another user' };
                }
            }

            // البحث عن اتصالات موجودة لنفس المستخدم
            await this.disconnectExistingConnections(finalUserId, finalEntityType, connectionId);

            // إنشاء سجل الاتصال الجديد
            const connectionData = await this.createConnectionRecord(
                connectionId, 
                finalUserId, 
                finalEntityType, 
                queryParams, 
                verified
            );

            // حفظ الاتصال في قاعدة البيانات
            await this.dynamoDB.send(new PutCommand({
                TableName: this.connectionsTable,
                Item: connectionData
            }));

            console.log(`✅ تم حفظ الاتصال: ${connectionId} للمستخدم: ${finalUserId}`);
            
            // ✨ إذا كان سائق، حدّث WizzDriverLiveState
            if (finalEntityType === 'driver' && finalUserId) {
                try {
                    await this.updateDriverLiveState(finalUserId, connectionId);
                    console.log(`✅ تم تحديث WizzDriverLiveState للسائق: ${finalUserId}`);
                } catch (driverError) {
                    console.error(`⚠️ فشل تحديث WizzDriverLiveState للسائق ${finalUserId}:`, driverError);
                    // لا نوقف الاتصال إذا فشل تحديث LiveState
                }
            }
            
            // 🧹 حذف الاشتراكات القديمة لنفس connectionId (إن وجدت)
            await this.cleanupOldSubscriptions(connectionId);
            
            // إنشاء الاشتراكات الافتراضية (Default Subscriptions)
            await this.createDefaultSubscriptions(
                connectionId,
                finalUserId,
                connectionData.role || connectionData.userType || finalEntityType,
                connectionData.entityId || finalUserId,
                connectionData.sessionId,
                connectionData.isGuest
            );
            
            return { statusCode: 200, body: 'Connected successfully' };

        } catch (error) {
            console.error('❌ خطأ في إنشاء الاتصال:', error);
            return { statusCode: 500, body: 'Connection failed' };
        }
    }

    /**
     * تحديث حالة الاتصال إلى منقطع بدلاً من الحذف
     */
    async handleDisconnect(connectionId) {
        try {
            console.log(`🔌 قطع الاتصال: ${connectionId}`);

            const connectionsSchema = await this.getConnectionsSchema();

            // تحديث حالة الاتصال
            await this.dynamoDB.send(new UpdateCommand({
                TableName: this.connectionsTable,
                Key: connectionsSchema.keyType === 'connectionId'
                    ? { connectionId }
                    : { PK: `CONNECTION#${connectionId}`, SK: `CONNECTION#${connectionId}` },
                UpdateExpression: 'SET #status = :status, #isActive = :isActive, #disconnectedAt = :disconnectedAt, #lastSeen = :lastSeen',
                ExpressionAttributeNames: {
                    '#status': 'status',
                    '#isActive': 'isActive',
                    '#disconnectedAt': 'disconnectedAt',
                    '#lastSeen': 'lastSeen'
                },
                ExpressionAttributeValues: {
                    ':status': 'disconnected',
                    ':isActive': false,
                    ':disconnectedAt': new Date().toISOString(),
                    ':lastSeen': new Date().toISOString()
                },
                ConditionExpression: 'attribute_exists(connectionId)'
            }));

            console.log(`✅ تم تحديث حالة الاتصال إلى منقطع: ${connectionId}`);
            return { statusCode: 200, body: 'Disconnected successfully' };

        } catch (error) {
            if (error.name === 'ConditionalCheckFailedException') {
                console.log(`ℹ️ الاتصال غير موجود: ${connectionId}`);
                return { statusCode: 200, body: 'Already disconnected' };
            }
            
            console.error('❌ خطأ في قطع الاتصال:', error);
            return { statusCode: 500, body: 'Disconnect failed' };
        }
    }

    /**
     * إنشاء سجل اتصال كامل المعلومات
     */
    async createConnectionRecord(connectionId, userId, entityType, queryParams, verified) {
        const now = new Date().toISOString();
        const connectionsSchema = await this.getConnectionsSchema();
        
        // 🔧 إصلاح: تحديد إذا كان المستخدم ضيف بشكل أكثر دقة
        // ضيف إذا:
        // 1. لا يوجد verified token أو لا يوجد sub في الـ token
        // 2. أو userId يبدأ بـ GUEST# أو guest-
        // مسجل إذا:
        // 1. يوجد verified token و sub
        // 2. أو userId يبدأ بـ user_
        const isGuest = (!verified || !verified.sub) && 
                       !userId.startsWith('user_') &&
                       (userId.startsWith('GUEST#') || userId.startsWith('guest-') || queryParams.userType === 'guest');
        
        // ✅ FIXED: Determine authenticated status based on JWT verification
        // authenticated = true if:
        // 1. JWT token exists and was verified successfully
        // 2. User is NOT a guest
        const isAuthenticated = !!(verified && verified.sub && !isGuest);
        
        // TTL مختلف للضيوف (2 ساعات) والمسجلين (24 ساعة)
        const ttlSeconds = isGuest ? 7200 : 86400;
        const ttl = Math.floor(Date.now() / 1000) + ttlSeconds;

        // استخراج معلومات إضافية من queryParams
        const {
            businessId,
            merchantId,
            driverId,
            sessionId,
            guestId,
            orderId,
            platform = 'unknown',
            appVersion = '1.0.0',  // ✅ FIXED: Always include appVersion with default
            deviceId,
            userType
        } = queryParams;

        // تحديد الدور (role) حسب نوع الكيان
        let role = 'customer'; // القيمة الافتراضية
        if (entityType === 'business' || entityType === 'merchant') {
            role = 'merchant';
        } else if (entityType === 'driver') {
            role = 'driver';
        } else if (entityType === 'guest') {
            // الضيف هو مستخدم (customer) لكن بدون تسجيل دخول
            role = 'customer';  // ✅ الدور الصحيح
        } else if (verified && verified['cognito:groups']) {
            role = verified['cognito:groups'][0] || 'customer';
        }

        // تحديد entityId حسب نوع الكيان
        let entityId = userId;
        if (entityType === 'business' || entityType === 'merchant') {
            entityId = businessId || merchantId || userId;
        } else if (entityType === 'driver') {
            entityId = (!this.isInvalidId(driverId) ? driverId : userId);
        }

        // بناء سجل الاتصال الكامل
        const connectionData = {
            // Primary Key
            ...(connectionsSchema.keyType === 'connectionId'
                ? { connectionId }
                : { PK: `CONNECTION#${connectionId}`, SK: `CONNECTION#${connectionId}`, connectionId }),
            
            // معلومات الاتصال الأساسية
            userId,
            entityType,
            entityId,
            role,
            
            // ✅ FIXED: Always include these important fields
            authenticated: isAuthenticated,  // Based on JWT verification
            appVersion,  // Always include, with default value
            userType: userType || role,  // Always include userType
            
            // حالة الاتصال
            isActive: true,
            // Keep status aligned with dev semantics so stream processors/queries don't miss active connections
            status: 'active',
            connectionType: 'REAL',
            
            // معلومات الضيف
            isGuest,
            sessionId: isGuest ? (sessionId || `session_${Date.now()}`) : undefined,
            guestId: isGuest ? (guestId || userId) : undefined,
            
            // معلومات التاجر/السائق
            businessId: (entityType === 'business' || entityType === 'merchant') ? (businessId || merchantId) : undefined,
            driverId: (entityType === 'driver') ? (!this.isInvalidId(driverId) ? driverId : userId) : undefined,
            
            // معلومات الطلب (إن وجدت)
            orderId: orderId || undefined,
            
            // معلومات الجهاز
            platform,
            deviceId: deviceId || `${platform}_${entityId}_${Date.now()}`,
            
            // التوقيتات
            connectedAt: now,
            lastActivity: now,
            lastHeartbeat: now,
            lastSeen: now,
            ttl,
            
            // GSI للبحث السريع
            GSI1PK: this.buildGSI1PK(entityType, entityId),
            GSI1SK: `CONNECTION#${connectionId}`,
            
            // معلومات JWT (إن وجدت)
            cognitoSub: verified?.sub,
            cognitoGroups: verified?.['cognito:groups'],
            
            // مصدر الاتصال
            source: `${entityType}_app`
        };

        // إزالة الحقول undefined
        Object.keys(connectionData).forEach(key => {
            if (connectionData[key] === undefined) {
                delete connectionData[key];
            }
        });

        return connectionData;
    }

    /**
     * بناء GSI1PK حسب نوع الكيان
     */
    buildGSI1PK(entityType, entityId) {
        if (entityType === 'business' || entityType === 'merchant') {
            return `BUSINESS#${entityId}`;
        } else if (entityType === 'driver') {
            return `DRIVER#${entityId}`;
        } else if (entityType === 'guest') {
            return `GUEST#${entityId}`;
        } else {
            return `USER#${entityId}`;
        }
    }

    /**
     * الحصول على GSI key للبحث
     */
    getGSIKey(entityType, userId) {
        return this.buildGSI1PK(entityType, userId);
    }

    /**
     * قطع الاتصالات الموجودة لنفس المستخدم
     */
    async disconnectExistingConnections(userId, entityType, currentConnectionId) {
        try {
            console.log(`🔍 البحث عن اتصالات موجودة للمستخدم: ${userId}`);

            const connectionsSchema = await this.getConnectionsSchema();

            let connections = [];

            try {
                // Prefer staging-friendly index if present
                if (connectionsSchema.userIndexName === 'userId-connectedAt-index') {
                    const existingConnections = await this.dynamoDB.send(new QueryCommand({
                        TableName: this.connectionsTable,
                        IndexName: 'userId-connectedAt-index',
                        KeyConditionExpression: 'userId = :userId',
                        FilterExpression: '(#status = :connected OR #status = :active) AND #isActive = :isActive',
                        ExpressionAttributeNames: {
                            '#status': 'status',
                            '#isActive': 'isActive'
                        },
                        ExpressionAttributeValues: {
                            ':userId': userId,
                            ':connected': 'connected',
                            ':active': 'active',
                            ':isActive': true
                        }
                    }));
                    connections = existingConnections.Items || [];
                } else if (connectionsSchema.userIndexName === 'GSI1') {
                    // Legacy behavior using GSI1PK
                    const gsiKey = this.getGSIKey(entityType, userId);
                    const existingConnections = await this.dynamoDB.send(new QueryCommand({
                        TableName: this.connectionsTable,
                        IndexName: 'GSI1',
                        KeyConditionExpression: 'GSI1PK = :gsiPK',
                        FilterExpression: '(#status = :connected OR #status = :active) AND #isActive = :isActive',
                        ExpressionAttributeNames: {
                            '#status': 'status',
                            '#isActive': 'isActive'
                        },
                        ExpressionAttributeValues: {
                            ':gsiPK': gsiKey,
                            ':connected': 'connected',
                            ':active': 'active',
                            ':isActive': true
                        }
                    }));
                    connections = existingConnections.Items || [];
                } else {
                    throw new Error('No usable user index configured');
                }
            } catch (indexError) {
                console.warn('⚠️ User-index query failed; falling back to scan:', indexError?.message || indexError);
                // Fallback: scan by userId
                const existingConnections = await this.dynamoDB.send(new ScanCommand({
                    TableName: this.connectionsTable,
                    FilterExpression: 'userId = :userId AND (#status = :connected OR #status = :active) AND #isActive = :isActive',
                    ExpressionAttributeNames: {
                        '#status': 'status',
                        '#isActive': 'isActive'
                    },
                    ExpressionAttributeValues: {
                        ':userId': userId,
                        ':connected': 'connected',
                        ':active': 'active',
                        ':isActive': true
                    }
                }));
                connections = existingConnections.Items || [];
            }
            console.log(`📊 وجدت ${connections.length} اتصالات نشطة للمستخدم: ${userId}`);

            // قطع الاتصالات القديمة
            for (const conn of connections) {
                if (conn.connectionId !== currentConnectionId) {
                    await this.dynamoDB.send(new UpdateCommand({
                        TableName: this.connectionsTable,
                        Key: connectionsSchema.keyType === 'connectionId'
                            ? { connectionId: conn.connectionId }
                            : { PK: conn.PK || `CONNECTION#${conn.connectionId}`, SK: conn.SK || `CONNECTION#${conn.connectionId}` },
                        UpdateExpression: 'SET #status = :status, #isActive = :isActive, #disconnectedAt = :disconnectedAt',
                        ExpressionAttributeNames: {
                            '#status': 'status',
                            '#isActive': 'isActive',
                            '#disconnectedAt': 'disconnectedAt'
                        },
                        ExpressionAttributeValues: {
                            ':status': 'disconnected',
                            ':isActive': false,
                            ':disconnectedAt': new Date().toISOString()
                        }
                    }));
                    
                    console.log(`🔌 تم قطع الاتصال القديم: ${conn.connectionId}`);
                }
            }

        } catch (error) {
            console.error('❌ خطأ في قطع الاتصالات الموجودة:', error);
        }
    }

    /**
     * تنظيف السجلات القديمة
     */
    async cleanupOldRecords() {
        try {
            const cutoffTime = new Date(Date.now() - (48 * 60 * 60 * 1000)); // 48 ساعة
            const cutoffISO = cutoffTime.toISOString();

            console.log(`🧹 تنظيف السجلات المنقطعة الأقدم من: ${cutoffISO}`);

            // البحث عن السجلات القديمة
            const oldRecords = await this.dynamoDB.send(new ScanCommand({
                TableName: this.connectionsTable,
                FilterExpression: '#status = :status AND #disconnectedAt < :cutoff',
                ExpressionAttributeNames: {
                    '#status': 'status',
                    '#disconnectedAt': 'disconnectedAt'
                },
                ExpressionAttributeValues: {
                    ':status': 'disconnected',
                    ':cutoff': cutoffISO
                }
            }));

            const recordsToDelete = oldRecords.Items || [];
            console.log(`🗑️ وجدت ${recordsToDelete.length} سجل قديم للحذف`);

            const connectionsSchema = await this.getConnectionsSchema();

            // حذف السجلات القديمة
            for (const record of recordsToDelete) {
                await this.dynamoDB.send(new DeleteCommand({
                    TableName: this.connectionsTable,
                    Key: connectionsSchema.keyType === 'connectionId'
                        ? { connectionId: record.connectionId }
                        : { PK: record.PK || `CONNECTION#${record.connectionId}`, SK: record.SK || `CONNECTION#${record.connectionId}` }
                }));
                
                console.log(`🗑️ تم حذف السجل القديم: ${record.connectionId}`);
            }

            return { cleaned: recordsToDelete.length };

        } catch (error) {
            console.error('❌ خطأ في تنظيف السجلات القديمة:', error);
            return { error: error.message };
        }
    }

    // دوال مساعدة
    determineEntityType(userType, entityType, queryParams) {
        if (entityType) return entityType;
        if (userType === 'driver') return 'driver';
        if (userType === 'business' || userType === 'merchant') return 'business';
        if (userType === 'customer' || userType === 'user') return 'customer';
        if (queryParams.businessId) return 'business';
        if (queryParams.driverId) return 'driver';
        return 'customer'; // default
    }

    determineSource(entityType, queryParams) {
        const sourceMap = {
            driver: 'driver_app',
            business: 'business_app',
            merchant: 'business_app',
            customer: 'customer_app',
            user: 'customer_app'
        };
        return sourceMap[entityType] || 'unknown_app';
    }

    getGSIKey(entityType, userId) {
        const keyMap = {
            driver: `DRIVER#${userId}`,
            business: `BUSINESS#${userId}`,
            merchant: `BUSINESS#${userId}`,
            customer: `USER#${userId}`,
            user: `USER#${userId}`
        };
        return keyMap[entityType] || `USER#${userId}`;
    }

    async verifyJwt(token) {
        try {
            // للاختبار: استخراج البيانات من JWT بسيط
            if (token && token.startsWith('eyJ')) {
                const parts = token.split('.');
                if (parts.length >= 2) {
                    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
                    return payload;
                }
            }
            // في الإنتاج: استخدم AWS Cognito أو مكتبة JWT حقيقية
            return null;
        } catch (error) {
            console.warn('فشل في التحقق من JWT:', error.message);
            return null;
        }
    }

    /**
     * تحديث Heartbeat للاتصال
     */
    async updateHeartbeat(connectionId) {
        try {
            const connectionsSchema = await this.getConnectionsSchema();
            await this.dynamoDB.send(new UpdateCommand({
                TableName: this.connectionsTable,
                Key: connectionsSchema.keyType === 'connectionId'
                    ? { connectionId }
                    : { PK: `CONNECTION#${connectionId}`, SK: `CONNECTION#${connectionId}` },
                UpdateExpression: 'SET #lastHeartbeat = :now, #lastActivity = :now, #lastSeen = :now',
                ExpressionAttributeNames: {
                    '#lastHeartbeat': 'lastHeartbeat',
                    '#lastActivity': 'lastActivity',
                    '#lastSeen': 'lastSeen'
                },
                ExpressionAttributeValues: {
                    ':now': new Date().toISOString()
                },
                ConditionExpression: 'attribute_exists(connectionId)'
            }));

            return { statusCode: 200, body: 'Heartbeat updated' };
        } catch (error) {
            console.error('❌ خطأ في تحديث Heartbeat:', error);
            return { statusCode: 500, body: 'Heartbeat update failed' };
        }
    }

    /**
     * الحصول على إحصائيات الاتصالات
     */
    async getConnectionStats() {
        try {
            const result = await this.dynamoDB.send(new ScanCommand({
                TableName: this.connectionsTable,
                ProjectionExpression: '#status, entityType, connectedAt, disconnectedAt',
                ExpressionAttributeNames: {
                    '#status': 'status'
                }
            }));

            const connections = result.Items || [];
            const stats = {
                total: connections.length,
                connected: connections.filter(c => c.status === 'connected').length,
                disconnected: connections.filter(c => c.status === 'disconnected').length,
                byEntityType: {
                    driver: connections.filter(c => c.entityType === 'driver').length,
                    business: connections.filter(c => c.entityType === 'business').length,
                    customer: connections.filter(c => c.entityType === 'customer').length
                }
            };

            return stats;
        } catch (error) {
            console.error('❌ خطأ في جلب إحصائيات الاتصالات:', error);
            return null;
        }
    }

    /**
     * توليد معرف ضيف فريد
     */
    generateGuestId() {
        const timestamp = Date.now();
        const randomId = Math.random().toString(36).substring(2, 15);
        return `GUEST#${timestamp}_${randomId}`;
    }

    /**
     * توليد معرف جلسة فريد
     */
    generateSessionId() {
        const randomId = Math.random().toString(36).substring(2, 15);
        return `SESSION#${randomId}`;
    }

    /**
     * الحصول على Topics الافتراضية حسب الدور
     */
    getDefaultTopics(role, userId, entityId, sessionId) {
        const topics = [];

        switch(role) {
            case 'guest':
                // الضيوف لديهم اشتراكات محدودة
                if (userId) topics.push(`guest:${userId}`);
                if (sessionId) topics.push(`session:${sessionId}`);
                topics.push('broadcast:all');
                break;

            case 'customer':
                // العملاء المسجلين
                topics.push(`user:${userId}`);
                topics.push('broadcast:all');
                topics.push('broadcast:customers');
                break;

            case 'merchant':
            case 'business':
                // التجار
                topics.push(`business:${entityId}`);
                topics.push(`user:${userId}`);
                topics.push('broadcast:all');
                topics.push('broadcast:merchants');
                break;

            case 'driver':
                // السائقين
                topics.push(`driver:${entityId}`);
                topics.push(`user:${userId}`);
                topics.push('broadcast:all');
                topics.push('broadcast:drivers');
                break;

            case 'admin':
                // المسؤولين
                topics.push('admin:system');
                topics.push('broadcast:all');
                topics.push('broadcast:admins');
                break;

            default:
                // افتراضي للعملاء
                topics.push(`user:${userId}`);
                topics.push('broadcast:all');
        }

        return topics;
    }

    /**
     * 🧹 حذف الاشتراكات القديمة لنفس connectionId
     * يستخدم عند إعادة الاتصال بنفس connectionId (مثل التحديث من guest إلى registered)
     */
    async cleanupOldSubscriptions(connectionId) {
        try {
            console.log(`🧹 فحص الاشتراكات القديمة لـ: ${connectionId}`);

            // البحث عن جميع الاشتراكات لهذا الاتصال باستخدام Scan
            // (لأننا لا نعرف إذا كان يوجد GSI على connectionId)
            const { Items: oldSubscriptions = [] } = await this.dynamoDB.send(new ScanCommand({
                TableName: this.subscriptionsTable,
                FilterExpression: 'connectionId = :connId',
                ExpressionAttributeValues: {
                    ':connId': connectionId
                }
            }));

            if (oldSubscriptions.length === 0) {
                console.log(`ℹ️ لا توجد اشتراكات قديمة لـ: ${connectionId}`);
                return;
            }

            console.log(`🔍 تم العثور على ${oldSubscriptions.length} اشتراك قديم`);

            // حذف الاشتراكات القديمة
            const deletePromises = oldSubscriptions.map(sub => 
                this.dynamoDB.send(new DeleteCommand({
                    TableName: this.subscriptionsTable,
                    Key: {
                        subscriptionId: sub.subscriptionId
                    }
                }))
            );

            await Promise.all(deletePromises);
            console.log(`✅ تم حذف ${oldSubscriptions.length} اشتراك قديم لـ: ${connectionId}`);

        } catch (error) {
            // إذا فشل الحذف، نستمر (لن نوقف الاتصال بسبب فشل التنظيف)
            console.warn(`⚠️ خطأ في حذف الاشتراكات القديمة:`, error.message);
        }
    }

    /**
     * إنشاء الاشتراكات الافتراضية
     */
    async createDefaultSubscriptions(connectionId, userId, role, entityId, sessionId, isGuest = false) {
        try {
            console.log(`📋 إنشاء اشتراكات افتراضية: ${connectionId}`, { role, userId, entityId, isGuest });

            const topics = this.getDefaultTopics(role, userId, entityId, sessionId);
            const now = Date.now();
            
            // TTL مختلف للضيوف (2 ساعات) والمسجلين (24 ساعة)
            const ttlHours = isGuest ? 2 : 24;
            const expiresAt = now + (ttlHours * 60 * 60 * 1000);

            const subscriptions = topics.map(topic => ({
                subscriptionId: `${connectionId}_${topic}`, // Primary key
                topic,
                connectionId,
                userId,
                role,
                subscribedAt: now,
                expiresAt,
                ttl: Math.floor(expiresAt / 1000), // TTL بالثواني
                metadata: {
                    autoSubscribed: true,
                    subscriptionType: 'default',
                    isGuest: isGuest
                }
            }));

            // حفظ الاشتراكات
            await this.batchWriteSubscriptions(subscriptions);

            console.log(`✅ تم إنشاء ${subscriptions.length} اشتراكات افتراضية لـ ${connectionId}`);
            return subscriptions;

        } catch (error) {
            console.error('❌ خطأ في إنشاء الاشتراكات الافتراضية:', error);
            throw error;
        }
    }

    /**
     * كتابة الاشتراكات دفعة واحدة (Batch Write)
     */
    async batchWriteSubscriptions(subscriptions) {
        if (!subscriptions || subscriptions.length === 0) {
            return;
        }

        try {
            // DynamoDB BatchWrite يقبل 25 عنصر كحد أقصى
            const batchSize = 25;
            
            for (let i = 0; i < subscriptions.length; i += batchSize) {
                const batch = subscriptions.slice(i, i + batchSize);
                
                const putRequests = batch.map(sub => ({
                    PutRequest: { Item: sub }
                }));

                await this.dynamoDB.send(new BatchWriteCommand({
                    RequestItems: {
                        [this.subscriptionsTable]: putRequests
                    }
                }));
            }

            console.log(`✅ تم حفظ ${subscriptions.length} اشتراك في الدفعة`);

        } catch (error) {
            console.error('❌ خطأ في Batch Write للاشتراكات:', error);
            
            // إعادة المحاولة واحداً تلو الآخر في حالة الفشل
            for (const subscription of subscriptions) {
                try {
                    await this.dynamoDB.send(new PutCommand({
                        TableName: this.subscriptionsTable,
                        Item: subscription
                    }));
                } catch (err) {
                    console.error(`❌ فشل حفظ اشتراك: ${subscription.PK}`, err.message);
                }
            }
        }
    }

    /**
     * تحديث WizzDriverLiveState عند اتصال السائق
     */
    async updateDriverLiveState(driverId, connectionId) {
        try {
            console.log(`🔄 تحديث WizzDriverLiveState للسائق: ${driverId}`);
            
            const now = new Date().toISOString();

            const envName = this.getEnvironmentName();
            const liveStateTable =
                process.env.DRIVER_LIVE_STATE_TABLE ||
                `WizzDriverLiveState_${envName}`;
            
            // تحديث WizzDriverLiveState - فقط connectionId و lastConnected
            // البيانات الكاملة تأتي من REST API /driver/start-searching
            await this.dynamoDB.send(new UpdateCommand({
                TableName: liveStateTable,
                Key: { 
                    driverId: driverId
                },
                UpdateExpression: `
                    SET connectionId = :connId,
                        connectionStatus = :connStatus,
                        isActive = :active,
                        lastConnected = :now,
                        lastUpdated = :now,
                        #status = if_not_exists(#status, :defaultStatus)
                `,
                ExpressionAttributeNames: {
                    '#status': 'status'
                },
                ExpressionAttributeValues: {
                    ':connId': connectionId,
                    ':connStatus': 'connected',
                    ':defaultStatus': 'offline',
                    ':active': true,
                    ':now': now
                }
            }));
            
            console.log(`✅ تم تحديث ${liveStateTable} للسائق ${driverId} بـ connectionId: ${connectionId}`);
            
        } catch (error) {
            console.error(`❌ خطأ في تحديث WizzDriverLiveState للسائق ${driverId}:`, error);
            throw error;
        }
    }
}

module.exports = { UniversalWebSocketManager };