const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const file = path.resolve(__dirname, '../src/production/customer-storefront.js');
function runtime({ business, businesses = [], onCatalog, menu, snapshots = [] } = {}) {
  const module = { exports: {} };
  class GetCommand { constructor(input) { this.input = input; } }
  class QueryCommand { constructor(input) { this.input = input; } }
  const sdk = {
    DynamoDBDocumentClient: { from: () => ({ send: async ({ input }) => {
      if (input.Key?.businessId) return { Item: business };
      if (input.Key?.sk === 'MENU_VERSION#ACTIVE') return { Item: menu };
      assert.equal(input.TableName, 'wizz-production-MerchantPlatform');
      assert.equal(input.ExpressionAttributeValues[':pk'], 'BRANCH#branch');
      assert.equal(input.ExpressionAttributeValues[':prefix'], 'MENU_VERSION#test#PRODUCT#');
      return { Items: snapshots };
    } }) },
    GetCommand, QueryCommand,
  };
  const context = {
    exports: module.exports,
    process: { env: { BUSINESSES_TABLE: 'wizz-production-Merchants', MERCHANT_PLATFORM_TABLE: 'wizz-production-MerchantPlatform' } },
    Buffer,
    console,
    require(name) {
      if (name === '@aws-sdk/client-dynamodb') return { DynamoDBClient: class {} };
      if (name === '@aws-sdk/lib-dynamodb') return sdk;
      if (name === './branch-menu-catalog') {
        const wrapper = { exports: {} };
        vm.runInNewContext(fs.readFileSync(path.join(path.dirname(file), 'branch-menu-catalog.js'), 'utf8'),
          { ...context, module: wrapper, require: () => sdk });
        return wrapper.exports;
      }
      if (name.includes('storefront-facts')) return require('../src/functions/shared/storefront-facts-170');
      if (name === './customer-address-search') return { createAddressSearch: () => async () => ({ statusCode: 401 }) };
      return {
        async handler(request) {
          onCatalog?.(request);
          return { statusCode: 200, body: JSON.stringify({ success: true, data: { businesses } }) };
        },
      };
    },
  };
  vm.runInNewContext(fs.readFileSync(file, 'utf8'), context);
  return module.exports;
}
const event = (resource, extra = {}) => ({
  requestContext: { stage: 'production' }, httpMethod: 'GET', resource, ...extra,
});

test('storefront sends public fields only and excludes closed or deleted listings', async () => {
  const api = runtime({
    businesses: [
      { businessId: 'visible', isActive: true, ownerId: 'private', address: { city: 'بغداد', phone: 'private' } },
      { businessId: 'deleted', isActive: true, deletedAt: '2026-10-01' },
      { businessId: 'off', isActive: false },
    ],
    onCatalog: request => assert.equal(request.headers, undefined),
  });
  const response = await api.catalog(event('/api/businesses/by-region', { headers: { authorization: 'private' } }));
  assert.equal(response.statusCode, 200);
  const listings = JSON.parse(response.body).data.businesses;
  assert.deepEqual(listings.map(row => row.businessId), ['visible']);
  assert.equal(listings[0].ownerId, undefined);
  assert.deepEqual(listings[0].address, { city: 'بغداد' });
});

test('unpublished storefronts and unsupported routes cannot reach the product handler', async () => {
  const api = runtime({ business: { isActive: false }, onCatalog: () => assert.fail('Unexpected handler') });
  assert.equal((await api.catalog(event('/business/{businessId}/products', { pathParameters: { businessId: 'off' } }))).statusCode, 404);
  assert.equal((await api.catalog(event('/orders'))).statusCode, 404);
  assert.equal((await api.catalog(event('/api/regions/find-by-coordinates', { requestContext: { stage: 'staging' } }))).statusCode, 404);
});


test('unpublished products and categories are hidden even for a visible production branch', async () => {
  const api = runtime({ business: { isActive: true, onboardingSchemaVersion: 2 },
    onCatalog: () => assert.fail('draft should not call legacy storefront') });
  const ids = { pathParameters: { businessId: 'branch' } };
  const products = await api.catalog(event('/business/{businessId}/products', ids));
  const categories = await api.catalog(event('/business/{businessId}/categories', ids));
  assert.deepEqual(JSON.parse(products.body).products, []);
  assert.deepEqual(JSON.parse(categories.body).categories, []);
});

test('published branch categories deduplicate and exclude rows belonging to another branch', async () => {
  const category = { categoryId: 'cat', categoryName: 'مشروبات', businessId: 'branch' };
  const own = { product: { businessId: 'branch', publishedCategory: category } };
  const foreign = { product: { businessId: 'branch', publishedCategory: { ...category, businessId: 'foreign', categoryId: 'foreign' } } };
  const api = runtime({ business: { isActive: true, onboardingSchemaVersion: 2 },
    menu: { publishedVersion: 'test' }, snapshots: [own, own, foreign] });
  const categories = await api.catalog(event('/business/{businessId}/categories', { pathParameters: { businessId: 'branch' } }));
  assert.deepEqual(JSON.parse(categories.body).categories.map(row => [row.categoryId, row.nameAr]), [['cat', 'مشروبات']]);
});
