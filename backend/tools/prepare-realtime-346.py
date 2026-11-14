"""Patch captured staging packages only; retain every unrelated archive entry."""
import pathlib,zipfile,json,hashlib,base64
ROOT=pathlib.Path(__file__).resolve().parents[1]
CAP=pathlib.Path('/private/tmp/realtime-346')
manifest=[]
for name in ['WizzUser-WebSocketConnect-staging','WizzUser-WebSocketDefault-staging','WizzUser-WebSocketHeartbeat-staging','WizzUser-WebSocketSendUpdate-staging']:
 cfg=json.loads((CAP/(name+'-config.private.json')).read_text());entry=cfg['Handler'].rsplit('.',1)[0]+'.js'
 with zipfile.ZipFile(CAP/(name+'-before.zip')) as z:
  original={n:z.read(n) for n in z.namelist()};files=dict(original);source=files[entry].decode()
  for module in ['realtime-identity-scope-346.js','merchant-realtime-scope-345.js']:
   files[module]=(ROOT/'src'/module).read_bytes()
  if 'Connect' in name:
   old="require('../../merchant-realtime-scope-345').scopedClient(DynamoDBDocumentClient.from(client))"
   assert source.count(old)==1
   source=source.replace(old,"require('../../realtime-identity-scope-346').scopedClient("+old+")")
   old="module.exports = {handler:require('../../merchant-realtime-scope-345').guardConnect(handler)};"
   assert source.count(old)==1;source=source.replace(old,"module.exports = {handler:require('../../realtime-identity-scope-346').guardConnect(require('../../merchant-realtime-scope-345').guardConnect(handler))};")
   manager=files['universal_websocket_manager.js'].decode()
   old='this.dynamoDB = DynamoDBDocumentClient.from(this.dynamoClient);';assert manager.count(old)==1
   manager=manager.replace(old,"this.dynamoDB = require('./realtime-identity-scope-346').scopedClient(require('./merchant-realtime-scope-345').scopedClient(DynamoDBDocumentClient.from(this.dynamoClient)));")
   old="if (!require('./merchant-realtime-scope-345').currentScope()) await this.disconnectExistingConnections";assert manager.count(old)==1
   manager=manager.replace(old,"if (!require('./merchant-realtime-scope-345').currentScope() && !require('./realtime-identity-scope-346').currentScope()) await this.disconnectExistingConnections")
   old='await this.createDefaultSubscriptions(';assert manager.count(old)==1
   manager=manager.replace(old,"if (require('./realtime-identity-scope-346').currentScope()?.role !== 'GUEST') await this.createDefaultSubscriptions(")
   manager=manager.replace('console.log(`🔍 [DEBUG] Full event object:`, JSON.stringify(event, null, 2));',"console.log('WebSocket connect received', {connectionId});").replace('console.log(`🔍 [DEBUG] Query params object:`, JSON.stringify(queryParams, null, 2));',"console.log('WebSocket parameter names',Object.keys(queryParams));")
   files['universal_websocket_manager.js']=manager.encode()
  elif 'Default' in name:
   assert 'merchant-realtime-scope-345' in source
   source+="\nexports.handler=require('../../realtime-identity-scope-346').guardDefault(exports.handler);\n"
  elif 'Heartbeat' in name:
   old='module.exports = { handler };';assert old in source
   source=source.replace(old,"module.exports = {handler:require('../../realtime-identity-scope-346').guardDefault(require('../../merchant-realtime-scope-345').guardDefault(handler))};")
  else:
   old="const { ApiGatewayManagementApiClient, PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');";assert source.count(old)==1
   source=source.replace(old,"const { PostToConnectionCommand } = require('@aws-sdk/client-apigatewaymanagementapi');\nconst { PrivateOrderApiClient: ApiGatewayManagementApiClient } = require('../../private-order-delivery-346');")
   files['private-order-delivery-346.js']=(ROOT/'src/private-order-delivery-346.js').read_bytes()
  files[entry]=source.encode()
  changed=[n for n in files if files[n]!=original.get(n)]
  out=CAP/(name+'-candidate.zip')
  with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as target:
   for n,data in files.items():target.writestr(n,data)
  manifest.append({'name':name,'entry':entry,'role':cfg['Role'],'baseHash':cfg['CodeSha256'],'candidateHash':base64.b64encode(hashlib.sha256(out.read_bytes()).digest()).decode(),'changedEntries':changed,'unrelatedEntriesPreserved':True})
  syntax=CAP/'syntax'/name
  for n in changed:
   if n.endswith('.js'):(syntax/n).parent.mkdir(parents=True,exist_ok=True);(syntax/n).write_bytes(files[n])
(CAP/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest,indent=2))
