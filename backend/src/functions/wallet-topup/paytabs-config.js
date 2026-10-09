// PayTabs Configuration for Iraqi Dinar (IQD) - Last Updated: August 7, 2025
// Integration Type: Hosted Payment Pages (Recommended for Flutter Web + Mobile)
// Profile: 166045 - WizzGo (Test Environment)
// Documentation: Based on PayTabs API documentation provided by user
function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

const PAYTABS_CONFIG = {
    // Environment settings - UPDATED FOR SANDBOX
    environment: 'test', // 'test' or 'production'
    
    // Test environment URLs - SANDBOX ENVIRONMENT (Iraq)
    test: {
        baseUrl: 'https://secure-iraq.paytabs.com',
        serverKey: process.env.PAYTABS_SERVER_KEY, // from env/SSM
        clientKey: process.env.PAYTABS_CLIENT_KEY, // from env/SSM
        sdkKey: process.env.PAYTABS_SDK_KEY, // from env/SSM
        profileId: process.env.PAYTABS_PROFILE_ID, // from env/SSM
        merchantEmail: process.env.PAYTABS_MERCHANT_EMAIL,
        // Test cards from PayTabs documentation 2025 - Updated test cards
        testCards: {
            // 3D Enrolled cards (will redirect for authentication)
            '4000000000000002': { scheme: 'Visa', cvv: '123', enrolled: true },
            '4012001036983332': { scheme: 'Visa', cvv: '530', enrolled: true },
            '5498383801606532': { scheme: 'MasterCard', cvv: '977', enrolled: true },
            '5200000000000007': { scheme: 'MasterCard', cvv: '977', enrolled: true },
            // Non-3D cards (direct processing) - PayTabs recommended
            '4111111111111111': { scheme: 'Visa', cvv: '123', enrolled: false, recommended: true },
            '5200000000000114': { scheme: 'MasterCard', cvv: '977', enrolled: false },
            // Additional PayTabs 2025 test cards
            '4242424242424242': { scheme: 'Visa', cvv: '123', enrolled: false }, // Standard test card
            '5555555555554444': { scheme: 'MasterCard', cvv: '123', enrolled: false },
            // Iraqi local test cards (if available)
            '4111111111111111': { scheme: 'Visa', cvv: '123', enrolled: false, description: 'PayTabs Iraq Test Card' }
        },
        // Session timeout in seconds (45 minutes - increased from 30)
        sessionTimeout: 2700,
        // Enhanced settings based on PayTabs documentation v2025
        enhancedSettings: {
            hide_shipping: true,      // Makes shipping_details optional (supported)
            framed: true,             // Enable for WebView/iframe support (recommended for mobile apps)
            theme: 'light',
            payment_methods: 'all',   // Support all available payment methods
            managed_form: false,      // Use hosted payment pages approach
            tokenise: 0,              // Disable tokenization for sandbox (set to 1 for production)
            // New PayTabs 2025 parameters
            session_timeout: 2700,    // 45 minutes session timeout
            auto_return: true,        // Auto return after payment completion
            enhanced_security: true   // Enable enhanced security features
        }
    },
    
    // Production environment URLs (to be updated when ready)
    production: {
        baseUrl: 'https://secure-iraq.paytabs.com',
        serverKey: 'YOUR_PRODUCTION_SERVER_KEY',
        clientKey: 'YOUR_PRODUCTION_CLIENT_KEY',
        profileId: 'YOUR_PRODUCTION_PROFILE_ID',
        merchantEmail: 'moh.al.daash@gmail.com'
    },
    
    // Default settings
    defaults: {
        currency: 'IQD',
        country: 'IQ',
        language: 'ar',
        tranType: 'sale',
        tranClass: 'ecom'
    },
    
    // Webhook URLs (environment specific) - WizzUser endpoints
    webhooks: {
        test: {
            callback: process.env.PAYTABS_CALLBACK_URL,
            return: process.env.PAYTABS_RETURN_URL
        },
        production: {
            callback: 'https://your-wizzuser-production-domain.com/wallet/paytabs/callback',
            return: 'https://your-wizzuser-production-domain.com/wallet/paytabs/return'
        }
    },
    
    // Get current configuration based on environment
    getCurrent() {
        const env = this.environment;
        console.log(`[PayTabs Config] Environment: ${env}`);

        if (env === 'test') {
            requireEnv('PAYTABS_SERVER_KEY');
            requireEnv('PAYTABS_CLIENT_KEY');
            requireEnv('PAYTABS_SDK_KEY');
            requireEnv('PAYTABS_PROFILE_ID');
            requireEnv('PAYTABS_MERCHANT_EMAIL');
            requireEnv('PAYTABS_CALLBACK_URL');
            requireEnv('PAYTABS_RETURN_URL');
        }
        
        const config = {
            ...this[env],
            ...this.defaults,
            webhooks: this.webhooks[env]
        };
        
        // Log safe, non-secret info only
        console.log(`[PayTabs Config] baseUrl: ${config.baseUrl}`);
        
        return config;
    },
    
    // Currency formatting for IQD
    formatCurrency(amount) {
        return `${Math.round(amount).toLocaleString('ar-IQ')} د.ع`;
    },
    
    // Validate amount for IQD (minimum 1000 IQD)
    validateAmount(amount) {
        const minAmount = 1000; // Minimum 1000 IQD
        const maxAmount = 10000000; // Maximum 10M IQD
        
        if (amount < minAmount) {
            return {
                valid: false,
                message: `الحد الأدنى للشحن هو ${this.formatCurrency(minAmount)}`
            };
        }
        
        if (amount > maxAmount) {
            return {
                valid: false,
                message: `الحد الأقصى للشحن هو ${this.formatCurrency(maxAmount)}`
            };
        }
        
        return { valid: true };
    },
    
    // Get suggested amounts for IQD
    getSuggestedAmounts() {
        return [
            5000,    // 5,000 IQD
            10000,   // 10,000 IQD
            25000,   // 25,000 IQD
            50000,   // 50,000 IQD
            100000,  // 100,000 IQD
            250000,  // 250,000 IQD
            500000   // 500,000 IQD
        ];
    }
};

module.exports = PAYTABS_CONFIG;
