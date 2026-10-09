// PayTabs Configuration for Iraqi Dinar (IQD)
const PAYTABS_CONFIG = {
    // Environment settings
    environment: 'test', // 'test' or 'production'
    
    // Test environment URLs
    test: {
        baseUrl: 'https://secure.paytabs.com',
        serverKey: 'SWJ92NRMM9-JLM2LNM92Z-MTZRDMKZL2',
        clientKey: 'CMK2QD-KPMQ6B-NMBQNP-M79BHV',
        profileId: '166045',
        merchantEmail: 'moh.al.daash@gmail.com'
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
    
    // Webhook URLs (environment specific)
    // NOTE: Do not hardcode /dev endpoints inside staging code.
    // Provide PAYTABS_WEBHOOK_BASE_URL at deploy-time, e.g.:
    //   https://<api-id>.execute-api.<region>.amazonaws.com/staging
    webhooks: {
        test: {
            callback: '',
            return: ''
        },
        production: {
            callback: 'https://your-production-domain.com/wallet/paytabs/callback',
            return: 'https://your-production-domain.com/wallet/paytabs/return'
        }
    },
    
    // Get current configuration based on environment
    getCurrent() {
        const env = this.environment;

        // Inject webhook URLs for non-production via env var
        if (env !== 'production') {
            const base = (process.env.PAYTABS_WEBHOOK_BASE_URL || '').replace(/\/$/, '');
            if (!base) {
                throw new Error('Missing PAYTABS_WEBHOOK_BASE_URL for PayTabs webhooks');
            }
            this.webhooks[env] = {
                callback: `${base}/wallet/paytabs/callback`,
                return: `${base}/wallet/paytabs/return`
            };
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
