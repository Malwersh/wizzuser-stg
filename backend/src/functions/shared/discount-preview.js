'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient}=require('@aws-sdk/lib-dynamodb');
const {resolveDiscount}=require('./discount-reservation');
const {createStagingOrderGoodsPricing}=require('../create-order/quote-runtime/orderGoodsPricing');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({}));
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization','Access-Control-Allow-Methods':'POST,OPTIONS'};
exports.preview = platform => async event => {
 const reply=(statusCode,body)=>({statusCode,headers,body:JSON.stringify(body)});
 if(event.httpMethod==='OPTIONS')return reply(204,{});
 try {
  const b=typeof event.body==='string'?JSON.parse(event.body):event.body;
  if(!b||!Array.isArray(b.items)||typeof (b.businessId||b.storeId)!=='string'||
    typeof b.deliveryFee!=='number'||!Number.isFinite(b.deliveryFee)||b.deliveryFee<0||b.deliveryFee>1e9)
    return reply(400,{valid:false,message:'INVALID_DISCOUNT_PREVIEW'});
  const catalog=await createStagingOrderGoodsPricing({db}).price({branchId:b.businessId||b.storeId,
   items:b.items.map(i=>({productId:i.id||i.productId||i.itemId,quantity:i.quantity}))});
  const deliveryFee=Math.round(b.deliveryFee*1000),subtotal=catalog.goodsGross.minorAmount;
  const result=await resolveDiscount({db,branchId:b.businessId||b.storeId,discountId:platform?null:b.discountId,
   promoCode:platform?b.code:null,subtotal,items:[],deliveryFee});
  if(!result.snapshot)return reply(400,{valid:false,message:'DISCOUNT_REQUIRED'});
  return reply(200,{success:true,valid:true,previewOnly:true,discountAmount:result.amount/1000,
   discountAmountFils:result.amount,finalTotal:(subtotal+deliveryFee-result.amount)/1000,
   message:'PREVIEW_REVALIDATED_AT_ORDER_COMMIT'});
 }catch(e){return reply(e.statusCode|| (e instanceof SyntaxError?400:503),{valid:false,success:false,message:['INVALID_GOODS_SELECTION','GOODS_UNAVAILABLE','GOODS_PRICING_UNSUPPORTED'].includes(e.code)?e.code:'DISCOUNT_UNAVAILABLE'});}
};
