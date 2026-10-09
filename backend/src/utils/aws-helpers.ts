// AWS Services Helper Functions

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, GetCommand, UpdateCommand, DeleteCommand, QueryCommand, ScanCommand } from '@aws-sdk/lib-dynamodb';
import { CognitoIdentityProviderClient, AdminCreateUserCommand, AdminSetUserPasswordCommand, AdminInitiateAuthCommand, AdminConfirmSignUpCommand, AdminGetUserCommand, AdminDeleteUserCommand, ListUsersCommand, SignUpCommand, ConfirmSignUpCommand } from '@aws-sdk/client-cognito-identity-provider';
import { SNSClient, PublishCommand } from '@aws-sdk/client-sns';
import { SESClient, SendEmailCommand } from '@aws-sdk/client-ses';
import { createHash, randomBytes } from 'crypto';
import { TempUser, User } from '../models/user';

// Initialize AWS clients
const dynamoClient = DynamoDBDocumentClient.from(
  new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' }),
  {
    marshallOptions: {
      removeUndefinedValues: true,
    },
  }
);
const cognitoClient = new CognitoIdentityProviderClient({ region: process.env.AWS_REGION || 'us-east-1' });
const snsClient = new SNSClient({ region: process.env.AWS_REGION || 'us-east-1' });
const sesClient = new SESClient({ region: process.env.AWS_REGION || 'us-east-1' });

// Environment variables
const USERS_TABLE = process.env.USERS_TABLE!;
const TEMP_USERS_TABLE = process.env.TEMP_USERS_TABLE!;
const USER_POOL_ID = process.env.USER_POOL_ID!;
const USER_POOL_CLIENT_ID = process.env.USER_POOL_CLIENT_ID!;

/**
 * DynamoDB Helper Functions
 */

export class DynamoHelper {
  // Temp Users Table Operations
  static async createTempUser(tempUser: TempUser): Promise<void> {
    const command = new PutCommand({
      TableName: TEMP_USERS_TABLE,
      Item: tempUser
    });
    await dynamoClient.send(command);
  }

  static async getTempUser(tempUserId: string): Promise<TempUser | null> {
    const command = new GetCommand({
      TableName: TEMP_USERS_TABLE,
      Key: { tempUserId }
    });
    const result = await dynamoClient.send(command);
    return result.Item as TempUser || null;
  }

  static async updateTempUser(tempUserId: string, updates: Partial<TempUser>): Promise<void> {
    const updateExpression: string[] = [];
    const expressionAttributeNames: Record<string, string> = {};
    const expressionAttributeValues: Record<string, any> = {};

    for (const [key, value] of Object.entries(updates)) {
      updateExpression.push(`#${key} = :${key}`);
      expressionAttributeNames[`#${key}`] = key;
      expressionAttributeValues[`:${key}`] = value;
    }

    const command = new UpdateCommand({
      TableName: TEMP_USERS_TABLE,
      Key: { tempUserId },
      UpdateExpression: `SET ${updateExpression.join(', ')}`,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: expressionAttributeValues
    });

    await dynamoClient.send(command);
  }

  static async deleteTempUser(tempUserId: string): Promise<void> {
    const command = new DeleteCommand({
      TableName: TEMP_USERS_TABLE,
      Key: { tempUserId }
    });
    await dynamoClient.send(command);
  }

  // Check for existing temp user by phone
  static async getTempUserByPhone(phone: string): Promise<TempUser | null> {
    const command = new ScanCommand({
      TableName: TEMP_USERS_TABLE,
      FilterExpression: 'phone = :phone',
      ExpressionAttributeValues: { ':phone': phone }
    });
    const result = await dynamoClient.send(command);
    return result.Items?.[0] as TempUser || null;
  }

  // Check for existing temp user by email
  static async getTempUserByEmail(email: string): Promise<TempUser | null> {
    const command = new ScanCommand({
      TableName: TEMP_USERS_TABLE,
      FilterExpression: 'email = :email',
      ExpressionAttributeValues: { ':email': email }
    });
    const result = await dynamoClient.send(command);
    return result.Items?.[0] as TempUser || null;
  }

