process.env.CHECKOUT_267_PREFLIGHT='1';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),C=path.resolve(__dirname,'../../whizzCentralPlatform-stg');
const sdk=require(C+'/backend/wallet-service/node_modules/@aws-sdk/lib-dynamodb'),{DynamoDBClient}=require(C+'/backend/wallet-service/node_modules/@aws-sdk/client-dynamodb');
const real=sdk.DynamoDBDocumentClient.from(new DynamoDBClient({region:'us-east-1'})),counts={reads:0,conditionChecks:0};
const db={send:async c=>{if(c instanceof sdk.GetCommand){assert.notEqual(c.input.TableName,'staging-AccountDeletion');counts.reads++;}
else{assert(c instanceof sdk.TransactWriteCommand);assert(c.input.TransactItems.every(x=>Object.keys(x).join()==='ConditionCheck'));counts.conditionChecks+=c.input.TransactItems.length;}
return real.send(c);}};
(async()=>{const start=Date.now();const out=await require('./test-checkout-writer-267.cjs').createStagingDeliveryFundingReader({db,lifecycleReadMode:'CONDITION_CHECK'}).prepare(JSON.parse(fs.readFileSync('/private/tmp/checkout-267/policy-pin.private.json')));assert(out.operations.every(x=>x.ConditionCheck));assert(out.operations.filter(x=>x.ConditionCheck.TableName==='staging-AccountDeletion').length>=2);console.log(JSON.stringify({status:'PASS',...counts,elapsedMs:Date.now()-start,policyVerified:true,finalOrderGuardsRetained:true,noMutations:true}));})().catch(e=>{console.error(e.code||e.name);process.exitCode=1;});
