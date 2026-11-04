const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
for(const name of ['set-default-address','delete-address','remove-favorite']){
 test(name+' rejects closing account before changing dependent records',async()=>{
  let calls=0;const classes={};for(const n of ['GetCommand','QueryCommand','UpdateCommand','DeleteCommand'])classes[n]=class{constructor(input){this.input=input;}};
  const modules={'@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},'@aws-sdk/lib-dynamodb':{...classes,DynamoDBDocumentClient:{from:()=>({send:async()=>{calls++;throw Error('must not access records');}})}},'../create-order/guarded-write':{writeContext:async()=>{throw Object.assign(Error('ACCOUNT_UNAVAILABLE'),{statusCode:409});}}};
  const exports={};vm.runInNewContext(fs.readFileSync(__dirname+'/../'+name+'/index.js','utf8'),{exports,require:n=>modules[n],process:{env:{ADDRESSES_TABLE:'addresses',FAVORITES_TABLE:'favorites'}},console:{log(){},error(){}}});
  const r=await exports.handler({httpMethod:name==='set-default-address'?'PUT':'DELETE',pathParameters:{user_id:'one',address_id:'address',favorite_id:'favorite'}});
  assert.equal(r.statusCode,409);assert.equal(calls,0);
 });
}