  // Users Table Operations
  static async createUser(user: User): Promise<void> {
    const command = new PutCommand({
      TableName: USERS_TABLE,
      Item: user
    });
    await dynamoClient.send(command);
  }

  static async getUser(userId: string): Promise<User | null> {
    const command = new GetCommand({
      TableName: USERS_TABLE,
      Key: { userId }
    });
    const result = await dynamoClient.send(command);
    return result.Item as User || null;
  }

  static async getUserByEmail(email: string): Promise<User | null> {
    const command = new QueryCommand({
      TableName: USERS_TABLE,
      IndexName: 'email-index',
      KeyConditionExpression: 'email = :email',
      ExpressionAttributeValues: { ':email': email }
    });
    const result = await dynamoClient.send(command);
    return result.Items?.[0] as User || null;
  }

  static async getUserByPhone(phone: string): Promise<User | null> {
    const command = new QueryCommand({
      TableName: USERS_TABLE,
      IndexName: 'phone-index',
      KeyConditionExpression: 'phone = :phone',
      ExpressionAttributeValues: { ':phone': phone }
    });
    const result = await dynamoClient.send(command);
    return result.Items?.[0] as User || null;
  }

  static async updateUser(userId: string, updates: Partial<User>): Promise<void> {
    const updateExpression: string[] = [];
    const expressionAttributeNames: Record<string, string> = {};
    const expressionAttributeValues: Record<string, any> = {};

    for (const [key, value] of Object.entries(updates)) {
      updateExpression.push(`#${key} = :${key}`);
      expressionAttributeNames[`#${key}`] = key;
      expressionAttributeValues[`:${key}`] = value;
    }

    const command = new UpdateCommand({
      TableName: USERS_TABLE,
      Key: { userId },
      UpdateExpression: `SET ${updateExpression.join(', ')}`,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: expressionAttributeValues
    });

    await dynamoClient.send(command);
  }

  // Password Reset Tokens Table Operations
  static async createPasswordResetToken(resetData: {
    resetToken: string;
    userId: string;
    phone: string;
    verificationCode: string;
    isUsed: boolean;
    createdAt: number;
    expiresAt: number;
    ttl: number;
  }): Promise<void> {
    const command = new PutCommand({
      TableName: 'PasswordResetTokens', // We'll need to create this table
      Item: resetData
    });
    await dynamoClient.send(command);
  }

  static async getPasswordResetToken(resetToken: string): Promise<any | null> {
    const command = new GetCommand({
      TableName: 'PasswordResetTokens',
      Key: { resetToken }
    });
    const result = await dynamoClient.send(command);
    return result.Item || null;
  }

  static async updatePasswordResetToken(resetToken: string, updates: any): Promise<void> {
    const updateExpression: string[] = [];
    const expressionAttributeNames: Record<string, string> = {};
    const expressionAttributeValues: Record<string, any> = {};

    for (const [key, value] of Object.entries(updates)) {
      updateExpression.push(`#${key} = :${key}`);
      expressionAttributeNames[`#${key}`] = key;
      expressionAttributeValues[`:${key}`] = value;
    }

    const command = new UpdateCommand({
      TableName: 'PasswordResetTokens',
      Key: { resetToken },
      UpdateExpression: `SET ${updateExpression.join(', ')}`,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: expressionAttributeValues
    });
    await dynamoClient.send(command);
  }

  static async deletePasswordResetToken(resetToken: string): Promise<void> {
    const command = new DeleteCommand({
      TableName: 'PasswordResetTokens',
      Key: { resetToken }
    });
    await dynamoClient.send(command);
  }
}

/**
 * Cognito Helper Functions
 */
