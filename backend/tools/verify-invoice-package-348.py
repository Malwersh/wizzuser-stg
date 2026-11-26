"""Preflight owned relative dependencies and direct shared exports in a Lambda zip."""
import json,pathlib,posixpath,re,sys,zipfile
package=zipfile.ZipFile(sys.argv[1]);names=set(package.namelist());entry='functions/create-order/index.js';source=package.read(entry).decode();failures=[]
for module,field in sorted(set(re.findall(r"require\(['\"](\.\./shared/[^'\"]+)['\"]\)\.([A-Za-z_$][\w$]*)",source))):
 target=posixpath.normpath(posixpath.join(posixpath.dirname(entry),module+'.js'))
 if target not in names:failures.append({'module':target,'issue':'missing module'});continue
 exports=re.findall(r'module\.exports\s*=\s*\{([^;]+)\}',package.read(target).decode(),re.S)
 if not exports or not re.search(r'\b'+re.escape(field)+r'\b',exports[-1]):failures.append({'module':target,'export':field,'issue':'missing export'})
source_root=pathlib.Path(__file__).resolve().parents[1]/'src';pending=[entry];seen=set()
while pending:
 item=pending.pop()
 if item in seen:continue
 seen.add(item)
 for relative in set(re.findall(r"require\(['\"](\.[^'\"]+)['\"]\)",package.read(item).decode(errors='replace'))):
  target=posixpath.normpath(posixpath.join(posixpath.dirname(item),relative));choices=[target,target+'.js',target+'/index.js',target+'.json'];found=next((p for p in choices if p in names),None)
  if not found and any((source_root/p).is_file() for p in choices):failures.append({'from':item,'module':target,'issue':'missing owned dependency'})
  if found and found.endswith('.js') and found.startswith('functions/shared/'):pending.append(found)
print(json.dumps({'pass':not failures,'checkedOwnedModules':len(seen),'failures':failures},indent=2))
if failures:sys.exit(1)
