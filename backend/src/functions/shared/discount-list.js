'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,QueryCommand,ScanCommand,GetCommand}=require('@aws-sdk/lib-dynamodb');
const {normalizeDiscount,normalizePlatformPromo,validateDiscount,validatePlatformPromo}=require('./discount-engine');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({}));
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET,OPTIONS'};
exports.list = platform => async event => {
 const reply=(statusCode,b)=>({statusCode,headers,body:JSON.stringify(b)});
 if(event.httpMethod==='OPTIONS')return reply(204,{});
 const branch=event.pathParameters?.businessId;
 if(!platform&&(typeof branch!=='string'||branch.length>150||!branch))return reply(400,{success:false,message:'INVALID_BRANCH'});
 try {
  const table=platform?(process.env.PLATFORM_DISCOUNTS_TABLE||'WizzCentral_Platform_Discounts'):(process.env.DISCOUNTS_TABLE||'WhizzMerchants_Discounts');
  const rows=[];let cursor;
  for(let page=0;page<20;page++) {
   const args={TableName:table,Limit:50,...(cursor?{ExclusiveStartKey:cursor}:{})};
   const result=platform?await db.send(new ScanCommand({...args,ConsistentRead:true})):
    await db.send(new QueryCommand({...args,IndexName:'BusinessIdIndex',KeyConditionExpression:'#b=:b',
      ExpressionAttributeNames:{'#b':'businessId'},ExpressionAttributeValues:{':b':branch}}));
   for(let raw of result.Items||[]) {
    if(!platform)raw=(await db.send(new GetCommand({TableName:table,Key:{discountId:raw.discountId},ConsistentRead:true}))).Item;
    if(!raw||(!platform&&raw.businessId!==branch))continue;
    const d=platform?normalizePlatformPromo(raw):normalizeDiscount(raw);
    if(!(platform?validatePlatformPromo(d,Number.MAX_SAFE_INTEGER):validateDiscount(d,Number.MAX_SAFE_INTEGER)).valid)continue;
    if(![undefined,'allItems','minimumOrder'].includes(d.applicability))continue;
    if(platform&&(!d.code||raw.singleUse||raw.applicableToAll===false||raw.targetRestaurants?.length||raw.targetSegments?.length||raw.occasions?.length||
      (raw.target&&raw.target!=='all')||raw.customerSegments?.some(x=>x!=='all')))continue;
    rows.push(platform?{code:d.code,title:d.title||'',description:d.description||'',type:d.type,value:d.value,minOrderAmount:d.minimumOrderAmount,endDate:d.validTo||null}:
      {discountId:d.discountId,businessId:branch,title:d.title||'',description:d.description||'',type:d.type,value:d.value,
       applicability:d.applicability||'allItems',minimumOrderAmount:d.minimumOrderAmount,validFrom:d.validFrom||null,validTo:d.validTo||null});
    if(rows.length>200)throw Error('DISCOUNT_LIST_LIMIT');
   }
   cursor=result.LastEvaluatedKey;if(!cursor)return reply(200,{success:true,[platform?'promos':'discounts']:rows,count:rows.length});
  }
  throw Error('DISCOUNT_LIST_LIMIT');
 }catch{return reply(503,{success:false,message:'DISCOUNT_LIST_UNAVAILABLE'});}
};