export class CognitoHelper {
  static async createCognitoUser(primaryIdentifier: string, email: string | undefined, password: string, name: string, phone?: string): Promise<string> {
    // Determine if registration is by phone or email
    const isPhoneRegistration = phone && Utils.isValidPhone(phone);
    const username = isPhoneRegistration ? phone : primaryIdentifier;
    
    const userAttributes = [
      { Name: 'name', Value: name }
    ];

    // Add phone attributes if phone registration
    if (isPhoneRegistration && phone) {
      userAttributes.push(
        { Name: 'phone_number', Value: phone },
        { Name: 'phone_number_verified', Value: 'true' }
      );
    }

    // Add email attributes if email is provided
    if (email) {
      userAttributes.push(
        { Name: 'email', Value: email },
        { Name: 'email_verified', Value: 'true' }
      );
    }

    // Create user with permanent password directly
    const createCommand = new AdminCreateUserCommand({
      UserPoolId: USER_POOL_ID,
      Username: username,
      MessageAction: 'SUPPRESS', // Don't send welcome email
      UserAttributes: userAttributes
    });

    await cognitoClient.send(createCommand);

    // Set the user's permanent password immediately
    const setPasswordCommand = new AdminSetUserPasswordCommand({
      UserPoolId: USER_POOL_ID,
      Username: username,
      Password: password,
      Permanent: true
    });

    await cognitoClient.send(setPasswordCommand);

    return username;
  }

  static async authenticateUser(username: string, password: string): Promise<any> {
    const command = new AdminInitiateAuthCommand({
      UserPoolId: USER_POOL_ID,
      ClientId: USER_POOL_CLIENT_ID,
      AuthFlow: 'ADMIN_NO_SRP_AUTH',
      AuthParameters: {
        USERNAME: username,
        PASSWORD: password
      }
    });

    const result = await cognitoClient.send(command);
    return result.AuthenticationResult;
  }

  /**
   * Check if a user exists in Cognito by phone number
   */
  static async checkUserExistsByPhone(phone: string): Promise<{ exists: boolean; username?: string; status?: string }> {
    try {
      const command = new ListUsersCommand({
        UserPoolId: USER_POOL_ID,
        Filter: `phone_number = "${phone}"`
      });

      const result = await cognitoClient.send(command);
      
      if (result.Users && result.Users.length > 0) {
        const user = result.Users[0];
        return {
          exists: true,
          username: user.Username,
          status: user.UserStatus
        };
      }

      return { exists: false };
    } catch (error) {
      console.error('Error checking user by phone:', error);
      return { exists: false };
    }
  }

  /**
   * Check if a user exists in Cognito by email with detailed status
   * Uses AdminGetUser as a fallback since ListUsers may have eventual consistency issues
   */
  static async checkUserExistsByEmail(email: string): Promise<{ 
    exists: boolean; 
    username?: string; 
    status?: string;
    isConfirmed?: boolean;
    canReregister?: boolean;
  }> {
    try {
      // First try with ListUsers (faster but may have consistency issues)
      const listCommand = new ListUsersCommand({
        UserPoolId: USER_POOL_ID,
        Filter: `email = "${email}"`
      });

      const listResult = await cognitoClient.send(listCommand);
      
      console.log(`Checking email ${email} in Cognito with ListUsers. Found ${listResult.Users?.length || 0} users`);
      
      if (listResult.Users && listResult.Users.length > 0) {
        const user = listResult.Users[0];
        const userStatus = user.UserStatus;
        const isConfirmed = userStatus === 'CONFIRMED';
        const canReregister = userStatus === 'UNCONFIRMED' || userStatus === 'FORCE_CHANGE_PASSWORD';
        
        console.log(`User found with ListUsers: ${email}, Status: ${userStatus}, IsConfirmed: ${isConfirmed}, Can reregister: ${canReregister}`);
        
        return {
          exists: true,
          username: user.Username,
          status: userStatus,
          isConfirmed: isConfirmed,
          canReregister: canReregister
        };
      }

      // If ListUsers doesn't find the user, try with the email as username directly
      // This handles cases where ListUsers has eventual consistency delays
      try {
        const getUserCommand = new AdminGetUserCommand({
          UserPoolId: USER_POOL_ID,
          Username: email
        });

        const getUserResult = await cognitoClient.send(getUserCommand);
        const userStatus = getUserResult.UserStatus;
        const isConfirmed = userStatus === 'CONFIRMED';
        const canReregister = userStatus === 'UNCONFIRMED' || userStatus === 'FORCE_CHANGE_PASSWORD';
        
        console.log(`User found with AdminGetUser: ${email}, Status: ${userStatus}, IsConfirmed: ${isConfirmed}, Can reregister: ${canReregister}`);
        
        return {
          exists: true,
          username: email,
          status: userStatus,
          isConfirmed: isConfirmed,
          canReregister: canReregister
        };
      } catch (getUserError: any) {
        if (getUserError.name === 'UserNotFoundException') {
          console.log(`No user found in Cognito for email: ${email}`);
          return { exists: false, canReregister: true };
        }
        // If it's another error, log it but continue
        console.log(`AdminGetUser failed for ${email}:`, getUserError.message);
      }

      console.log(`No user found in Cognito for email: ${email}`);
      return { exists: false, canReregister: true };
    } catch (error) {
      console.error('Error checking user by email:', error);
      return { exists: false, canReregister: true };
    }
  }

