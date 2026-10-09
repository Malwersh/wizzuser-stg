# WizzUser - Staging Environment (Customer App)

## 📋 Overview
This is the **clean staging environment** for the WizzUser customer application. Contains only essential files for production deployment without test files, debug code, or development artifacts.

## 🗂️ Project Structure

```
wizzuser-stg/
├── frontend/              # Flutter customer app (Staging)
│   ├── lib/              # Clean Dart source (208 files)
│   │   ├── screens/      # 57 app screens
│   │   ├── services/     # 48 services
│   │   ├── models/       # 29 data models
│   │   ├── providers/    # 4 state providers
│   │   ├── widgets/      # 33 reusable widgets
│   │   └── config/       # Environment configs
│   ├── android/          # Android platform
│   ├── ios/              # iOS platform
│   ├── assets/           # Images, icons, sounds
│   └── pubspec.yaml      # Dependencies
│
└── backend/              # AWS SAM backend (Staging)
    ├── src/
    │   ├── functions/    # 75 Lambda functions
    │   ├── lambdas/      # Additional handlers
    │   ├── utils/        # Shared utilities
    │   ├── models/       # Data models
    │   └── config/       # Configurations
    ├── lambda/           # WebSocket processor
    ├── package.json      # Node.js dependencies
    ├── template.yaml     # AWS SAM template
    └── samconfig.toml    # SAM configuration
```

## 🎯 Environment Configuration

**Environment:** Staging (`stg`)
**AWS Region:** us-east-1
**Status:** Ready for AWS resources creation

### Required AWS Resources (To Be Created):
- [ ] Cognito User Pool: `WizzUsers-stg`
- [ ] Lambda Functions: 75 functions with `-staging` suffix
- [ ] API Gateway: Staging endpoints
- [ ] WebSocket API: Staging real-time connections
- [ ] DynamoDB Tables: With environment field = 'stg'

## 🚀 Key Features

### Customer App Features:
✅ User Registration & Authentication
✅ Browse Restaurants & Products
✅ Real-time Restaurant Availability
✅ Shopping Cart & Checkout
✅ Multiple Delivery Addresses
✅ Order Tracking (Real-time)
✅ Favorites Management
✅ Wallet & Payments (PayTabs, ZainCash)
✅ Promo Codes & Rewards
✅ Order History
✅ Push Notifications (Real-time)
✅ Multi-language Support (Arabic/English)

### Backend Services (75 Lambda Functions):
- **Auth (7):** Login, Registration, Verification, Password Reset
- **Orders (13):** Create, Track, Update, Cancel, History
- **Business (16):** Get Restaurants, Products, Categories, Availability
- **Wallet (6):** Balance, Topup, Spend, Transactions, Webhooks
- **WebSocket (6):** Connect, Disconnect, Heartbeat, Broadcast, Updates
- **Address (5):** CRUD operations, Default address
- **Favorites (3):** Add, Remove, Check status
- **Other (19):** Search, Delivery zones, Version check, etc.

## 📦 Size Comparison

- **Original Development:** ~16 GB
- **Clean Staging:** ~304 MB
- **Reduction:** 98% smaller! 🎉

## 🔧 Differences from Development

| Aspect | Development (dev) | Staging (stg) |
|--------|------------------|---------------|
| Size | ~16 GB | ~304 MB |
| Frontend Files | 190+ files | 208 clean files |
| Backend Functions | 75 + test files | 75 production files |
| Build Artifacts | .aws-sam (13GB) | ❌ Excluded |
| Test Files | ✅ Included | ❌ Removed |
| Backup Files | ✅ Included | ❌ Removed |
| Documentation | 25+ MD files | This README only |
| Environment | dev | stg |

## ✅ Cleanup Applied

The following non-essential files were **excluded** from this staging copy:
- 🚫 No build/ directory (688MB saved)
- 🚫 No .dart_tool/ directory (233MB saved)
- 🚫 No .aws-sam/ directory (13GB saved!)
- 🚫 No node_modules/ (will be installed on deployment)
- 🚫 No backup/old/test files
- 🚫 No test scripts (43 files)
- 🚫 No excessive documentation (25 MD files)

