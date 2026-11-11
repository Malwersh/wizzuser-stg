 'use strict';
const {ApiGatewayManagementApiClient}=require('@aws-sdk/client-apigatewaymanagementapi');
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient}=require('@aws-sdk/lib-dynamodb');
const {CognitoIdentityProviderClient}=require('@aws-sdk/client-cognito-identity-provider');
const {authorizePrivateRecipient}=require('./realtime-identity-scope-346');
class PrivateOrderApiClient {
 constructor(options,{db=DynamoDBDocumentClient.from(new DynamoDBClient({region:'us-east-1'})),cognito=new CognitoIdentityProviderClient({region:'us-east-1'}),api=new ApiGatewayManagementApiClient(options)}={}) {this.db=db;this.cognito=cognito;this.api=api;}
 async send(command) {
  if(command.constructor.name!=='PostToConnectionCommand')throw Error('PRIVATE_SEND_COMMAND_INVALID');
  const data=typeof command.input.Data==='string'?command.input.Data:Buffer.from(command.input.Data).toString();
  const message=JSON.parse(data);
  if(!message.orderId)throw Error('PRIVATE_SEND_ORDER_REQUIRED');
  const scope=await authorizePrivateRecipient(this.db,this.cognito,command.input.ConnectionId,message.orderId);
  if(message.type==='driver_location'&&scope.role!=='CUSTOMER')throw Error('CUSTOMER_TRACKING_REQUIRED');
  if(message.type==='driver_location'){const {GetCommand}=require('@aws-sdk/lib-dynamodb');const o=(await this.db.send(new GetCommand({TableName:'WizzOrders',Key:{PK:'ORDER#'+message.orderId,SK:'META'},ConsistentRead:true}))).Item;if(!o||o.driverId!==message.driverId||!['picked_up','heading_to_customer','arrived_at_customer','on_the_way','out_for_delivery'].includes(o.status))throw Object.assign(Error('TRACKING_ENDED'),{status:403});}
  // Do not send private guest bearer tokens over a tracking channel.
  delete message.guestToken;delete message.guest_token;
  command.input.Data=Buffer.from(JSON.stringify(message));
  return this.api.send(command);
 }
}
module.exports={PrivateOrderApiClient};
