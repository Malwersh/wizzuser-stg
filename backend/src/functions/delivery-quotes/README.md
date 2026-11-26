# Delivery quote Lambda runtime

`index.js` loads `runtime.js`, a generated bundle excluded from Git. The source of that bundle is `whizzCentralPlatform-stg/backend/wallet-service/src/deliveryQuoteRuntime.ts`.

Keep the repositories as siblings. From `whizzCentralPlatform-stg`, run:

```sh
npm ci --prefix backend/wallet-service
node scripts/build-delivery-quote-runtime.cjs
node scripts/build-delivery-quote-runtime.cjs --check
```

Generate the bundle before testing this handler or preparing a deployment. Generating it does not deploy anything. Keep the deployment gates in the finance plan and release preparation tools; do not activate incomplete financial flows.
