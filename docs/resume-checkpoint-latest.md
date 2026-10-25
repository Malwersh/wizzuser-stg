# Resume checkpoint — 2026-10-22

User requested saving progress and stopping until later. Read the shared checkpoint in ../whizzCentralPlatform-stg/docs/resume-checkpoint-2026-10-22-292.md before continuing.

Customer build222 and merchant build231 installed on simulators; driver profile221 on real phone. Human order ORD1792697497756 delivered and settled8500; platform goods discount500 consumed once, fixed delivery1500, driver2750, merchant payable5950 locked (not paid), platform contribution−200. Commission remains15%;27% was a hypothetical calculation only. No automatic new order or financial actions on resume. Session source changes saved in local commits; no GitHub push requested during save.


## 319 — GitHub handoff requested
User authorized publishing all session updates for colleague pull. Scope: four staging repositories on feature/malwersh/bootstrap; legacy non-staging worktrees excluded. Repository-specific Arabic handoff record: docs/github-handoff-2026-10-23.json. Current batch passed: Drivers54Node+7Python+65Flutter, Merchants6Flutter, Customers2Flutter; Central docs whitespace checked. Driver native258 installed, final demand colors secondary navy and12h ص/م. No financial operation or new AWS deployment performed for GitHub upload. Detailed commit messages and GitHub commit comments describe scope and pending work.


## 321 — General pricing, independent route and native234
Merged latest customer integration35c5a99 before edits. Existing delivery quote handler source now includes colleague storefront_route action; frontend separately caches scoped/expiring route results on pricing failures, never price/zero checkout authorization. Server skips pricing reads for route-only; malformed/missing prep/minimum do not suppress valid road distance/time. Saved order lineId/itemId/selectedOptions deserialization fixed after integration test exposed it.13Flutter tests passed; no analyzer errors/warnings, existing brace-style info. Final profile234 built successfully; attempted install failed because all paired iPhones unavailable. Generated dependency/Swift lockfiles restored, colleague signing/dependency sources preserved. Central policy CURRENTversion2 active8regions, branch overrides preserved; quote route module and hosting166 deployed. Frouj still needs genuine commercial binding; no fabricated consent, order or wallet actions. See shared central docs/general-pricing-implementation-321.json and local general-pricing-integration-321.json.


## 326 — Cart delivery label/loading and redundant request
User objected to التوصيل التقديري and pending placeholder. Unified labelرسوم التوصيل with restaurant, explicit animated loadingجارٍ حساب الرسوم… bounded withFlexible, existing scoped fresh cache shows price immediately. Removed forced storefront load on restaurant initState; existing widgets share/coalesce cache, no repeated request merely navigating matching fresh data. Basket/address changes or expiry still fetch server preview for eligibility; cart250ms debounce remains. No server route cache introduced: a new preview still obtains road route. Final checkout validation unchanged.20Flutter tests pass incl warm-cache first frame/no new request, cold loading, fast edits, scope failures. Analyzer no errors/warnings7brace infos. Simulator debug235 built, installed/launched on existing iPhone16Pro26.2 replacing233, data preserved; iPhone16older simulator left alone. No AWS, order or financial mutations. User handles commercial workflow personally; AG-000003 screenshots show approved25%GOODS_GROSS/service300/1year; do not create/edit/accept agreements on user's behalf. Report docs/cart-delivery-clarity-326.json.


## Part327 — final cash invoice and service fee
Central cash policy v1 active UP250 IQD, effective service minimum250. Existing commercial preview populates final service/total on checkout before review without persisting an attempt or consuming an offer. Required store metadata and saved address coordinates are included. Preview/confirmation still use trusted server allocation and immutable policy consent/fences. Order evidence persists base/delta/final service. Customer sees final service only. Canonical quote runtime and SAM synced. Debug simulator237 installed, data retained; commercial26 + legacy29 tests pass. See docs/cash-rounding-checkout-327.json and central docs/cash-rounding-327.json.


## Part328 — home cart circle restored
Restore home AnimatedCartBar.isExpanded=false from initial snapshot (integration f30e3b6 had selected expanded mode). Existing five-second pulse and cart navigation retained. Restaurant expanded variant uses minHeight64 instead of fixed56 to prevent Arabic two-line overflow. Twelve cart tests pass including320px and2x text. Customer simulator238 installed and launched; app data preserved. No pricing or financial changes. See docs/home-cart-restoration-328.json.


## Part329 — restaurant cart overlay and quiet add feedback
Restaurant cart lives outside Scaffold in a Stack: transparent Material restores inherited typography and removes yellow debug underlines. Navy label/store name directly on gold; count/amount badge navy. Successful direct add snackbar removed; error/different-store actions retained. Whole bar pulses subtly on any quantity increase (same dish included); badge counts units.13 cart tests pass including actual outside-Scaffold overlay,320px/2x text, repeated-unit pulse. Simulator239 installed and launched; data preserved. No financial changes. See docs/restaurant-cart-feedback-329.json.


