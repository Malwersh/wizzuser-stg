import pathlib,zipfile,copy,hashlib,json
p=pathlib.Path('/private/tmp/checkout-267');name='_discount_review/user-create-order/index.js';z=zipfile.ZipFile(p/'writer-base.zip');s=z.read(name).decode();before=s
old='''          for (const pk of ["ACCOUNT_LIFECYCLE#MERCHANT#" + branch.ownerId, "BUSINESS_LIFECYCLE#MERCHANT#" + branch.businessId]) {
            const lifecycleKey = { pk, sk: "META" };
            const state3 = await db.send(new lib_dynamodb_1.GetCommand({ TableName: L, Key: lifecycleKey, ConsistentRead: true }));
            if (state3.Item)
              return fail("DELIVERY_POLICY_AUTHORITY_REVOKED");
            fences.push({ ConditionCheck: { TableName: L, Key: lifecycleKey, ConditionExpression: "attribute_not_exists(pk)" } });
          }'''
new='''          const lifecycleChecks = ["ACCOUNT_LIFECYCLE#MERCHANT#" + branch.ownerId, "BUSINESS_LIFECYCLE#MERCHANT#" + branch.businessId].map(pk => ({ ConditionCheck: { TableName: L, Key: {pk, sk:"META"}, ConditionExpression: "attribute_not_exists(pk)" } }));
          if (options.lifecycleReadMode === "CONDITION_CHECK") {
            try { await db.send(new lib_dynamodb_1.TransactWriteCommand({TransactItems:lifecycleChecks})); }
            catch(e) {
              if(e?.name === "TransactionCanceledException" && e?.CancellationReasons?.some(r=>r.Code === "ConditionalCheckFailed")) return fail("DELIVERY_POLICY_AUTHORITY_REVOKED");
              return fail();
            }
          } else {
            for (const check of lifecycleChecks) {
              const state = await db.send(new lib_dynamodb_1.GetCommand({TableName:L,Key:check.ConditionCheck.Key,ConsistentRead:true}));
              if(state.Item) return fail("DELIVERY_POLICY_AUTHORITY_REVOKED");
            }
          }
          fences.push(...lifecycleChecks);'''
replacements=[(old,new),('function createStagingDeliveryFundingReader(options) {\n      const { db } = options, now = options.now ?? Date.now;', 'function createStagingDeliveryFundingReader(options) {\n      const { db } = options, now = options.now ?? Date.now;\n      if(options.lifecycleReadMode !== undefined && !["GET","CONDITION_CHECK"].includes(options.lifecycleReadMode)) return fail();'),('const reader = (0, deliveryFundingReader_1.createStagingDeliveryFundingReader)({ db, now });','const reader = (0, deliveryFundingReader_1.createStagingDeliveryFundingReader)({ db, now, lifecycleReadMode: options.lifecycleReadMode });'),('''? createStagingDeliveryPromotionSelection({
        db: dynamoDb,''','''? createStagingDeliveryPromotionSelection({
        db: dynamoDb, lifecycleReadMode: "CONDITION_CHECK",''')]
replacements += [('statusCode: error3.statusCode || 500,','statusCode: error3.statusCode || (error3.name === "DeliveryFundingReaderError" ? 503 : 500),'), ('["BENEFIT_EXHAUSTED", "BENEFIT_EXPIRED",','["DELIVERY_POLICY_UNAVAILABLE", "DELIVERY_POLICY_AUTHORITY_REVOKED", "DELIVERY_POLICY_HISTORY_MISMATCH", "BENEFIT_EXHAUSTED", "BENEFIT_EXPIRED",')]
for a,b in replacements:
 assert s.count(a)==1,(a[:100],s.count(a));s=s.replace(a,b,1)
(p/'writer-candidate.js').write_text(s)
with zipfile.ZipFile(p/'writer-candidate.zip','w',zipfile.ZIP_DEFLATED)as out:
 for e in z.infolist():out.writestr(copy.copy(e),s.encode()if e.filename==name else z.read(e.filename))
with zipfile.ZipFile(p/'writer-candidate.zip')as out:
 assert z.namelist()==out.namelist();assert all(z.read(n)==out.read(n)for n in z.namelist()if n!=name)
(p/'patch.json').write_text(json.dumps({'changedFile':name,'boundedReplacements':6,'unrelatedEntriesPreserved':True,'iamChanged':False,'sourceSha256':hashlib.sha256(before.encode()).hexdigest(),'candidateSha256':hashlib.sha256(s.encode()).hexdigest()},indent=2))
print('Prepared bounded lifecycle guard repair; no permission/configuration or business data changes')
