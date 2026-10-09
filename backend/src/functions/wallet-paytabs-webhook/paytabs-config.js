// PayTabs Configuration for Iraqi Dinar (IQD)
function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

const PAYTABS_CONFIG = {
    // Environment settings
    environment: 'test', // 'test' or 'production'
    
    // Test environment URLs
    test: {
        baseUrl: 'https://secure.paytabs.com',
        serverKey: process.env.PAYTABS_SERVER_KEY,
        clientKey: process.env.PAYTABS_CLIENT_KEY,
        profileId: process.env.PAYTABS_PROFILE_ID,
        merchantEmail: process.env.PAYTABS_MERCHANT_EMAIL
    },
    
    // Production environment URLs (to be updated when ready)
    production: {
        baseUrl: 'https://secure.paytabs.com',
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
        if (env === 'test') {
            requireEnv('PAYTABS_SERVER_KEY');
            requireEnv('PAYTABS_CLIENT_KEY');
            requireEnv('PAYTABS_PROFILE_ID');
            requireEnv('PAYTABS_MERCHANT_EMAIL');
            requireEnv('PAYTABS_CALLBACK_URL');
            requireEnv('PAYTABS_RETURN_URL');
        }
        return {
            ...this[env],
            ...this.defaults,
            webhooks: this.webhooks[env]
        };
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
