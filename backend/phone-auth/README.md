# Customer phone authentication (Staging)

API: https://f44z33oz55.execute-api.us-east-1.amazonaws.com/staging/auth/phone/{send,verify}

Deploy `backend/phone-auth-template.yaml` with SAM to `staging-wizzuser-phone-auth` using `Wizz_stg_UserApp`. Run `scripts/configure-cognito.py` afterwards to attach the challenge triggers and enable `ALLOW_CUSTOM_AUTH`; the script preserves existing pool/client settings and stores a private backup in the system temporary directory. Do not use this configuration for production.

The public API validates the SMS code, then creates a 90-second, single-use server proof for Cognito. Cognito issues the JWTs; the Flutter app uses its existing SessionService and token refresh flow. Direct custom-auth calls cannot send SMS or authenticate without that proof.

Existing verified phone accounts retain their Cognito subject, legacy profile ID, and balances. An unverified or ambiguous existing phone requires legacy email login and the separate authenticated phone-link flow. Newly verified numbers require a name and both consents before account creation. Their profile is keyed by Cognito subject and their canonical wallet is conditionally created with zero balance. Existing wallets are never overwritten. No automatic merging of accounts by email or phone.

Codes expire after five minutes, allow five wrong attempts, and are consumed atomically. SMS sends have a 60-second cooldown and per-phone, per-IP, and global daily quotas. Delivery uses the existing OTPIQ WhatsApp/SMS provider configuration. Credentials, SMS codes, and tokens must never be logged.

Run `node --test backend/phone-auth/*.test.cjs` from the repository root. Flutter phone-format and inbox tests run from `frontend`. Test a real existing account and a fresh number on Staging before treating the rollout as verified; unit tests do not prove SMS delivery.
