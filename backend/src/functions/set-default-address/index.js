'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,QueryCommand,ScanCommand}=require('@aws-sdk/lib-dynamodb');
const {writeContext,commitBook}=require('../shared/address-book-319');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({maxAttempts:2}));
const headers={'Content-Type':'application/json; charset=utf-8','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization','Access-Control-Allow-Methods':'GET,POST,PUT,DELETE,OPTIONS'};
exports.handler=async event=>{
 if(event.httpMethod==='OPTIONS')return{statusCode:200,headers,body:'{}'};
 try{
  const userId=event.pathParameters?.user_id,addressId=event.pathParameters?.address_id;
  if(!userId||!addressId)throw Object.assign(Error('INVALID_ADDRESS'),{statusCode:400});
  const write=await writeContext(db,event,userId),a=(await db.send(new GetCommand({TableName:process.env.ADDRESSES_TABLE,Key:{addressId},ConsistentRead:true}))).Item;
  if(!a||a.userId!==userId||a.recordType==='CHECKOUT_ADDRESS')throw Object.assign(Error('ADDRESS_NOT_SAVED'),{statusCode:404});
  const regions=require('../../utils/customer-regions-313').create({db,sdk:{GetCommand,QueryCommand,ScanCommand},tables:{regions:process.env.REGIONS_TABLE,derived:process.env.REGIONS_DERIVED_TABLE,index:process.env.REGION_INDEX_TABLE}});
  const r=await regions.resolve(a.latitude,a.longitude);
  await commitBook({db,write,expectedAddress:a,makeDefault:true,regionChecks:regions.checks(r.path),operation:{Update:{TableName:process.env.ADDRESSES_TABLE,Key:{addressId},UpdateExpression:'SET updatedAt=:now, regionId=:region, regionNameAr=:label',ExpressionAttributeValues:{':now':new Date().toISOString(),':region':r.regionId,':label':r.regionNameAr}}}});
  return {statusCode:200,headers,body:JSON.stringify({success:true,message:'تم تعيين العنوان الافتراضي',data:{address_id:addressId,is_default:true,default_address_id:addressId}})};
 }catch(e){console.warn('Address default unavailable',{code:e.code||e.name});return{statusCode:e.statusCode||503,headers,body:JSON.stringify({success:false,code:e.code||e.message,message:e.code==='ADDRESS_BOOK_CHANGED'?'تغيّرت العناوين. حدّث القائمة ثم أعد المحاولة.':'تعذر تعيين العنوان الافتراضي. أعد المحاولة.'})};}
};
