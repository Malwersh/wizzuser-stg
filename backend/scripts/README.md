Scripts

- `copy-dynamodb-tables.js`
  - Copies DynamoDB tables from a source AWS profile/env to a target profile/env.
  - Default allowlist: users/addresses/favorites only.
  - Wallet-related tables are intentionally excluded (legacy system).

Examples

Dry-run (no writes):
- `node scripts/copy-dynamodb-tables.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --source-env dev --target-env staging`

Write (copies items):
- `node scripts/copy-dynamodb-tables.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --source-env dev --target-env staging --write`

Limit items (safe testing):
- `node scripts/copy-dynamodb-tables.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --source-env dev --target-env staging --write --max-items 100`

Include sensitive tables (NOT recommended unless needed):
- `node scripts/copy-dynamodb-tables.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --source-env dev --target-env staging --write --include-sensitive`

Auto-map (all apps) with safe defaults (dry-run):
- `node scripts/copy-dynamodb-auto.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp`

Auto-map, but only specific table families (recommended first pass):
- `node scripts/copy-dynamodb-auto.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --include '^(WhizzMerchants_|WizzCentral_Regions$|WizzCentral_Region.*_dev$|order-receiver-.*-dev$|WaveOffers$|WizzOrders$)'`

Auto-map write (after you review dry-run):
- `node scripts/copy-dynamodb-auto.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --include '^(WhizzMerchants_|WizzCentral_Regions$|WizzCentral_Region.*_dev$)' --write --max-items 500`

Auto-map write but allow index/GSI differences (only requires matching primary key types):
- `node scripts/copy-dynamodb-auto.js --source-profile Wizz_dev_UserApp --target-profile Wizz_stg_UserApp --include '^(WhizzMerchants_|WizzCentral_Regions$|WizzCentral_Region.*_dev$)' --write --allow-index-mismatch`
