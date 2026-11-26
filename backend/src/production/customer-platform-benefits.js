'use strict';

const {DynamoDBClient} = require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient, GetCommand} = require('@aws-sdk/lib-dynamodb');
const {CognitoJwtVerifier} = require('aws-jwt-verify');
const {list} = require('../functions/shared/platform-benefits');
const {list:discountList} = require('../functions/shared/discount-list');
const {preview} = require('../functions/shared/discount-preview');
const {checkoutTables} = require('../functions/create-order/quote-runtime/checkoutTables');

const active = '/promo-codes/active';
const validate = '/promo-codes/validate';
const branchDiscounts = '/business/{businessId}/discounts';
const merchantPreview = '/promo-codes/apply';
const methods = new Map([[active,'GET'],[validate,'POST'],[branchDiscounts,'GET'],[merchantPreview,'POST']]);
const id = /^[A-Za-z0-9][A-Za-z0-9_.:#-]{0,149}$/;
const discountId = /^[A-Za-z0-9_-]{1,150}$/;
const subject = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const headers = {
  'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Vary':'Authorization',
  'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Authorization,Content-Type',
  'Access-Control-Allow-Methods':'GET,POST,OPTIONS','X-Content-Type-Options':'nosniff',
};
const reply = (statusCode, message) => ({statusCode,headers,
  body:statusCode===204 ? '' : JSON.stringify({success:false,valid:false,message})});

function createHandler({db,verify,apiId,tables,readBenefits=list,readCampaigns=discountList(true,db),
  previewOffer=preview(true,db),readMerchantDiscounts=discountList(false,db),previewMerchantDiscount=preview(false,db)}) {
  const handlers = new Map([[active,readCampaigns],[validate,previewOffer],
    [branchDiscounts,readMerchantDiscounts],[merchantPreview,previewMerchantDiscount]]);
  return async event => {
    const path = event?.resource;
    if (!apiId || event?.requestContext?.apiId !== apiId || event?.requestContext?.stage !== 'production' ||
        !methods.has(path)) return reply(404,'NOT_FOUND');
    if (event.httpMethod === 'OPTIONS') return reply(204);
    if (event.httpMethod !== methods.get(path)) return reply(405,'METHOD_NOT_ALLOWED');
    const auth = Object.entries(event.headers ?? {}).filter(([key]) => key.toLowerCase() === 'authorization');
    const token = auth.length===1 && typeof auth[0][1]==='string' && /^Bearer (\S{1,8192})$/i.exec(auth[0][1])?.[1];
    if (auth.length && !token) return reply(401,'BENEFIT_LOGIN_REQUIRED');
    const query = event.queryStringParameters ?? {};
    const benefitFeed = path === active && query.benefits === '1';
    if (benefitFeed && !token) return reply(401,'BENEFIT_LOGIN_REQUIRED');
    let input;
    if (event.httpMethod === 'GET') {
      const allowed = path===active ? ['benefits','userId','addressId','businessId'] : ['userId','addressId','itemIds'];
      if ((query.benefits!==undefined && !benefitFeed) ||
          Object.keys(query).some(k => !allowed.includes(k)) ||
          Object.values(event.multiValueQueryStringParameters ?? {}).some(values => values.length !== 1) ||
          ['addressId','businessId'].some(k => query[k]!==undefined && (typeof query[k]!=='string' || !id.test(query[k]))) ||
          (path===branchDiscounts && (typeof event.pathParameters?.businessId!=='string' ||
            !id.test(event.pathParameters.businessId) ||
            (query.itemIds!==undefined && (typeof query.itemIds!=='string' || query.itemIds.length>6040)))))
        return reply(400,'BENEFIT_INVALID');
      input = query;
    } else {
      if (Object.keys(query).length || event.isBase64Encoded || typeof event.body!=='string' ||
          Buffer.byteLength(event.body)>64000) return reply(400,'BENEFIT_INVALID');
      try { input=JSON.parse(event.body); } catch { return reply(400,'BENEFIT_INVALID'); }
      const branch = path===validate ? input?.storeId : input?.businessId;
      if (!input || typeof input!=='object' || Array.isArray(input) ||
          !Array.isArray(input.items) || input.items.length>100 || input.items.length===0 ||
          typeof branch!=='string' || !id.test(branch) ||
          [input.storeId,input.businessId].some(value=>value!=null && value!==branch) ||
          (input.addressId!=null && (typeof input.addressId!=='string' || !id.test(input.addressId))) ||
          (path===merchantPreview && (typeof input.discountId!=='string' || !discountId.test(input.discountId))))
        return reply(400,'BENEFIT_INVALID');
    }
    if (!token) {
      if (input.userId!=null && input.userId!=='guest' || path===validate && input.platformDiscountId!=null)
        return reply(401,'BENEFIT_LOGIN_REQUIRED');
      const result = await handlers.get(path)(event);
      return {...result,headers};
    }
    let account;
    try { account = (await verify(token)).sub; } catch { return reply(401,'BENEFIT_LOGIN_REQUIRED'); }
    if (typeof account !== 'string' || !subject.test(account)) return reply(401,'BENEFIT_LOGIN_REQUIRED');
    if (input.userId !== account) return reply(403,'BENEFIT_LOGIN_REQUIRED');
    try {
      const get = async (TableName,Key) => (await db.send(new GetCommand({TableName,Key,ConsistentRead:true}))).Item;
      const [profile,deletion] = await Promise.all([
        get(tables.customers,{userId:account}),get(tables.deletion,{pk:'ACCOUNT_LIFECYCLE#CUSTOMER#'+account,sk:'META'}),
      ]);
      if (deletion || profile?.cognitoSub!==account || profile.isActive===false || profile.isDeleted===true ||
          profile.deletedAt!=null || profile.deletionRequestId!=null) return reply(403,'BENEFIT_ACCOUNT_UNAVAILABLE');
      const request = {...event,headers:{Authorization:'Bearer '+token}};
      if (benefitFeed) return {statusCode:200,headers,body:JSON.stringify(await readBenefits(db,request))};
      const result = await handlers.get(path)(request);
      return {...result,headers};
    } catch (error) {
      const code = error?.message;
      if (/^(BENEFIT_|OFFER_|AUTH_REQUIRED$)/.test(code ?? '')) return reply(error.statusCode ?? 409,code);
      console.error('Customer benefits unavailable',error?.name ?? 'Error');
      return reply(503,'BENEFIT_UNAVAILABLE');
    }
  };
}
const poolId = process.env.USER_POOL_ID;
const clientId = process.env.USER_POOL_CLIENT_ID;
const jwt = poolId && clientId && CognitoJwtVerifier.create({userPoolId:poolId,clientId,tokenUse:'access'});
const db = DynamoDBDocumentClient.from(new DynamoDBClient({region:'us-east-1',maxAttempts:2}),
  {marshallOptions:{removeUndefinedValues:true}});
const live = jwt && createHandler({db,verify:token=>jwt.verify(token),apiId:process.env.BENEFITS_API_ID,tables:checkoutTables()});
module.exports = {createHandler,handler:event => live && process.env.STAGE==='production' && process.env.AWS_REGION==='us-east-1'
  ? live(event) : reply(503,'BENEFIT_UNAVAILABLE')};
