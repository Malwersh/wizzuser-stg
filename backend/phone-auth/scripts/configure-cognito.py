"""Attach the staging phone proof triggers, preserving existing pool/client settings."""
import json, os, subprocess, tempfile
import boto3
credentials = json.loads(subprocess.check_output(['aws','configure','export-credentials','--profile','Wizz_stg_UserApp','--format','process']))
session = boto3.Session(aws_access_key_id=credentials['AccessKeyId'], aws_secret_access_key=credentials['SecretAccessKey'], aws_session_token=credentials['SessionToken'], region_name='us-east-1')
assert session.client('sts').get_caller_identity()['Account'] == '699561669180'
c = session.client('cognito-idp')
pool_id, client_id = 'us-east-1_TpyyrVkEE', '4a9e8o3em311eq2rgckp0pd2s9'
function = session.client('lambda').get_function_configuration(FunctionName='WizzUser-phone-challenge-staging')
assert function['Environment']['Variables']['USER_POOL_ID'] == pool_id
arn = function['FunctionArn']
pool = c.describe_user_pool(UserPoolId=pool_id)['UserPool']
client = c.describe_user_pool_client(UserPoolId=pool_id,ClientId=client_id)['UserPoolClient']
backup = tempfile.NamedTemporaryFile(prefix='staging-phone-cognito-backup-',suffix='.json',delete=False,mode='w')
os.chmod(backup.name,0o600)
json.dump({'pool':pool,'client':client},backup,default=str)
backup.close()
triggers = dict(pool.get('LambdaConfig',{}))
for name in ['DefineAuthChallenge','CreateAuthChallenge','VerifyAuthChallengeResponse']:
    assert triggers.get(name) in [None,arn], 'Existing custom trigger requires review'
    triggers[name] = arn
allowed = c.meta.service_model.operation_model('UpdateUserPool').input_shape.members
payload = {k:v for k,v in pool.items() if k in allowed}
payload.update(UserPoolId=pool_id,LambdaConfig=triggers)
c.update_user_pool(**payload)
allowed = c.meta.service_model.operation_model('UpdateUserPoolClient').input_shape.members
payload = {k:v for k,v in client.items() if k in allowed}
payload.update(UserPoolId=pool_id,ClientId=client_id,ExplicitAuthFlows=list(dict.fromkeys(client['ExplicitAuthFlows']+['ALLOW_CUSTOM_AUTH'])))
c.update_user_pool_client(**payload)
assert c.describe_user_pool(UserPoolId=pool_id)['UserPool']['LambdaConfig'] == triggers
assert 'ALLOW_CUSTOM_AUTH' in c.describe_user_pool_client(UserPoolId=pool_id,ClientId=client_id)['UserPoolClient']['ExplicitAuthFlows']
print('Staging Cognito custom proof triggers and auth flow verified. Existing flows preserved.')
