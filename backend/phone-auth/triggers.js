'use strict';
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,UpdateCommand}=require('@aws-sdk/lib-dynamodb');
const {SecretsManagerClient,GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager');
const {defineChallenge}=require('./challenge-policy');
const {proofMatches}=require('./login-proof');
const db=DynamoDBDocumentClient.from(new DynamoDBClient({})),secrets=new SecretsManagerClient({});
exports.handler=async e=>{
 if(e.userPoolId!==process.env.USER_POOL_ID)throw Error('Wrong pool');
 if(e.triggerSource==='DefineAuthChallenge_Authentication')return defineChallenge(e);
 if(e.request.userNotFound || e.request.userAttributes.phone_number_verified!=='true')throw Error('Phone verification required');
 const table=process.env.OTP_TABLE,time=Math.floor(Date.now()/1000);
 if(e.triggerSource==='CreateAuthChallenge_Authentication'){
  const {Item:login}=await db.send(new GetCommand({TableName:table,Key:{id:`LOGIN#${e.userName}`},ConsistentRead:true}));
  if(!login || login.expiresAt<=time)throw Error('SMS verification required');
  const {Item:proof}=await db.send(new GetCommand({TableName:table,Key:{id:login.proofId},ConsistentRead:true}));
  if(!proof || proof.username!==e.userName || proof.purpose!=='login-proof' || proof.used || proof.expiresAt<=time)throw Error('SMS verification required');
  e.response.privateChallengeParameters={id:proof.id};e.response.publicChallengeParameters={method:'verified-phone'};e.response.challengeMetadata=proof.id;return e;
 }
 if(e.triggerSource==='VerifyAuthChallengeResponse_Authentication'){
  e.response.answerCorrect=false;const id=e.request.privateChallengeParameters?.id;if(!id)return e;
  const {Item:proof}=await db.send(new GetCommand({TableName:table,Key:{id},ConsistentRead:true}));
  const config=JSON.parse((await secrets.send(new GetSecretValueCommand({SecretId:process.env.OTP_SECRET_ARN}))).SecretString);
  if(!proofMatches(config.hmacKey,proof,e.userName,e.request.challengeAnswer,time))return e;
  try{await db.send(new UpdateCommand({TableName:table,Key:{id},UpdateExpression:'SET used = :yes',ConditionExpression:'username = :username AND used = :no AND expiresAt > :now',ExpressionAttributeValues:{':username':e.userName,':yes':true,':no':false,':now':time}}));e.response.answerCorrect=true;}
  catch(x){if(x.name!=='ConditionalCheckFailedException')throw x;}return e;
 }
 throw Error('Unsupported trigger');
};
