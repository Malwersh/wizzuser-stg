const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient}=require('@aws-sdk/lib-dynamodb');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({}));
const legacy=require('../shared/discount-list').list(true);
exports.handler=async event=>{if(event.httpMethod==='OPTIONS'||event.queryStringParameters?.benefits!=='1')return legacy(event);try{return {statusCode:200,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Cache-Control':'no-store','Vary':'Authorization'},body:JSON.stringify(await require('../shared/platform-benefits').list(db,event))};}catch(e){return {statusCode:e.statusCode||503,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Cache-Control':'no-store','Vary':'Authorization'},body:JSON.stringify({success:false,message:e.message?.startsWith('BENEFIT_')?e.message:'BENEFIT_UNAVAILABLE'})};}};