  /**
   * Check if a user exists in Cognito by username
   */
  static async checkUserExistsByUsername(username: string): Promise<{ exists: boolean; status?: string }> {
    try {
      const command = new AdminGetUserCommand({
        UserPoolId: USER_POOL_ID,
        Username: username
      });

      const result = await cognitoClient.send(command);
      
      return {
        exists: true,
        status: result.UserStatus
      };
    } catch (error: any) {
      if (error.name === 'UserNotFoundException') {
        return { exists: false };
      }
      console.error('Error checking user by username:', error);
      return { exists: false };
    }
  }  /**
   * Sign up a new user using Cognito's built-in email service
   * This automatically sends verification email without SES sandbox restrictions
   */
  static async signUpUser(
    username: string, 
    password: string, 
    name: string, 
    email: string,
    phone?: string,
    marketingConsent?: boolean,
    birthDate?: string,
    gender?: string,
    countryCode?: string,
    termsAccepted?: boolean,
    privacyAccepted?: boolean
  ): Promise<{ success: boolean; error?: string; userSub?: string; userExists?: boolean; isUnconfirmed?: boolean }> {
    try {
      const userAttributes = [
        { Name: 'name', Value: name },
        { Name: 'email', Value: email }
      ];

      if (phone) {
        userAttributes.push({ Name: 'phone_number', Value: phone });
      }

      if (marketingConsent !== undefined) {
        userAttributes.push({ Name: 'custom:marketing_consent', Value: marketingConsent.toString() });
      }

      // NOTE: Only use existing custom attributes to avoid schema errors
      // Terms, privacy, birth date, gender, and country code will be stored in DynamoDB instead
      // as these custom attributes don't exist in the Cognito User Pool schema

      const command = new SignUpCommand({
        ClientId: USER_POOL_CLIENT_ID,
        Username: username,
        Password: password,
        UserAttributes: userAttributes
      });

      const result = await cognitoClient.send(command);
      
      console.log('Cognito SignUp successful:', result.UserSub);
      
      return {
        success: true,
        userSub: result.UserSub
      };
    } catch (error: any) {
      console.error('Cognito SignUp failed:', error);
      
      let errorMessage = 'فشل في إنشاء الحساب';
      let userExists = false;
      let isUnconfirmed = false;
      
      if (error.name === 'UsernameExistsException') {
        userExists = true;
        // Check if the existing user is unconfirmed
        try {
          const userCheck = await this.checkUserExistsByEmail(email);
          if (userCheck.exists && !userCheck.isConfirmed) {
            isUnconfirmed = true;
            errorMessage = 'يوجد حساب غير مؤكد بهذا البريد الإلكتروني';
          } else {
            errorMessage = 'البريد الإلكتروني مسجل مسبقاً';
          }
        } catch (checkError) {
          console.error('Error checking user status:', checkError);
          errorMessage = 'البريد الإلكتروني مسجل مسبقاً';
        }
      } else if (error.name === 'InvalidPasswordException') {
        errorMessage = 'كلمة المرور لا تلبي المتطلبات المطلوبة';
      } else if (error.name === 'InvalidParameterException') {
        errorMessage = 'البيانات المدخلة غير صحيحة';
      }
      
      return {
        success: false,
        error: errorMessage,
        userExists: userExists,
        isUnconfirmed: isUnconfirmed
      };
    }
  }