## Part330 — restaurant cart pill matches requested reference
User requested DoorDash-style compact pill using our colors. Gold/navy restaurant bar now minimum56px at normal text scale, cart icon + centered view-cart/store label + small tinted count circle; white count/price box and displayed price removed. Accessible text can grow the bar. Quantity pulse and quiet add feedback retained.13 cart tests pass. Simulator240 installed and launched; data preserved. No pricing change. See docs/restaurant-cart-design-330.json.


## Part331 — shared early invoice and normal review cancellation
Client now warms invoice from existing home/restaurant/cart basket with saved destination, coalesces both invoice and road-quote requests, and caches bounded account/branch/address/basket/tip/benefit snapshots until server expiry. Cart shows service/total; checkout and review use the same prepared proposal and quote. Closing review is cancelled=true without toast/error/pending/order; final commit still performs existing server financial verification. Quiet foreground expiry refresh retains valid displayed result; real rejection invalidates it; unknown outcomes keep pending recovery.52 current +29 legacy Flutter tests passed;13 actual backend handler acceptance cases mocked (three new metadata/replay cases). No policy/backend deployment or real financial writes. Simulator241 installed and launched; app data preserved. See docs/shared-checkout-invoice-331.json.


## GitHub handoff and product/import delegation — 2026-10-24

User requested all four staging repos on feature/malwersh/bootstrap ready for colleague pull, with detailed commit messages and GitHub commit comments. docs/github-handoff-2026-10-24.json records repository changes, validation, pull instructions and scope. Full manual products/CSV/Excel/menu/options/images/catalog/stock/branch/versioned publish work delegated to colleague; canonical handoff docs/merchant-products-import-colleague-handoff-2026-10-24.txt in Central and Merchants. Main plan and transition/product plans mark DELEGATED_TO_COLLEAGUE, not complete. Agent must not implement a parallel importer; coordinate order/pricing/stock/COD contracts. No new AWS deployment/business action as part of upload. Next ongoing COD work remains pickup issue resolution, respecting delegated menu/item-change ownership.


### تصحيح254 — وضوح مصير الطلب بعد فك إسناد السائق
أضيف عرض البحث عن سائق بديل اعتمادًا على financialRelease وحالة الطلب وعدم وجود سائق، مع إعطاء أولوية لحالة تعذر العثور على سائق. تحفظ الإشارة في الذاكرة وتزال عند إسناد بديل. أصل الخادم أُصلح في Central عبر المضيف والمنسق الموحدين؛ الطلب ORD1792870714924 وصل تلقائيًا إلى مراجعة تعذر العثور بعد انتهاء مهلة البحث دون إلغاء. التغيير ليس إكمالًا لفحوص جاهزية الإطلاق على النظامين المؤجلة؛ إعادة الإسناد البشرية لطلب جديد بعد الإصلاح ما زالت تحتاج تجربة.


## تصحيح مرجع الأولويات — الخطة كاملة، 2026-10-24
طلب المستخدم مراجعة جميع بنود الخطة الأساسية عبر التطبيقات الأربعة، وليس استثناءاتCODأوتطبيقًامنفردًا. المرجع الموحد ../whizzCentralPlatform-stg/docs/main-plan-all-apps-priority-review-2026-10-24.json وCSVالمرافق، معالقسمالشاملبختامfinance-pricing-settlements-returns-unified-plan.md. يشمل61بندًاو127قسممواصفةوالحزم14معحالةودليلومتبقٍوأولوية؛ الموجودلايعادبناؤهوغيرالمثبتلايسمىمكتملًا. المنتجاتوالقوائموكلنطاقالاستيرادوالمخزونالمحالللزميلمستثنىمنتنفيذنا،وليسباقيتطبيقالمطعم. يبدأالعملمنسدالضرورياتالتشغيليةحسبالتبعياتعبرالجميع،ثمفحوصالإطلاقAndroid+iPhoneبعدإكمالالتشغيلواختباره.


## شحن محفظة السائق وزين كاش — 260

مرجع الدليل الكامل في Central-stg: `docs/zaincash-readiness-260.json`. جُهّز الوصل والدفع المباشر وإعدادات الأسرار والتجربة المحددة والتفعيل العام والمطابقة والاستعادة. LIVE وUAT الجديدان معطلان؛ بيانات UAT مهيأة ومصادقة OAuth ناجحة دون دفع. القبول البشري وبيانات الشركة والإشعار الفعلي باقية، فلا إعلان اكتمال F02 أو خطة التطبيقات كلها. الطلبات للزبون نقدية، وصرف المطعم الحالي و6000 المعلق لا يتغيران. المنتجات/import للزميل، وبقية أولويات الدفعة محفوظة.

