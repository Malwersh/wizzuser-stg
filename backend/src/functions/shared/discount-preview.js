'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient}=require('@aws-sdk/lib-dynamodb');
const {offerContext}=require('./offer-context');
const {catalogItems}=require('./offer-eligibility');
const {resolveDiscount}=require('./discount-reservation');
const {hasDiscountCustomizations,discountGoodsSelection}=require('./discount-contract');
const {createStagingOrderGoodsPricing}=require('../create-order/quote-runtime/orderGoodsPricing');
const documentClient=DynamoDBDocumentClient.from(new DynamoDBClient({}));
const db={async send(command){try{return await documentClient.send(command);}catch(e){console.error('Offer data access failed',{table:command.input.TableName,name:e.name,message:e.message});throw e;}}};
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization','Access-Control-Allow-Methods':'POST,OPTIONS'};
const catalogErrors = new Map([['INVALID_GOODS_SELECTION',400],['GOODS_UNAVAILABLE',409],['GOODS_PRICING_UNSUPPORTED',409]]);
exports.preview = (platform,store=db) => async event => {
 const reply=(statusCode,body)=>({statusCode,headers,body:JSON.stringify(body)});
 if(event.httpMethod==='OPTIONS')return reply(204,{});
 try {
  const b=typeof event.body==='string'?JSON.parse(event.body):event.body;
  if(!b||!Array.isArray(b.items)||typeof (b.businessId||b.storeId)!=='string'||
    b.items.some(i=>!i||typeof i!=='object'||Array.isArray(i))||
    typeof b.deliveryFee!=='number'||!Number.isFinite(b.deliveryFee)||b.deliveryFee<0||b.deliveryFee>1e9)
    return reply(400,{valid:false,message:'INVALID_DISCOUNT_PREVIEW'});
  if(hasDiscountCustomizations(b.items))return reply(409,{valid:false,success:false,message:'UNSUPPORTED_DISCOUNT_ITEMS'});
  const context=await offerContext(store,event,b);
  const catalog=await createStagingOrderGoodsPricing({db:store}).price({branchId:b.businessId||b.storeId,
   items:b.items.map(discountGoodsSelection)});
  const deliveryFee=Math.round(b.deliveryFee*1000),subtotal=catalog.goodsGross.minorAmount;
  const result=await resolveDiscount({db:store,branchId:b.businessId||b.storeId,discountId:platform?null:b.discountId,
   promoCode:platform?b.code:null,platformDiscountId:platform?b.platformDiscountId:null,subtotal,items:catalogItems(catalog),deliveryFee,...context,preview:true});
  await require('./platform-benefits').previewStacking(store,result,b);
  if(result.deliveryBenefit)return reply(200,{success:true,valid:true,previewOnly:true,discountAmount:0,lines:[],deliveryBenefit:true,deliveryBenefitSavingAmount:result.deliveryBenefitSavingAmount,message:'BENEFIT_DELIVERY_PREVIEW_AT_CHECKOUT'});
  if(!result.snapshot)return reply(400,{valid:false,message:'DISCOUNT_REQUIRED'});
  return reply(200,{success:true,valid:true,previewOnly:true,discountAmount:result.amount/1000,
   discountAmountFils:result.amount,lines:result.lines,finalTotal:(subtotal+deliveryFee-result.amount)/1000,
   message:'PREVIEW_REVALIDATED_AT_ORDER_COMMIT'});
 }catch(e){
  console.error('Offer preview failed',{name:e.name,code:e.code,message:e.message});
  const catalogStatus=catalogErrors.get(e.code);
  const message=catalogStatus?e.code:/^(OFFER_|BENEFIT_)/.test(e.message||'')?e.message:'DISCOUNT_UNAVAILABLE';
  return reply(e.statusCode||catalogStatus||(e instanceof SyntaxError?400:503),{valid:false,success:false,message});
 }
};