  /**
   * Confirm user sign up with verification code
   */
  static async confirmSignUp(username: string, confirmationCode: string): Promise<{ success: boolean; error?: string }> {
    try {
      const command = new ConfirmSignUpCommand({
        ClientId: USER_POOL_CLIENT_ID,
        Username: username,
        ConfirmationCode: confirmationCode
      });

      await cognitoClient.send(command);
      
      console.log('Cognito ConfirmSignUp successful for:', username);
      
      return { success: true };
    } catch (error: any) {
      console.error('Cognito ConfirmSignUp failed:', error);
      
      let errorMessage = 'رمز التحقق غير صحيح';
      
      if (error.name === 'CodeMismatchException') {
        errorMessage = 'رمز التحقق غير صحيح';
      } else if (error.name === 'ExpiredCodeException') {
        errorMessage = 'رمز التحقق منتهي الصلاحية';
      } else if (error.name === 'UserNotFoundException') {
        errorMessage = 'المستخدم غير موجود';
      }
      
      return {
        success: false,
        error: errorMessage
      };
    }
  }

  /**
   * Delete unconfirmed user from Cognito
   */
  static async deleteUnconfirmedUser(username: string): Promise<{ success: boolean; error?: string }> {
    try {
      // First check if user exists and get their status
      const userCheck = await this.checkUserExistsByUsername(username);
      
      if (!userCheck.exists) {
        console.log(`User ${username} does not exist in Cognito, nothing to delete`);
        return { success: true }; // Consider this success since the goal is achieved
      }

      // Only delete if user is unconfirmed
      if (userCheck.status === 'UNCONFIRMED' || userCheck.status === 'FORCE_CHANGE_PASSWORD') {
        const command = new AdminDeleteUserCommand({
          UserPoolId: USER_POOL_ID,
          Username: username
        });

        await cognitoClient.send(command);
        console.log(`Deleted unconfirmed user ${username} from Cognito`);
        return { success: true };
      } else {
        console.log(`User ${username} is confirmed (${userCheck.status}), not deleting`);
        return { 
          success: false, 
          error: 'لا يمكن حذف مستخدم مؤكد' 
        };
      }
    } catch (error: any) {
      console.error('Error deleting unconfirmed user:', error);
      
      if (error.name === 'UserNotFoundException') {
        return { success: true }; // User already doesn't exist
      }
      
      return {
        success: false,
        error: 'فشل في حذف المستخدم غير المؤكد'
      };
    }
  }

  /**
   * Initiate password reset for email users using Cognito
   */
  static async initiatePasswordReset(username: string): Promise<{ success: boolean; error?: string; resetToken?: string }> {
    try {
      const { ForgotPasswordCommand } = await import('@aws-sdk/client-cognito-identity-provider');
      
      const command = new ForgotPasswordCommand({
        ClientId: USER_POOL_CLIENT_ID,
        Username: username
      });

      await cognitoClient.send(command);
      console.log('Password reset initiated for:', username);
      
      return {
        success: true,
        resetToken: username // For email users, we use the email as the reset token
      };
    } catch (error: any) {
      console.error('Failed to initiate password reset:', error);
      
      let errorMessage = 'فشل في إرسال رمز إعادة تعيين كلمة المرور';
      
      if (error.name === 'UserNotFoundException') {
        errorMessage = 'المستخدم غير موجود';
      } else if (error.name === 'InvalidParameterException') {
        errorMessage = 'بيانات غير صحيحة';
      } else if (error.name === 'LimitExceededException') {
        errorMessage = 'تم تجاوز حد المحاولات. يرجى المحاولة لاحقاً';
      }
      
      return {
        success: false,
        error: errorMessage
      };
    }
  }

