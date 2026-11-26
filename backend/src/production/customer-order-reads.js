'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { CognitoIdentityProviderClient, GetUserCommand } = require('@aws-sdk/client-cognito-identity-provider');
const { accountGuard } = require('../functions/create-order/account-guard');
const { customerOrderView } = require('../functions/shared/customer-order-view');
const { customerStatusFilter, isTerminalOrderStatus } = require('../functions/shared/legacy-order-policy');

const listPath = '/users/{user_id}/orders';
const detailPath = '/orders/{orderId}';
const ordersTable = 'wizz-production-Orders';
const customersTable = 'wizz-production-Customers';
const driversTable = 'wizz-production-Drivers';
const pool = 'us-east-1_rNtNKVsVf';
const clientId = '3e8p0ouglrprpd0a3pc91du0hg';
const headers = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization,Content-Type',
  'Access-Control-Allow-Methods': 'GET,OPTIONS',
};
const id = value => typeof value === 'string' && /^[A-Za-z0-9_.:-]{1,150}$/.test(value);
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });
const fail = (status, code) => reply(status, { success: false, code });

const publicFields = [
  'orderId', 'orderNumber', 'userId', 'storeId', 'storeName', 'storeAddress',
  'items', 'pricing', 'status', 'returnStatus', 'paymentMethod', 'paymentStatus',
  'deliveryAddress', 'deliveryInstructions', 'customerPhone', 'customerName', 'customerEmail',
  'createdAt', 'updatedAt', 'confirmedAt', 'estimatedDeliveryTime', 'actualDeliveryTime',
  'deliveryEstimate', 'estimatedReadyAt', 'estimatedPreparationTime', 'cancelReason',
  'driverId', 'assignedDriverId', 'driverName', 'driverPhone', 'vehicleType', 'vehiclePlate',
  'driverSearchUnavailable', 'scheduledAt', 'merchantAcceptanceDeadlineAt',
];
function publicOrder(order) {
  const view = customerOrderView(order);
  const result = Object.fromEntries(publicFields.filter(key => view[key] !== undefined).map(key => [key, view[key]]));
  if (order.exceptionCancellation) {
    const { caseId, state } = order.exceptionCancellation;
    result.exceptionCancellation = { caseId, state };
  }
  if (order.financialRelease || order.driverReplacementSearch === true) result.driverReplacementSearch = true;
  return result;
}

function subject(event) {
  const bearer = Object.entries(event.headers || {}).filter(([k]) => k.toLowerCase() === 'authorization');
  if (bearer.length !== 1 || typeof bearer[0][1] !== 'string' || bearer[0][1].length > 8192) return null;
  const match = /^Bearer ([\w-]+\.([\w-]+)\.[\w-]+)$/.exec(bearer[0][1]);
  if (!match) return null;
  try {
    const { sub } = JSON.parse(Buffer.from(match[2], 'base64url').toString());
    return id(sub) && sub !== 'guest' ? { sub, token: match[1] } : null;
  } catch {
    return null;
  }
}

function createOrderReads({ db, cognito, env = process.env, now = Date.now }) {
  const get = async (TableName, Key, projection) => (await db.send(new GetCommand({
    TableName, Key, ConsistentRead: true, ...projection,
  }))).Item;
  const owned = (order, sub) => order?.userId === sub && order.userSub === sub &&
    order.isGuestOrder !== true && !order.deletionRequestId && !order.deletedAt && order.isDeleted !== true;
  return async event => {
    if (event?.requestContext?.stage !== 'production' || ![listPath, detailPath].includes(event.resource)) {
      return fail(404, 'NOT_FOUND');
    }
    if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
    if (event.httpMethod !== 'GET') return fail(405, 'METHOD_NOT_ALLOWED');
    if (env.ENVIRONMENT !== 'production' || env.AWS_REGION !== 'us-east-1' ||
        env.USER_POOL_ID !== pool || env.USER_POOL_CLIENT_ID !== clientId) {
      return fail(503, 'ORDER_READ_UNAVAILABLE');
    }
    const identity = subject(event);
    if (!identity) return fail(401, 'AUTH_REQUIRED');
    const list = event.resource === listPath;
    const orderId = event.pathParameters?.orderId;
    const query = event.queryStringParameters || {};
    if ((list && query.guestToken !== undefined) || (!list && !id(orderId))) return fail(400, 'INVALID_ORDER_REQUEST');

    try {
      const { sub } = await accountGuard({
        event: { headers: { Authorization: 'Bearer ' + identity.token } }, userId: identity.sub,
        pool, clientId, profilesTable: customersTable,
        getUser: token => cognito.send(new GetUserCommand({ AccessToken: token })),
        getProfile: userId => get(customersTable, { userId }),
      });
      if (!list) {
        const order = await get(ordersTable, { PK: 'ORDER#' + orderId, SK: 'META' });
        if (!owned(order, sub) || order.orderId !== orderId) return fail(404, 'ORDER_NOT_FOUND');
        const view = publicOrder(order);
        if (id(order.driverId) && !isTerminalOrderStatus(order.status)) {
          const driver = await get(driversTable, { driverId: order.driverId }, {
            ProjectionExpression: '#name, vehicleType, licenseNumber',
            ExpressionAttributeNames: { '#name': 'name' },
          });
          if (driver) {
            view.driverName ??= driver.name;
            view.vehicleType ??= driver.vehicleType;
            view.vehiclePlate ??= driver.licenseNumber;
          }
        }
        return reply(200, { success: true, order: view });
      }
      if (event.pathParameters?.user_id !== sub) return fail(403, 'ACCOUNT_MISMATCH');
      const history = query.historyDays === '30';
      const limit = query.limit === undefined ? (history ? 100 : 20) : Number(query.limit);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100 ||
          (query.historyDays !== undefined && !history) || (query.status !== undefined && !id(query.status))) {
        return fail(400, 'INVALID_ORDER_REQUEST');
      }
      const request = {
        TableName: ordersTable, IndexName: 'GSI_User', KeyConditionExpression: 'userId_gsi=:user',
        ExpressionAttributeValues: { ':user': sub }, ScanIndexForward: false, Limit: limit,
      };
      if (history) {
        request.KeyConditionExpression += ' AND createdAt>=:since';
        request.ExpressionAttributeValues[':since'] = new Date(now() - 30 * 86400000).toISOString();
      }
      if (query.status) {
        const filter = ['active', 'completed'].includes(query.status) ? customerStatusFilter(query.status)
          : { expression: '#status=:status', names: { '#status': 'status' }, values: { ':status': query.status } };
        request.FilterExpression = filter.expression;
        request.ExpressionAttributeNames = filter.names;
        Object.assign(request.ExpressionAttributeValues, filter.values);
      }
      const orders = [];
      let next;
      let offset = 0;
      do {
        const response = await db.send(new QueryCommand({ ...request, ExclusiveStartKey: next }));
        orders.push(...(response.Items || []).filter(order => owned(order, sub)).map(publicOrder));
        next = response.LastEvaluatedKey;
      } while (history && next && ++offset < 10);
      return reply(200, { success: true, orders, count: orders.length, ...(next ? { lastEvaluatedKey: next } : {}) });
    } catch (error) {
      if ([401, 403, 409].includes(error.statusCode)) return fail(error.statusCode, error.code);
      return fail(503, 'ORDER_READ_UNAVAILABLE');
    }
  };
}

exports.createOrderReads = createOrderReads;
exports.handler = createOrderReads({
  db: DynamoDBDocumentClient.from(new DynamoDBClient({ maxAttempts: 2 })),
  cognito: new CognitoIdentityProviderClient({ maxAttempts: 2 }),
});
