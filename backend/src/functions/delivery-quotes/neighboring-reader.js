'use strict';
const { isIP } = require('node:net');
const maximumBatchSize = 8;

function createPreview(runtime, env, db, catalogPreview = false) {
 const secrets = new runtime.SecretsManagerClient({});
 return runtime.createStagingPointStorefrontPreview317({
  db,
  catalogPreview,
  createRouter: guardedDb => runtime.createStagingSecretDeliveryRouting({
   db: guardedDb, secrets, secretArn: env.MAPBOX_SECRET_ARN, profile: 'driving',
   ttlSeconds: 120, timeoutMs: 8000, credentialTimeoutMs: 2000,
  }),
 });
}

// Catalog invokes this function directly with IAM. API Gateway puts caller data in event.body.
async function readNeighboringBranches(selections, sourceIp) {
 const env = process.env;
 if (env.ENVIRONMENT !== 'staging' || env.AWS_REGION !== 'us-east-1' ||
     env.DELIVERY_QUOTES_ENABLED !== 'true' || env.STOREFRONT_POINT_PREVIEW_ENABLED !== 'true') throw Error('DELIVERY_CHECK_UNAVAILABLE');
 if (!Array.isArray(selections) || !selections.length || selections.length > maximumBatchSize ||
     typeof sourceIp !== 'string' || !isIP(sourceIp)) return { eligible: [] };
 const runtime = require('./point-preview-runtime-317');
 const clean = selections.map(runtime.pointSelection317);
 const db = runtime.DynamoDBDocumentClient.from(new runtime.DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
 const operating = await runtime.readDeliveryOperations(db, env);
 await runtime.reservePublicPointPreview317({ db, sourceIp, maxPerMinute: Math.min(30, operating.values.quoteMaxPerCustomerPerMinute * 2) });
 const reader = createPreview(runtime, env, db, true);
 const results = await Promise.allSettled(clean.map(selection => reader.preview(selection)));
 return { eligible: results.flatMap(r => r.status === 'fulfilled'
  ? [{ branchId: r.value.branchId, roadDistanceMeters: r.value.roadDistanceMeters,
       arrivalMinutes: r.value.arrivalMinutes?.maximum ?? null }]
  : []) };
}

function neighboringRequest(event) {
 return event && Object.keys(event).length === 2 &&
  Object.hasOwn(event, 'sourceIp') && Object.hasOwn(event, 'neighboringBranchPreviews');
}

module.exports = { neighboringRequest, readNeighboringBranches, createPreview };
