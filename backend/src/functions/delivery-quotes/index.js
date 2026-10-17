'use strict';
const { accountGuard } = require('../create-order/account-guard');
const { createStagingDeliveryQuoteRateLimiter, createStagingDeliveryQuotes, createStagingSecretDeliveryRouting, DynamoDBClient,
  createFinanceRollout, DynamoDBDocumentClient, GetCommand, SecretsManagerClient, CognitoIdentityProviderClient, GetUserCommand, readDeliveryOperations } = require('./runtime');
const cognito = new CognitoIdentityProviderClient({});
const db = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
const secrets = new SecretsManagerClient({});
const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Customer-Id',
  'Access-Control-Expose-Headers': 'Retry-After',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' };
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });
exports.handler = async event => {
  if (event.httpMethod === 'OPTIONS') return reply(204, {});
  try {
    const env = process.env;
    if (env.DELIVERY_QUOTES_ENABLED !== 'true') return reply(503, { success: false, code: 'QUOTES_NOT_ENABLED' });
    if (env.AWS_REGION !== 'us-east-1' || env.ENVIRONMENT !== 'staging' ||
        env.USERS_TABLE !== 'WizzUser_users_staging' || env.USER_POOL_ID !== 'us-east-1_TpyyrVkEE' ||
        !env.USER_POOL_CLIENT_ID || !/^(?:[1-9]|[1-9][0-9]|1[01][0-9]|120)$/.test(env.DELIVERY_QUOTE_MAX_PER_MINUTE || '') || !env.MAPBOX_SECRET_ARN?.startsWith('arn:aws:secretsmanager:us-east-1:699561669180:secret:'))
      return reply(503, { success: false, code: 'QUOTES_NOT_CONFIGURED' });
    if (!['GET', 'POST'].includes(event.httpMethod)) return reply(405, { success: false, code: 'METHOD_NOT_ALLOWED' });
    // This header selects a profile, never authorizes it. GetUser + accountGuard bind it to the live subject.
    const selected = Object.entries(event.headers || {}).find(([k]) => k.toLowerCase() === 'x-customer-id')?.[1];
    if (typeof selected !== 'string' || !/^[A-Za-z0-9_.:-]{1,150}$/.test(selected) || selected === 'guest')
      return reply(401, { success: false, code: 'AUTH_REQUIRED' });
    const authenticateCustomer = async () => {
      const guarded = await accountGuard({ event, userId: selected, profilesTable: env.USERS_TABLE,
        pool: env.USER_POOL_ID, clientId: env.USER_POOL_CLIENT_ID,
        getUser: token => cognito.send(new GetUserCommand({ AccessToken: token })),
        getProfile: async userId => (await db.send(new GetCommand({ TableName: env.USERS_TABLE, Key: { userId }, ConsistentRead: true }))).Item });
      return { userId: selected, subjectId: guarded.sub, condition: guarded.condition };
    };
    await authenticateCustomer();
    const rollout=createFinanceRollout({db});
    const service = createStagingDeliveryQuotes({ db:rollout.db, authenticateCustomer, beforeCalculate: async (c,selection) => {
      rollout.admit(selection.branchId,c.subjectId);
      const operating=await readDeliveryOperations(db,env);
      await createStagingDeliveryQuoteRateLimiter({db,maxPerMinute:operating.values.quoteMaxPerCustomerPerMinute,policyCondition:operating.condition}).reserve(c);
    },
      createRouter: guardedDb => createStagingSecretDeliveryRouting({ db: guardedDb, secrets,
        secretArn: env.MAPBOX_SECRET_ARN, profile: 'driving', ttlSeconds: 120, timeoutMs: 8000, credentialTimeoutMs: 2000 }) });
    let quote;
    if (event.httpMethod === 'POST') {
      if (event.isBase64Encoded || typeof event.body !== 'string' || Buffer.byteLength(event.body) > 2048 ||
          Object.keys(event.queryStringParameters || {}).length) return reply(400, { success: false, code: 'INVALID_QUOTE_REQUEST' });
      let input; try { input = JSON.parse(event.body); } catch { return reply(400, { success: false, code: 'INVALID_QUOTE_REQUEST' }); }
      quote = await service.create(input);
    } else {
      const query = event.queryStringParameters || {};
      if (Object.keys(query).join(',') !== 'quoteId') return reply(400, { success: false, code: 'INVALID_QUOTE_REQUEST' });
      quote = await service.get(query);
    }
    return reply(200, { success: true, quote });
  } catch (error) {
    const code = error.code;
    if (code === 'QUOTE_RATE_LIMITED') {
      const seconds = Number.isInteger(error.retryAfterSeconds) && error.retryAfterSeconds >= 1 && error.retryAfterSeconds <= 60 ? error.retryAfterSeconds : 60;
      return { ...reply(429, { success: false, code, retryAfterSeconds: seconds }), headers: { ...headers, 'Retry-After': String(seconds) } };
    }
    const status = { FINANCE_ROLLOUT_OUT_OF_SCOPE:403, FINANCE_ROLLOUT_ADMISSION_CLOSED:403, FINANCE_ROLLOUT_NOT_CONFIGURED:503, AUTH_REQUIRED: 401, ACCOUNT_MISMATCH: 403, ACCOUNT_UNAVAILABLE: error.statusCode || 409,
      INVALID_QUOTE_REQUEST: 400, QUOTE_EXPIRED: 409, QUOTE_INVALIDATED: 409, QUOTE_CONSUMED: 409,
      QUOTE_REQUEST_CONFLICT: 409, QUOTE_UNAVAILABLE: 404, CUSTOMER_UNAVAILABLE: 403 }[code];
    return reply(status || 503, { success: false, code: status ? code : 'QUOTE_SERVICE_UNAVAILABLE' });
  }
};
