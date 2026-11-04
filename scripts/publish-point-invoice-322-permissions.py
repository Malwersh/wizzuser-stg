"""Apply only the two read grants explicitly approved by the user. No code/data writes."""
from pathlib import Path
import json,subprocess,hashlib,datetime,time
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/point-invoice-322');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-CreateOrder-staging';POLICY='PointInvoiceEligibilityRead322'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
review=json.loads((R/'docs/point-invoice-read-permissions-review-322.json').read_text());path=R/review['candidateReadOnlyPolicy'];assert hashlib.sha256(path.read_bytes()).hexdigest()==review['candidatePolicySha256']
policy=json.loads(path.read_text());assert all(s['Action']==['dynamodb:GetItem']for s in policy['Statement'])
before=aws('lambda','get-function-configuration','--function-name',NAME);assert before['CodeSha256']==review['codeCorrection']['newHash'],'LIVE_CODE_DRIFT'
role=before['Role'].split('/')[-1];prior=aws('iam','list-role-policies','--role-name',role)['PolicyNames'];(P/'policies-before-eligibility.json').write_text(json.dumps(prior))
if POLICY in prior:assert aws('iam','get-role-policy','--role-name',role,'--policy-name',POLICY)['PolicyDocument']==policy
else:aws('iam','put-role-policy','--role-name',role,'--policy-name',POLICY,'--policy-document','file://'+str(path))
assert aws('iam','get-role-policy','--role-name',role,'--policy-name',POLICY)['PolicyDocument']==policy
checks=[]
for table,key in [('WizzCentral_RegionsDerived_staging','region_test'),('staging-AccountDeletion','BUSINESS_LIFECYCLE#MERCHANT#business_test'),('staging-AccountDeletion','ACCOUNT_LIFECYCLE#MERCHANT#owner_test')]:
 args=['iam','simulate-principal-policy','--policy-source-arn',before['Role'],'--action-names','dynamodb:GetItem','--resource-arns','arn:aws:dynamodb:us-east-1:699561669180:table/'+table,'--context-entries',json.dumps([{'ContextKeyName':'dynamodb:LeadingKeys','ContextKeyValues':[key],'ContextKeyType':'stringList'}])]
 for attempt in range(4):
  decision=aws(*args)['EvaluationResults'][0]['EvalDecision']
  if decision=='allowed':break
  time.sleep(2)
 assert decision=='allowed',(table,key,decision);checks.append({'table':table,'key':key,'action':'dynamodb:GetItem','decision':decision})
for table,key,action in [('staging-AccountDeletion','ACCOUNT_LIFECYCLE#CUSTOMER#customer_test','dynamodb:GetItem'),('staging-AccountDeletion','ACCOUNT_LIFECYCLE#MERCHANT#owner_test','dynamodb:UpdateItem'),('WizzCentral_RegionsDerived_staging','region_test','dynamodb:PutItem')]:
 decision=aws('iam','simulate-custom-policy','--policy-input-list',json.dumps(policy),'--action-names',action,'--resource-arns','arn:aws:dynamodb:us-east-1:699561669180:table/'+table,'--context-entries',json.dumps([{'ContextKeyName':'dynamodb:LeadingKeys','ContextKeyValues':[key],'ContextKeyType':'stringList'}]))['EvaluationResults'][0]['EvalDecision']
 assert decision=='implicitDeny';checks.append({'table':table,'key':key,'action':action,'newPolicyDecision':decision})
after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==before['CodeSha256']and after['Environment']==before['Environment']and after['Role']==before['Role']
assert set(aws('iam','list-role-policies','--role-name',role)['PolicyNames'])==set(prior)|{POLICY}
receipt={'status':'READ_PERMISSIONS_APPLIED_VERIFIED_HUMAN_INVOICE_RETRY_PENDING','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'function':NAME,'policyName':POLICY,'policy':policy,'userExplicitlyApproved':True,'checks':checks,'codeHashUnchanged':after['CodeSha256'],'environmentAndExistingPoliciesPreserved':True,'customerAddressOrderWalletWritesPerformed':False,'mobileUpdateRequired':False}
(R/'docs/point-invoice-read-permissions-publication-322.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print('Approved two read grants installed and verified. New policy remains read-only and merchant-scoped.')