## 🏗️ Deployment Steps

### 1. Frontend Deployment
```bash
cd frontend
flutter clean
flutter pub get
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

### 2. Backend Deployment
```bash
cd backend
npm install

# Build SAM application
sam build

# Deploy to AWS (staging)
sam deploy --config-env staging --profile Wizz_staging_UserApp
```

## 📝 Configuration Files

### Frontend Environment
- `lib/config/environment.dart` - Main environment config
- `lib/config/api_config.dart` - API endpoints
- `lib/config/google_maps_config.dart` - Google Maps configuration
- `pubspec.yaml` - Flutter dependencies

### Backend Configuration
- `template.yaml` - AWS SAM infrastructure
- `samconfig.toml` - SAM deployment settings
- `package.json` - Node.js dependencies
- `src/config/` - Service configurations

## 🔒 Security Notes

Before deploying to staging:
1. Update all AWS resource IDs in configuration files
2. Create new Cognito User Pool for staging users
3. Use separate AWS profile: `Wizz_staging_UserApp`
4. Configure staging-specific API keys (Google Maps, PayTabs, etc.)
5. Set up staging DynamoDB tables with environment field
6. Update WebSocket endpoints to staging URLs
7. Configure staging payment gateway endpoints

## 📊 Lambda Functions by Category

**Authentication (7):**
- user-login, user-registration
- email-login, phone-login
- verify-email, verify-phone, resend-verification
- forgot-password, confirm-forgot-password, change-password

**Orders (13):**
- create-order, get-order, get-user-orders, get-guest-orders
- update-order-status, cancel-order, search-order-by-number
- merchant-order-status-update
- order-stream-processor, enhanced-order-stream-processor
- order-stream-merchant-notifier
- driver-assignment-api, driver-response-handler
- manual-assignment-trigger, order-scheduling

**Business/Restaurants (16):**
- get-businesses, get-business, get-businesses-status
- get-business-categories, get-business-products, get-business-working-hours
- get-category, get-category-products, get-product
- check-store-availability, store-availability
- realtime-availability, availability-broadcast
- availability-websocket-broadcast, availability-cache, availability-monitor
- business-status-stream-handler, business-status-availability-trigger
- working-hours-stream-handler

**Wallet & Payments (6):**
- wallet-balance, wallet-init
- wallet-topup, wallet-spend
- wallet-transactions
- wallet-paytabs-webhook

**WebSocket (6):**
- websocket-connect, websocket-disconnect
- websocket-default, websocket-heartbeat
- websocket-send-update
- unified-notification-sender

**User Profile (7):**
- get-user-profile, update-user-profile
- update-user-preferences, update-contact-info
- update-cognito-email

**Address Management (5):**
- get-user-addresses, get-address
- create-address, update-address, delete-address
- set-default-address

**Favorites (3):**
- add-favorite, remove-favorite
- check-favorite-status

**Other (12):**
- delivery-zones
- apply-promo-code
- merge-guest-orders

## 🛠️ Maintenance

This is a **clean copy** for staging. Do NOT add:
- Test files or debug code
- Multiple versions of the same file
- Development documentation
- Build artifacts (.aws-sam, build/, .dart_tool/)
- Deployment archives
- Temporary or backup files

For development and testing, use the original `wizzuser` directory.

## 🎯 Next Steps

1. **Create AWS Resources:**
   - Cognito User Pool for staging
   - All Lambda functions with staging config
   - DynamoDB tables with environment field
   - API Gateway + WebSocket APIs

2. **Configure Environment:**
   - Update frontend config files
   - Update backend template.yaml
   - Set environment variables

3. **Test Deployment:**
   - Deploy backend to AWS
   - Test all Lambda functions
   - Deploy frontend apps
   - Test end-to-end flows

4. **Integration Testing:**
   - Test full customer journey
   - Test real-time updates
   - Test payment flows
   - Test with other staging apps (Driver, Merchant)

---

**Created:** December 29, 2025
**Purpose:** Clean staging environment for WizzUser customer application
**Source:** wizzuser (development directory)
**Environment:** Staging (stg)