  /**
   * Confirm password reset for email users using Cognito
   */
  static async confirmPasswordReset(
    username: string, 
    confirmationCode: string, 
    newPassword: string
  ): Promise<{ success: boolean; error?: string }> {
    try {
      const { ConfirmForgotPasswordCommand } = await import('@aws-sdk/client-cognito-identity-provider');
      
      const command = new ConfirmForgotPasswordCommand({
        ClientId: USER_POOL_CLIENT_ID,
        Username: username,
        ConfirmationCode: confirmationCode,
        Password: newPassword
      });

      await cognitoClient.send(command);
      console.log('Password reset confirmed for:', username);
      
      return { success: true };
    } catch (error: any) {
      console.error('Failed to confirm password reset:', error);
      
      let errorMessage = 'رمز التحقق غير صحيح أو منتهي الصلاحية';
      
      if (error.name === 'CodeMismatchException') {
        errorMessage = 'رمز التحقق غير صحيح';
      } else if (error.name === 'ExpiredCodeException') {
        errorMessage = 'رمز التحقق منتهي الصلاحية';
      } else if (error.name === 'UserNotFoundException') {
        errorMessage = 'المستخدم غير موجود';
      } else if (error.name === 'InvalidPasswordException') {
        errorMessage = 'كلمة المرور الجديدة غير صالحة';
      }
      
      return {
        success: false,
        error: errorMessage
      };
    }
  }

  /**
   * Set user password in Cognito (for phone users)
   */
  static async setUserPassword(
    cognitoUsername: string, 
    newPassword: string
  ): Promise<{ success: boolean; error?: string }> {
    try {
      const command = new AdminSetUserPasswordCommand({
        UserPoolId: USER_POOL_ID,
        Username: cognitoUsername,
        Password: newPassword,
        Permanent: true
      });

      await cognitoClient.send(command);
      console.log('Password updated for user:', cognitoUsername);
      
      return { success: true };
    } catch (error: any) {
      console.error('Failed to set user password:', error);
      
      let errorMessage = 'فشل في تحديث كلمة المرور';
      
      if (error.name === 'UserNotFoundException') {
        errorMessage = 'المستخدم غير موجود';
      } else if (error.name === 'InvalidParameterException') {
        errorMessage = 'كلمة المرور غير صالحة';
      } else if (error.name === 'InvalidPasswordException') {
        errorMessage = 'كلمة المرور الجديدة لا تلبي متطلبات الأمان';
      }
      
      return {
        success: false,
        error: errorMessage
      };
    }
  }

  /**
   * Get user information from Cognito including custom attributes
   */
  static async getCognitoUserAttributes(username: string): Promise<{ 
    success: boolean; 
    userData?: any;
    error?: string; 
  }> {
    try {
      const command = new AdminGetUserCommand({
        UserPoolId: USER_POOL_ID,
        Username: username
      });

      const result = await cognitoClient.send(command);
      
      // Convert UserAttributes array to object for easier access
      const userData: any = {
        username: result.Username,
        userStatus: result.UserStatus,
        enabled: result.Enabled,
        userCreateDate: result.UserCreateDate,
        userLastModifiedDate: result.UserLastModifiedDate
      };

      // Parse user attributes
      if (result.UserAttributes) {
        for (const attr of result.UserAttributes) {
          if (attr.Name && attr.Value) {
            // Remove 'custom:' prefix for custom attributes
            const attrName = attr.Name.startsWith('custom:') 
              ? attr.Name.substring(7) 
              : attr.Name;
            userData[attrName] = attr.Value;
          }
        }
      }

      console.log('Retrieved Cognito user data:', JSON.stringify(userData, null, 2));

      return {
        success: true,
        userData: userData
      };
    } catch (error: any) {
      console.error('Error getting Cognito user attributes:', error);
      
      let errorMessage = 'فشل في الحصول على معلومات المستخدم';
      
      if (error.name === 'UserNotFoundException') {
        errorMessage = 'المستخدم غير موجود';
      }
      
      return {
        success: false,
        error: errorMessage
      };
    }
  }
}

