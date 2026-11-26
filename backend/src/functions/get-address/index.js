'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand}=require('@aws-sdk/lib-dynamodb');
const {writeContext,formatAddress,isDefault}=require('../shared/address-book-319');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({maxAttempts:2}));
const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization','Access-Control-Allow-Methods':'GET,OPTIONS'};
exports.handler=async event=>{
 if(event.httpMethod==='OPTIONS')return{statusCode:200,headers,body:'{}'};
 try{
  const userId=event.pathParameters?.user_id,addressId=event.pathParameters?.address_id;
  if(!userId||!addressId)throw Object.assign(Error('INVALID_ADDRESS'),{statusCode:400});
  const context=await writeContext(db,event,userId);
  const a=(await db.send(new GetCommand({TableName:process.env.ADDRESSES_TABLE,Key:{addressId},ConsistentRead:true}))).Item;
  if(!a||a.userId!==userId||(a.recordType==='CHECKOUT_ADDRESS'&&a.checkoutExpiresAt<=Date.now()/1000))throw Object.assign(Error('ADDRESS_NOT_FOUND'),{statusCode:404});
  const defaultId=a.recordType==='CHECKOUT_ADDRESS'?null:context.profile.addressBook319?.defaultId??(isDefault(a)?addressId:null);
  return{statusCode:200,headers,body:JSON.stringify({success:true,data:formatAddress(a,defaultId)})};
 }catch(e){return{statusCode:e.statusCode||503,headers,body:JSON.stringify({success:false,code:e.code||e.message,message:'تعذر تحميل العنوان. حدّث القائمة ثم أعد المحاولة.'})};}
};
