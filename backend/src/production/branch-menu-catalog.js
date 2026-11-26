'use strict';

const { GetCommand, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

async function activeMenu(db, businessId) {
  return (await db.send(new GetCommand({
    TableName: process.env.MERCHANT_PLATFORM_TABLE,
    Key: { pk: 'BRANCH#' + businessId, sk: 'MENU_VERSION#ACTIVE' },
    ConsistentRead: true,
  }))).Item;
}

async function publishedCategories(db, businessId, business) {
  const active = await activeMenu(db, businessId);
  const found = new Map();
  let cursor;
  do {
    let page;
    if (active?.publishedVersion) {
      page = await db.send(new QueryCommand({
        TableName: process.env.MERCHANT_PLATFORM_TABLE,
        KeyConditionExpression: 'pk=:pk AND begins_with(sk,:prefix)',
        ExpressionAttributeValues: {
          ':pk': 'BRANCH#' + businessId,
          ':prefix': 'MENU_VERSION#' + active.publishedVersion + '#PRODUCT#',
        },
        ConsistentRead: true,
        ExclusiveStartKey: cursor,
      }));
    } else if (business.onboardingSchemaVersion !== 2) {
      page = await db.send(new ScanCommand({
        TableName: process.env.CATEGORIES_TABLE,
        FilterExpression: 'attribute_not_exists(businessId) AND (attribute_not_exists(businessType) OR businessType=:type)',
        ExpressionAttributeValues: {':type': business.businessType || business.business_type || 'restaurant'},
        ExclusiveStartKey: cursor,
      }));
    } else break;
    for (const row of page.Items || []) {
      if (active?.publishedVersion && row.product?.businessId !== businessId) continue;
      const item = active?.publishedVersion ? row.product.publishedCategory : row;
      if (!item?.categoryId || (item.businessId && item.businessId !== businessId) ||
          item.isActive === false || item.is_active === false) continue;
      const nameAr = item.name_ar || item.categoryName || item.name;
      if (!nameAr) continue;
      const nameEn = item.categoryNameEn || item.name_en || item.name || nameAr;
      found.set(item.categoryId, { categoryId: item.categoryId, category_id: item.categoryId,
        id: item.categoryId, name_ar: nameAr, nameAr, name_en: nameEn, nameEn });
    }
    cursor = page.LastEvaluatedKey;
  } while (cursor);
  const categories = [...found.values()].sort((a, b) => a.nameAr.localeCompare(b.nameAr, 'ar'));
  return { success: true, categories, count: categories.length };
}

function visible(business) {
  return business?.isActive === true && !business.isDeleted && !business.deletedAt &&
    !business.deletionRequestId && !['DELETED', 'DRAFT', 'PENDING', 'REJECTED', 'SUSPENDED'].includes(String(business.status || '').toUpperCase());
}

function wrapCatalog({ db, catalog, reply }) {
  return async event => {
    const resource = event.resource;
    const categories = resource === '/business/{businessId}/categories';
    if (event.requestContext?.stage !== 'production' || event.httpMethod !== 'GET' ||
        (!categories && resource !== '/business/{businessId}/products') || event.isBase64Encoded ||
        (event.body && Buffer.byteLength(event.body) > 32000)) return catalog(event);
    const businessId = event.pathParameters?.businessId;
    if (!businessId) return catalog(event);
    try {
      const { Item: business } = await db.send(new GetCommand({
        TableName: process.env.BUSINESSES_TABLE, Key: { businessId }, ConsistentRead: true,
      }));
      if (!visible(business)) return reply(404, { success: false, code: 'NOT_FOUND' });
      if (categories) return reply(200, await publishedCategories(db, businessId, business));
      if (business.onboardingSchemaVersion === 2 && !(await activeMenu(db, businessId))?.publishedVersion) {
        return reply(200, { success: true, products: [], count: 0 });
      }
      return catalog(event);
    } catch (error) {
      console.warn('Published menu read failed', error.name);
      return reply(503, { success: false, code: 'SERVICE_UNAVAILABLE', message: 'تعذر إكمال العملية. أعد المحاولة.' });
    }
  };
}

module.exports = { wrapCatalog, visible };