Transfer visibility batch270: Release248 installed on real iMohammed. Existing CONFIG#TRANSFERS.enabled gates transfer entry/actions with fail-closed refresh on resume and30s polling. Balance/history and uncertain-attempt recovery remain available; no commission and no actual transfer created. DRIVER additionally reads posted cancellation entitlement+matching case operation from Holds; ORD1792849495126 has500IQD already credited, now shown as compensation, not unknown delivery earnings. Missing proof differs from known pending review. Central evidence docs/trip-transfer-controls-270.json. User confirms no payment license or partner transfer contract: public money-transfer classification and commission need Iraqi legal/provider review before launch.


### تقييم الزبون283
بموافقة المستخدم دُمجت شاشة وخدمة واختبارات تقييم زميله من الفرع 30dc40f1df8f89a952ff6803a458f5ffc1b367f8 دمجًا انتقائيًا مع تعديل زر الطلب المسلّم وحقول متوسط المطعم وعدد التقييمات في النموذج والتخزين. 14اختبارًا ناجحًا وفحص الملفات دون مشاكل. لم يُنشأ أي تقييم أو طلب. بناء Release283 جارٍ؛ اختبار المستخدم بتقييم حقيقي بعد التسليم ما زال غير منفذ. دليل `docs/customer-rating-integration-283.json`.

تحديث283: اكتمل بناء وتثبيت وتشغيل تطبيق الزبون Release283 على iMohammed دون حذف التطبيق. اختبارات14 ناجحة. انتظار تجربة تقييم حقيقية بعد التسليم؛ لم يُنشأ طلب أو تقييم آلي.


### 284 — الحد الأدنى للسلة
تعطيل زر متابعة الطلب عندما يكون مجموع الأصناف أقل من الحد الأدنى المعروف، بلون رمادي واضح مع بقاء المبلغ المتبقي. نجح اختبار بلوغ الحد وتقليل الكمية بعده. مجموعة السلة11 ناجحة و3 فحوص رسوم توصيل فاشلة ثبتت أيضًا دون تغيير الزر؛ ليست حالة مرور كامل. تحديث المحاكي قيد البناء. دليل `docs/cart-minimum-button-284.json`.


### تحقق تقييم حقيقي بعد دمج283
أرسل المستخدم تقييمًا حقيقيًا: المطعم4 والسائق5 للطلب96cd4249-41af-5ebb-885a-d7dae2c321d0. القراءة القوية أكدت السجل الأصلي ومتوسط السائق5/5 وعدد1 ومجموع5 وملفه المطابق، ووجود السجل في فهرس281. لا كتابة من الوكيل. هذا يثبت تقديم التقييم وتجميع السائق فقط؛ عرض الزبون/المطعم وواجهة السائق بعد تحديثها وسيناريوهات المراجعة لا تزال منفصلة. دليل `docs/customer-real-rating-verification-284.json`.


### 285 — قائمة الحذف وربط تقييم المطعم
أعيد تنسيق تأكيد حذف الطبق RTL بأيقونة48 وأزرار أصغر وألوان الأصفر والكحلي. تحديث285 مثبت ومشغّل على محاكي الزبون. تدقيق حي: قائمة المطاعم كانت محدثة، لكن دالة التفاصيل مساعدها قديم وتُرجعnull للتقييم وعدده رغم متوسط4 وعدد1 في السجل. تجهيز إصلاح مساعد واحد فقط داخل الحزمتين دون تغيير IAM أوإعدادات أو بيانات؛ النشر جارٍ. نموذجreviews والخريطة500+ صُححا، وتفاصيل المطعم تجلب تقييمًا حديثًا عند الفتح/العودة. اختبارات6 خادم و14 تطبيق ناجحة. دليل `docs/restaurant-rating-and-cart-sheet-285.json`.

إغلاق285: نُشر المساعد فقط في GetBusinesses/GetBusiness مع CodeSHA موثق وإعدادات محفوظة. طلباHTTPعامان بعد النشر أكدا للمطعم الحقيقي rating4 وreviewCount1 في القائمة والتفاصيل. لم تتغير أي بيانات تقييم أوصلاحيات أوإعدادات مالية. تحديث285 مشغّل على المحاكي. القبول البصري اليدوي لم يُسجّل كناجح.


### 287 — عرض التقييم غير المتوفر
طلب المستخدم شرطة بدل0.0 للمطعم والسائق. توحيد تسميات العرض إلى— مع إبقاء القيم الرقمية الداخلية للفرز دون تعديل التقييمات. صُحح نص500+ ثابت آخر في بطاقة الخريطة إلى العدد الفعلي إن كان موجبًا. اختبارات16زبون و9سائق ناجحة. بناء محاكي الزبون وRelease287للسائق جارٍ. دليل `docs/unrated-display-287.json`.

إغلاق287: نجح بناء وتثبيت وتشغيل الزبون287على المحاكي والسائقRelease287علىiMohammed. اختبارات25ناجحة،لا تعديل بيانات تقييم.
