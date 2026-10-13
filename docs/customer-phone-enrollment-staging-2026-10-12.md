# Customer phone enrollment on Staging

The existing email/password account keeps its Cognito sub and wallet. The former change-phone UI only delayed and displayed success; it is replaced by a real authenticated phone-link screen, accessible from account settings and the transfer wallet.

The new staging-wizzuser-phone-link stack uses the existing OTP provider secret and a separate encrypted session table. Access tokens are validated live by Cognito GetUser and restricted to the customer pool/client; enrollment requires authentication within 15 minutes. Codes are HMAC-protected, expire after 5 minutes, allow 5 attempts, bind to the signed-in principal and active session, and are consumed conditionally once. Send limits enforce cooldown plus account/IP/global quotas. Another account's phone cannot be reassigned by this API.

After verification the existing Cognito identity is updated with the canonical E.164 phone and verified flag. A legacy profile is synchronized only when its stored Cognito username matches the trusted identity or verified email. The body cannot select a target user ID. Transfer recipient lookup now requires a verified customer phone and an active central wallet.

Validation: 9 mocked enrollment/identity tests, 78 wallet tests, targeted Dart analysis and iOS simulator build passed. Live unauthenticated status/send/verify calls return 401. SMS delivery and recipient lookup after actual code verification remain interactive checks; no test SMS was sent by tools.

This is phone enrollment for existing accounts. A complete phone-only signup/login flow, including safe recovery/linking of existing email accounts, is not implemented in this change. Email/password login remains available.