/**
 * SMS Helper Functions
 */
export class SMSHelper {
  static async sendVerificationSMS(phone: string, code: string): Promise<void> {
    const message = `رمز التحقق لتطبيق زاد: ${code}\nلا تشارك هذا الرمز مع أحد.\nصالح لمدة 10 دقائق.`;
    
    const command = new PublishCommand({
      PhoneNumber: phone,
      Message: message
    });

    await snsClient.send(command);
  }

  static async sendPasswordResetSMS(phone: string, code: string): Promise<void> {
    const message = `رمز إعادة تعيين كلمة المرور لتطبيق زاد: ${code}\nلا تشارك هذا الرمز مع أحد.\nصالح لمدة 15 دقيقة.`;
    
    const command = new PublishCommand({
      PhoneNumber: phone,
      Message: message,
      MessageAttributes: {
        'AWS.SNS.SMS.SenderID': {
          DataType: 'String',
          StringValue: 'FOODAPP'
        },
        'AWS.SNS.SMS.SMSType': {
          DataType: 'String',
          StringValue: 'Transactional'
        }
      }
    });

    await snsClient.send(command);
    console.log(`Password reset SMS sent to ${phone}`);
  }
}

/**
 * Email Helper Functions
 */
export class EmailHelper {
  static async sendVerificationEmail(email: string, code: string, name: string): Promise<void> {
    const subject = 'تأكيد حسابك في تطبيق زاد';
    const htmlBody = `
      <div dir="rtl" style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #00c1e8, #0099b8); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
          <h1 style="color: white; margin: 0; font-size: 28px;">مرحباً ${name}</h1>
        </div>
        
        <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px;">
          <h2 style="color: #333; text-align: center;">تأكيد عنوان البريد الإلكتروني</h2>
          
          <p style="color: #666; font-size: 16px; line-height: 1.6;">
            شكراً لتسجيلك في تطبيق زاد! لإكمال إنشاء حسابك، يرجى استخدام رمز التحقق التالي:
          </p>
          
          <div style="background: white; padding: 20px; text-align: center; border-radius: 8px; margin: 20px 0; border: 2px dashed #00c1e8;">
            <h1 style="color: #00c1e8; font-size: 32px; margin: 0; letter-spacing: 8px;">${code}</h1>
          </div>
          
          <p style="color: #666; font-size: 14px;">
            • هذا الرمز صالح لمدة <strong>10 دقائق</strong> فقط<br>
            • لا تشارك هذا الرمز مع أحد<br>
            • إذا لم تقم بطلب هذا الرمز، يرجى تجاهل هذه الرسالة
          </p>
          
          <div style="text-align: center; margin-top: 30px;">
            <p style="color: #999; font-size: 12px;">
              فريق تطبيق زاد<br>
              للمساعدة: support@foodapp.com
            </p>
          </div>
        </div>
      </div>
    `;

    const textBody = `
مرحباً ${name}،

شكراً لتسجيلك في تطبيق زاد! 

رمز التحقق الخاص بك: ${code}

هذا الرمز صالح لمدة 10 دقائق فقط.
لا تشارك هذا الرمز مع أحد.

فريق تطبيق زاد
    `;

    const command = new SendEmailCommand({
      Source: process.env.SES_FROM_EMAIL || 'noreply@foodapp.com',
      Destination: { ToAddresses: [email] },
      Message: {
        Subject: { Data: subject, Charset: 'UTF-8' },
        Body: {
          Html: { Data: htmlBody, Charset: 'UTF-8' },
          Text: { Data: textBody, Charset: 'UTF-8' }
        }
      }
    });

    try {
      await sesClient.send(command);
      console.log(`Email sent successfully to ${email}`);
    } catch (error: any) {
      console.error('Failed to send email:', error);
      
      // Enhanced error handling with specific AWS SES errors
      if (error.name === 'SendingQuotaExceededException') {
        throw new Error('تم تجاوز الحد اليومي لإرسال الإيميلات (50 رسالة). يرجى المحاولة غداً أو استخدم رقم الهاتف للتسجيل.');
      } else if (error.name === 'MessageRejected') {
        throw new Error('تم رفض الإيميل. تأكد من صحة عنوان البريد الإلكتروني.');
      } else if (error.name === 'MailFromDomainNotVerifiedException') {
        throw new Error('نطاق الإرسال غير مُحقق. يرجى استخدام رقم الهاتف للتسجيل.');
      } else if (error.name === 'AccountSendingPausedException') {
        throw new Error('تم إيقاف خدمة الإرسال مؤقتاً. يرجى استخدام رقم الهاتف للتسجيل.');
      } else if (error.message?.includes('not verified') || error.message?.includes('Email address not verified')) {
        throw new Error('عذراً، نظام الإرسال في وضع الاختبار حالياً. يرجى استخدام رقم الهاتف للتسجيل.');
      } else if (error.message?.includes('Daily sending quota exceeded')) {
        throw new Error('تم تجاوز الحد اليومي لإرسال الإيميلات (50 رسالة). يرجى المحاولة غداً أو استخدم رقم الهاتف.');
      } else if (error.message?.includes('sandbox')) {
        throw new Error('نظام الإرسال في وضع التطوير. يرجى استخدام رقم الهاتف للتسجيل.');
      }
      
      throw new Error(`فشل في إرسال رمز التحقق عبر البريد الإلكتروني. يرجى استخدام رقم الهاتف للتسجيل.`);
    }
  }
}

