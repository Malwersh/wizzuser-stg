'use strict';
const crypto=require('crypto');
exports.intent=(userId,data)=>{
 if(data.idempotency_key===undefined||data.idempotency_key===null)return null;
 if(typeof data.idempotency_key!=='string'||!/^[-_A-Za-z0-9]{16,100}$/.test(data.idempotency_key))throw Object.assign(Error('INVALID_ADDRESS_REQUEST_KEY'),{statusCode:400});
 const fields=['name','province','district','neighborhood','landmark','detailed_address','fullAddress','latitude','longitude','address_type','is_default','building_number','floor_number','apartment_number','phone_number'];
 const input=Object.fromEntries(fields.map(k=>[k,data[k]??null]));
 if(data.save_to_address_book===false)input.storage='CHECKOUT_ADDRESS';
 return {addressId:'addr_'+crypto.createHash('sha256').update(userId+'|'+data.idempotency_key).digest('hex').slice(0,32),hash:crypto.createHash('sha256').update(JSON.stringify(input)).digest('hex')};
};
exports.replay=async({db,GetCommand,table,userId,intent,data})=>{
 if(!intent)return null;
 const row=(await db.send(new GetCommand({TableName:table,Key:{addressId:intent.addressId},ConsistentRead:true}))).Item;
 if(!row)return null;
 if(row.userId!==userId||row.creationRequestHash!==intent.hash||row.latitude!==data.latitude||row.longitude!==data.longitude)throw Object.assign(Error('ADDRESS_REQUEST_CHANGED'),{statusCode:409});
 return row;
};
