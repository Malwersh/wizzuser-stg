'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,QueryCommand,ScanCommand,GetCommand}=require('@aws-sdk/lib-dynamodb');
const {normalizeDiscount,normalizePlatformPromo,validateDiscount,validatePlatformPromo}=require('./discount-engine');
const {universal,removed}=require('./discount-contract');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({}));
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET,OPTIONS'};
exports.list = platform => async event => {
 const reply=(statusCode,b)=>({statusCode,headers,body:JSON.stringify(b)});
 if(event.httpMethod==='OPTIONS')return reply(204,{});
 const branch=event.pathParameters?.businessId;
 if(!platform&&(typeof branch!=='string'||branch.length>150||!branch))return reply(400,{success:false,message:'INVALID_BRANCH'});
 try {
  const table=platform?(process.env.PLATFORM_DISCOUNTS_TABLE||'WizzCentral_Platform_Discounts'):(process.env.DISCOUNTS_TABLE||'WhizzMerchants_Discounts');
  const query=event.queryStringParameters||{};
  const authenticated=!!(event.headers?.Authorization||event.headers?.authorization);
  const context=authenticated&&query.userId?await require('./offer-context').offerContext(db,event,{userId:query.userId,addressId:query.addressId}):null;
  const rows=[];let cursor;
  for(let page=0;page<20;page++) {
   const args={TableName:table,Limit:50,...(cursor?{ExclusiveStartKey:cursor}:{})};
   const result=platform?await db.send(new ScanCommand({...args,ConsistentRead:true})):
    await db.send(new QueryCommand({...args,IndexName:'BusinessIdIndex',KeyConditionExpression:'#b=:b',
      ExpressionAttributeNames:{'#b':'businessId'},ExpressionAttributeValues:{':b':branch}}));
   for(let raw of result.Items||[]) {
    if(!platform)raw=(await db.send(new GetCommand({TableName:table,Key:{discountId:raw.discountId},ConsistentRead:true}))).Item;
    if(!raw||(!platform&&raw.businessId!==branch))continue;
    if(removed(raw))continue;
    // The home code card has no merchant selector; scoped offers use the slideshow/detail journey.
    if(platform&&!branch&&(raw.businessId||raw.targetRestaurants?.length||raw.allowedBusinessIds?.length||raw.businessIds?.length))continue;
    if(context){try{await require('./offer-eligibility').eligibility(db,raw,{...context,branchId:branch,source:platform?'platform':'merchant',preview:true});}catch(e){if(e.statusCode===409||e.status===409)continue;throw e;}}
    else if(!universal(raw)||(authenticated&&(raw.customerSegments||[]).some(s=>s!=='all')))continue;
    let d;try{d=platform?normalizePlatformPromo(raw):normalizeDiscount(raw);}catch{continue;}
    if(!(platform?validatePlatformPromo(d,Number.MAX_SAFE_INTEGER):validateDiscount(d,Number.MAX_SAFE_INTEGER)).valid)continue;
    if(![undefined,'allItems','minimumOrder','specificItems','specificCategories'].includes(d.applicability))continue;
    if(platform&&!d.code)continue;
    rows.push(platform?{code:d.code,title:d.title||'',description:d.description||'',type:d.type,value:d.value,minOrderAmount:d.minimumOrderAmount,endDate:d.validTo||null}:
      {discountId:d.discountId,businessId:branch,title:d.title||'',description:d.description||'',type:d.type,value:d.value,
       applicability:d.applicability||'allItems',applicable_item_ids:d.applicable_item_ids||[],applicable_category_ids:d.applicable_category_ids||[],minimumOrderAmount:d.minimumOrderAmount,validFrom:d.validFrom||null,validTo:d.validTo||null});
    if(rows.length>200)throw Error('DISCOUNT_LIST_LIMIT');
   }
   cursor=result.LastEvaluatedKey;if(!cursor)return reply(200,{success:true,[platform?'promos':'discounts']:rows,count:rows.length});
  }
  throw Error('DISCOUNT_LIST_LIMIT');
 }catch{return reply(503,{success:false,message:'DISCOUNT_LIST_UNAVAILABLE'});}
};
