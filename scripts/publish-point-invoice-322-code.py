"""Code-only correction. Does not grant the separately approval-blocked IAM reads."""
from pathlib import Path
import subprocess,json,zipfile,copy,hashlib,base64,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/point-invoice-322');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-CreateOrder-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'fail 0'in (P/'node-tests.log').read_text()and 'fail 0'in (P/'compatibility-tests.log').read_text()
c=json.loads((P/'create.config.private.json').read_text());live=aws('lambda','get-function-configuration','--function-name',NAME);assert live['CodeSha256']==c['CodeSha256']and live['Environment']==c['Environment'],'LIVE_DRIFT'
assert digest((P/'create.original.zip').read_bytes())==c['CodeSha256']
entry='functions/create-order/point-order-handler-321.js';out=P/'create.candidate.zip'
with zipfile.ZipFile(P/'create.original.zip')as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 assert entry in z.namelist()
 for i in z.infolist():w.writestr(copy.copy(i),(P/'point-order-handler-322.js').read_bytes()if i.filename==entry else z.read(i.filename))
with zipfile.ZipFile(P/'create.original.zip')as z,zipfile.ZipFile(out)as w:assert all(z.read(n)==w.read(n)for n in z.namelist()if n!=entry)
bucket='wizz-regions-artifacts-staging-699561669180';key='region-consumers/322/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
aws('lambda','update-function-code','--function-name',NAME,'--revision-id',live['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes())and after['Environment']==c['Environment']and after['Role']==c['Role']
receipt={'status':'CODE_CORRECTION_PUBLISHED_NEW_IAM_READS_NOT_APPLIED_AWAITING_APPROVAL','date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'name':NAME,'beforeHash':c['CodeSha256'],'hash':after['CodeSha256'],'changedEntryOnly':entry,'legacyFinancialBundleAndRootUnchanged':True,'environmentAndRoleUnchanged':True,'newPermissionsApplied':False,'businessWritesPerformed':False,'tests':{'pointBoundaryAndRealEngine':5,'existingFinancialCompatibility':50,'candidateIAMPositiveAndNegativeSimulation':6},'reason':'Allow real ConditionCheck-only read transactions while retaining ephemeral point/quote isolation; block all state-changing operations.'}
(R/'docs/point-invoice-code-correction-322.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print('Code-only correction published. New IAM read permissions remain unapplied pending explicit approval.')
