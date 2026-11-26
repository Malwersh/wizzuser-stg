'use strict';

const { accountGuard } = require('../functions/create-order/account-guard');
const runtime = require('../functions/delivery-quotes/runtime');

const path = '/delivery-quotes';
const customerPool = 'us-east-1_rNtNKVsVf';
const customerClient = '3e8p0ouglrprpd0a3pc91du0hg';
const customersTable = 'wizz-production-Customers';
const routingSecret = /^arn:aws:secretsmanager:us-east-1:746727375268:secret:production\/finance\/mapbox\/server-routing-[A-Za-z0-9]{6}$/;
const headers = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization,Content-Type,X-Customer-Id',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Expose-Headers': 'Retry-After',
};
const reply = (statusCode, body, extra = {}) => ({
  statusCode, headers: { ...headers, ...extra }, body: JSON.stringify(body),
});
const failure = (status, code) => reply(status, { success: false, code });

function requestValue(event) {
  const query = event.queryStringParameters || {};
  if (event.httpMethod === 'GET') {
    return Object.keys(query).join(',') === 'quoteId' &&
      (event.multiValueQueryStringParameters?.quoteId?.length ?? 1) === 1 ? query : undefined;
  }
  if (event.isBase64Encoded || typeof event.body !== 'string' ||
      Buffer.byteLength(event.body) > 2048 || Object.keys(query).length) return undefined;
  try {
    const body = JSON.parse(event.body);
    return body && typeof body === 'object' && !Array.isArray(body) ? body : undefined;
  } catch {
    return undefined;
  }
}

function configured(env) {
  return env.ENVIRONMENT === 'production' && env.AWS_REGION === 'us-east-1' &&
    [env.PLATFORM_ENVIRONMENT, env.STAGE].every(value => !value || value === 'production') &&
    env.USERS_TABLE === customersTable && env.USER_POOL_ID === customerPool &&
    env.USER_POOL_CLIENT_ID === customerClient && routingSecret.test(env.MAPBOX_SECRET_ARN) &&
    /^[1-9]\d{0,2}$/.test(env.DELIVERY_QUOTE_MAX_PER_MINUTE) &&
    Number(env.DELIVERY_QUOTE_MAX_PER_MINUTE) <= 120;
}

function quoteFailure(error) {
  if (error.code === 'QUOTE_RATE_LIMITED') {
    const seconds = Number.isInteger(error.retryAfterSeconds) &&
      error.retryAfterSeconds >= 1 && error.retryAfterSeconds <= 60 ? error.retryAfterSeconds : 60;
    return reply(429, { success: false, code: error.code, retryAfterSeconds: seconds }, { 'Retry-After': String(seconds) });
  }
  const statuses = {
    ACCOUNT_MISMATCH: 403, ACCOUNT_UNAVAILABLE: error.statusCode === 409 ? 409 : 403,
    AUTH_REQUIRED: 401, CUSTOMER_UNAVAILABLE: 403, INVALID_QUOTE_REQUEST: 400,
    ADDRESS_UNAVAILABLE: 404, BRANCH_UNAVAILABLE: 404, OUTSIDE_COVERAGE: 422,
    QUOTE_EXPIRED: 409, QUOTE_CONSUMED: 409, QUOTE_INVALIDATED: 409, QUOTE_REQUEST_CONFLICT: 409,
    QUOTE_UNAVAILABLE: 404, PRICING_UNAVAILABLE: 503,
  };
  const status = Object.hasOwn(statuses, error.code) ? statuses[error.code] : undefined;
  return status ? failure(status, error.code) : failure(503, 'QUOTE_SERVICE_UNAVAILABLE');
}

function createHandler({ db, cognito, secrets, env = process.env, services = runtime }) {
  return async event => {
    if (event?.requestContext?.stage !== 'production' || event.resource !== path) {
      return failure(404, 'NOT_FOUND');
    }
    if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
    if (!['GET', 'POST'].includes(event.httpMethod)) return failure(405, 'METHOD_NOT_ALLOWED');
    if (!configured(env)) return failure(503, 'QUOTES_NOT_CONFIGURED');

    const entries = Object.entries(event.headers || {});
    const selected = entries.filter(([key]) => key.toLowerCase() === 'x-customer-id');
    const authorization = entries.filter(([key]) => key.toLowerCase() === 'authorization');
    const userId = selected[0]?.[1];
    if (selected.length !== 1 || authorization.length !== 1 ||
        typeof userId !== 'string' || !/^[A-Za-z0-9_.:-]{1,150}$/.test(userId) ||
        userId === 'guest' || typeof authorization[0][1] !== 'string') {
      return failure(401, 'AUTH_REQUIRED');
    }
    try {
      const authenticateCustomer = async () => {
        const guarded = await accountGuard({
          event: { headers: { Authorization: authorization[0][1] } },
          userId, profilesTable: env.USERS_TABLE,
          pool: env.USER_POOL_ID, clientId: env.USER_POOL_CLIENT_ID,
          getUser: token => cognito.send(new services.GetUserCommand({ AccessToken: token })),
          getProfile: async id => (await db.send(new services.GetCommand({
            TableName: env.USERS_TABLE, Key: { userId: id }, ConsistentRead: true,
          }))).Item,
        });
        return { userId, subjectId: guarded.sub, condition: guarded.condition };
      };
      await authenticateCustomer();
      const input = requestValue(event);
      if (!input) return failure(400, 'INVALID_QUOTE_REQUEST');
      const service = services.createStagingDeliveryQuotes({
        db, authenticateCustomer,
        beforeCalculate: async customer => {
          const operating = await services.readDeliveryOperations(db, env);
          await services.createStagingDeliveryQuoteRateLimiter({
            db, maxPerMinute: operating.values.quoteMaxPerCustomerPerMinute,
            policyCondition: operating.condition,
          }).reserve(customer);
        },
        createRouter: guardedDb => services.createStagingSecretDeliveryRouting({
          db: guardedDb, secrets, secretArn: env.MAPBOX_SECRET_ARN,
          profile: 'driving', ttlSeconds: 120, timeoutMs: 8000, credentialTimeoutMs: 2000,
        }),
      });
      const quote = event.httpMethod === 'POST' ? await service.create(input) : await service.get(input);
      return reply(200, { success: true, quote });
    } catch (error) {
      return quoteFailure(error);
    }
  };
}

const db = runtime.DynamoDBDocumentClient.from(new runtime.DynamoDBClient({ maxAttempts: 2 }), {
  marshallOptions: { removeUndefinedValues: true },
});
exports.handler = createHandler({
  db,
  cognito: new runtime.CognitoIdentityProviderClient({ maxAttempts: 2 }),
  secrets: new runtime.SecretsManagerClient({ maxAttempts: 2 }),
});
exports.createHandler = createHandler;
