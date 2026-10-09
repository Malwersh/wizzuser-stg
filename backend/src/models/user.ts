// User Models for DynamoDB Tables

/**
 * Temporary User Model - stored in temp_users table before verification
 */
export interface TempUser {
  tempUserId: string;           // Primary Key
  name: string;                 // Required
  phone?: string;               // Optional - for phone registration: +964XXXXXXXXX
  email?: string;               // Optional - for email registration
  password: string;             // Original password for Cognito
  birthDate?: string;           // Optional - ISO date string
  gender?: 'male' | 'female';   // Optional
  countryCode: string;          // Default: '+964'
  
  // Verification status
  phoneVerificationCode?: string;
  emailVerificationCode?: string;
  phoneVerified: boolean;
  emailVerified: boolean;
  
  // Consent flags (required)
  termsAccepted: boolean;
  privacyAccepted: boolean;
  marketingConsent?: boolean;   // Optional
  
  // Metadata
  createdAt: string;            // ISO timestamp
  updatedAt: string;            // ISO timestamp
  ttl: number;                  // Unix timestamp for auto-deletion (24 hours)
  
  // Verification attempts tracking
  phoneVerificationAttempts: number;
  emailVerificationAttempts: number;
  lastPhoneCodeSent?: string;   // ISO timestamp
  lastEmailCodeSent?: string;   // ISO timestamp
}

/**
 * Permanent User Model - stored in users table after verification
 */
export interface User {
  userId: string;               // Primary Key (Cognito User ID)
  cognitoUsername: string;      // Cognito username (phone or email)
  name: string;
  phone?: string;               // Verified phone number (if phone registration)
  email?: string;               // Verified email (if email registration)
  birthDate?: string;
  gender?: 'male' | 'female';
  countryCode: string;
  
  // Profile information
  profileImage?: string;        // S3 URL
  isActive: boolean;            // Account status
  lastLoginAt?: string;         // ISO timestamp
  
  // Consent flags
  termsAccepted: boolean;
  privacyAccepted: boolean;
  marketingConsent: boolean;
  
  // Metadata
  createdAt: string;
  updatedAt: string;
  
  // Additional fields for food app
  preferredLanguage?: string;   // 'ar' | 'en'
  addresses?: Address[];        // Delivery addresses
  paymentMethods?: PaymentMethod[];
}

/**
 * Address Model
 */
export interface Address {
  addressId: string;
  title: string;                // 'Home', 'Work', etc.
  fullAddress: string;
  latitude: number;
  longitude: number;
  isDefault: boolean;
  createdAt: string;
}

/**
 * Payment Method Model
 */
export interface PaymentMethod {
  paymentId: string;
  type: 'card' | 'cash' | 'digital_wallet';
  isDefault: boolean;
  // Additional fields based on type
  cardDetails?: {
    lastFourDigits: string;
    cardType: string;
    expiryMonth: number;
    expiryYear: number;
  };
}

/**
 * API Request/Response Models
 */

// Registration Request
export interface RegisterRequest {
  name: string;
  phone?: string;                    // Required for phone registration
  email?: string;                    // Required for email registration
  password: string;
  birthDate?: string;
  gender?: 'male' | 'female';
  countryCode?: string;
  termsAccepted: boolean;
  privacyAccepted: boolean;
  marketingConsent?: boolean;
  registrationType: 'phone' | 'email';  // New: registration type
}

// Registration Response
export interface RegisterResponse {
  success: boolean;
  message: string;
  tempUserId?: string;
  phoneVerificationRequired: boolean;
  emailVerificationRequired: boolean;
  requiresVerification?: boolean; // New: indicates if user needs to verify existing account
}

// Verification Request
export interface VerificationRequest {
  tempUserId: string;
  verificationCode?: string;  // For backward compatibility
  code?: string;              // New field name
  verificationType?: 'phone' | 'email';
}

// Verification Response
export interface VerificationResponse {
  success: boolean;
  message: string;
  userId?: string;           // Only when both phone and email (if provided) are verified
  accessToken?: string;      // JWT token
  refreshToken?: string;
}

// Update Contact Info Request
export interface UpdateContactRequest {
  tempUserId: string;
  newPhone?: string;
  newEmail?: string;
}

// Login Request
export interface LoginRequest {
  username?: string;          // Can be phone or email (legacy field)
  identifier?: string;        // Can be phone or email (new field)
  password: string;
}

// Login Response
export interface LoginResponse {
  success: boolean;
  message: string;
  user?: Partial<User>;  // Changed to Partial<User> for flexibility
  accessToken?: string;
  refreshToken?: string;
}

// Error Response
export interface ErrorResponse {
  success: false;
  error: string;
  errorCode?: string;
  details?: any;
}
