'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient}=require('@aws-sdk/lib-dynamodb');
const {writeContext,readSavedBook,formatAddress}=require('../shared/address-book-319');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({maxAttempts:2}));
const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization','Access-Control-Allow-Methods':'GET,POST,PUT,DELETE,OPTIONS'};
exports.handler=async event=>{
 if(event.httpMethod==='OPTIONS')return{statusCode:200,headers,body:'{}'};
 try{
  const userId=event.pathParameters?.user_id;if(!userId)throw Object.assign(Error('INVALID_USER'),{statusCode:400});
  const write=await writeContext(db,event,userId),book=await readSavedBook(db,write,{mutation:false});
  return{statusCode:200,headers,body:JSON.stringify({success:true,data:{addresses:book.rows.map(a=>formatAddress(a,book.defaultId)),total:book.rows.length,default_address_id:book.defaultId,book_revision:book.meta?.revision??0}})};
 }catch(e){console.warn('Address book unavailable',{code:e.code||e.name});return{statusCode:e.statusCode||503,headers,body:JSON.stringify({success:false,code:e.code||e.message,message:'تعذر تحميل عناوينك. أعد المحاولة.'})};}
};