/**
 * Utility Functions
 */
export class Utils {
  static generateVerificationCode(): string {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  static generateTempUserId(): string {
    return 'temp_' + randomBytes(16).toString('hex');
  }

  static generateUserId(): string {
    return 'user_' + randomBytes(16).toString('hex');
  }

  static hashPassword(password: string): string {
    return createHash('sha256').update(password).digest('hex');
  }

  static formatPhoneNumber(phone: string, countryCode: string = '+964'): string {
    // Remove any existing country code and format
    let cleanPhone = phone.replace(/^\+?964/, '').replace(/\D/g, '');
    
    // Handle Iraqi phone number formats:
    // - If starts with 07, remove the leading 0 to get 7XXXXXXXX (10 digits starting with 7)
    // - If starts with 7, keep as is (already 10 digits starting with 7)
    if (cleanPhone.startsWith('07')) {
      cleanPhone = cleanPhone.substring(1); // Remove leading 0
    }
    
    // Ensure it's exactly 10 digits starting with 7
    if (!cleanPhone.startsWith('7') || cleanPhone.length !== 10) {
      // Try to fix common formats
      if (cleanPhone.startsWith('0') && cleanPhone.length === 11) {
        cleanPhone = cleanPhone.substring(1);
      }
    }
    
    return `${countryCode}${cleanPhone}`;
  }

  static isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  static isValidPhone(phone: string): boolean {
    // Iraqi phone number validation
    // Format: +964 followed by 10 digits starting with 7
    // Examples: +9647901234567, +9647701234567, +9647801234567
    const phoneRegex = /^\+9647[0-9]{9}$/;
    return phoneRegex.test(phone);
  }

  static getCurrentTimestamp(): string {
    return new Date().toISOString();
  }

  static getTTLTimestamp(hoursFromNow: number = 24): number {
    return Math.floor(Date.now() / 1000) + (hoursFromNow * 60 * 60);
  }

  static createAPIResponse(statusCode: number, body: any) {
    return {
      statusCode,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'
      },
      body: JSON.stringify(body)
    };
  }

  static generateResetToken(): string {
    // Generate a secure reset token
    return Utils.generateUserId() + '_' + Date.now().toString();
  }

  static getExpiryTimestamp(minutesFromNow: number = 15): number {
    return Math.floor(Date.now() / 1000) + (minutesFromNow * 60);
  }

  static isValidPassword(password: string): boolean {
    // Password must be at least 8 characters and contain:
    // - At least one uppercase letter
    // - At least one lowercase letter  
    // - At least one number
    // - At least one special character
    const passwordRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$/;
    return passwordRegex.test(password);
  }
}
