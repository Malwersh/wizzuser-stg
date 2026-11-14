'use strict';
// Deployment preserves the prior exact handler and all its companion files.
// Only this new, bounded, informational action is dispatched to the public point reader.
exports.handler=async(event,context)=>{
 let input;
 if(event.httpMethod==='POST'&&!event.isBase64Encoded&&typeof event.body==='string'&&Buffer.byteLength(event.body)<=2048){try{input=JSON.parse(event.body);}catch(_){}}
 if(!['storefront_point_preview','service_fee_preview'].includes(input?.action)){
  if(String(event.resource||event.path||'').endsWith('/storefront-point-preview'))return {statusCode:400,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'*'},body:JSON.stringify({success:false,code:'INVALID_STOREFRONT_REQUEST'})};
  return require('./legacy-index-317').handler(event,context);
 }
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization,X-Customer-Id','Access-Control-Expose-Headers':'Retry-After'};
 const reply=(statusCode,body)=>({statusCode,headers,body:JSON.stringify(body)});
 try{
  const env=process.env;
  if(env.STOREFRONT_POINT_PREVIEW_ENABLED!=='true'||env.DELIVERY_QUOTES_ENABLED!=='true'||env.ENVIRONMENT!=='staging'||env.AWS_REGION!=='us-east-1')return reply(503,{success:false,code:'POINT_PREVIEW_NOT_ENABLED'});
  if(Object.keys(event.queryStringParameters||{}).length)return reply(400,{success:false,code:'INVALID_STOREFRONT_REQUEST'});
  const runtime=require('./point-preview-runtime-317');
  const {action,...value}=input,selection=action==='storefront_point_preview'?runtime.pointSelection317(value):value;
  const db=runtime.DynamoDBDocumentClient.from(new runtime.DynamoDBClient({}),{marshallOptions:{removeUndefinedValues:true}});
  const operating=await runtime.readDeliveryOperations(db,env);
  await runtime.reservePublicPointPreview317({db,sourceIp:event.requestContext?.identity?.sourceIp||event.requestContext?.http?.sourceIp,maxPerMinute:Math.min(30,operating.values.quoteMaxPerCustomerPerMinute*2)});
  if(action==='service_fee_preview')return reply(200,{success:true,preview:await runtime.serviceFeePreview320(db,selection)});
  const secrets=new runtime.SecretsManagerClient({});
  const preview=await runtime.createStagingPointStorefrontPreview317({db,createRouter:guardedDb=>runtime.createStagingSecretDeliveryRouting({db:guardedDb,secrets,secretArn:env.MAPBOX_SECRET_ARN,profile:'driving',ttlSeconds:120,timeoutMs:8000,credentialTimeoutMs:2000})}).preview(selection);
  console.info('STOREFRONT_POINT_PREVIEW_READY',{branchId:preview.branchId,regionId:preview.regionId,feeMinor:preview.customerDeliveryFee.minorAmount,pricingMode:preview.pricingMode,roadDistanceMeters:preview.roadDistanceMeters});
  return reply(200,{success:true,preview});
 }catch(e){
  const code=e.code||e.message;
  if(code==='QUOTE_RATE_LIMITED')return {...reply(429,{success:false,code,retryAfterSeconds:60}),headers:{...headers,'Retry-After':'60'}};
  if(code==='INVALID_STOREFRONT_REQUEST')return reply(400,{success:false,code});
  if(code==='OUTSIDE_COVERAGE'||code==='OUTSIDE_DELIVERY_RANGE')return reply(409,{success:false,code});
  console.warn('POINT_PREVIEW_UNAVAILABLE',{code:typeof code==='string'?code:'UNKNOWN',requestId:event.requestContext?.requestId});
  return reply(503,{success:false,code:'QUOTE_SERVICE_UNAVAILABLE'});
 }
};
