'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand}=require('@aws-sdk/lib-dynamodb');
const {writeContext,commitBook,isDefault}=require('../shared/address-book-319');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({maxAttempts:2}));
const headers={'Content-Type':'application/json; charset=utf-8','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization','Access-Control-Allow-Methods':'GET,POST,PUT,DELETE,OPTIONS'};
exports.handler=async event=>{
 if(event.httpMethod==='OPTIONS')return{statusCode:200,headers,body:'{}'};
 try{
  const userId=event.pathParameters?.user_id,addressId=event.pathParameters?.address_id;
  if(!userId||!addressId)throw Object.assign(Error('INVALID_ADDRESS'),{statusCode:400});
  const write=await writeContext(db,event,userId),a=(await db.send(new GetCommand({TableName:process.env.ADDRESSES_TABLE,Key:{addressId},ConsistentRead:true}))).Item;
  if(!a)return{statusCode:200,headers,body:JSON.stringify({success:true,message:'العنوان غير موجود في القائمة',data:{deleted_address_id:addressId,already_absent:true}})};
  if(a.userId!==userId||a.recordType==='CHECKOUT_ADDRESS')throw Object.assign(Error('ADDRESS_NOT_SAVED'),{statusCode:404});
  const result=await commitBook({db,write,expectedAddress:a,operation:{Delete:{TableName:process.env.ADDRESSES_TABLE,Key:{addressId}}}});
  return {statusCode:200,headers,body:JSON.stringify({success:true,message:'تم حذف العنوان',data:{deleted_address_id:addressId,was_default:isDefault(a),new_default_address_id:result.defaultId}})};
 }catch(e){console.warn('Address delete unavailable',{code:e.code||e.name});return{statusCode:e.statusCode||503,headers,body:JSON.stringify({success:false,code:e.code||e.message,message:e.code==='ADDRESS_BOOK_CHANGED'?'تغيّرت العناوين. حدّث القائمة ثم أعد المحاولة.':'تعذر حذف العنوان. أعد المحاولة.'})};}
};
