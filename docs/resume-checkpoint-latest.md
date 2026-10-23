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
