"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const aws_helpers_1 = require("../../utils/aws-helpers");

const handler = async (event) => {
    console.log('=== Change Password Handler ===');
    console.log('Event:', JSON.stringify(event, null, 2));
    
    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
        return aws_helpers_1.Utils.createAPIResponse(200, { message: 'OK' });
    }

    try {
        const userId = event.pathParameters?.user_id;
        const requestBody = JSON.parse(event.body || '{}');
        const { current_password, new_password } = requestBody;

        // Validate input
        if (!userId) {
            return aws_helpers_1.Utils.createAPIResponse(400, {
                success: false,
                error: 'معرف المستخدم مطلوب'
            });
        }

        if (!current_password || !new_password) {
            return aws_helpers_1.Utils.createAPIResponse(400, {
                success: false,
                error: 'كلمة المرور الحالية والجديدة مطلوبتان'
            });
        }

        // Validate new password strength
        if (!aws_helpers_1.Utils.isValidPassword(new_password)) {
            return aws_helpers_1.Utils.createAPIResponse(400, {
                success: false,
                error: 'كلمة المرور الجديدة يجب أن تحتوي على 8 أحرف على الأقل وتشمل أحرف كبيرة وصغيرة وأرقام'
            });
        }

        // Check if new password is the same as current password
        if (current_password === new_password) {
            return aws_helpers_1.Utils.createAPIResponse(400, {
                success: false,
                error: 'كلمة المرور الجديدة يجب أن تكون مختلفة عن كلمة المرور الحالية'
            });
        }

        // Get user from DynamoDB
        const user = await aws_helpers_1.DynamoHelper.getUserById(userId);
        if (!user) {
            return aws_helpers_1.Utils.createAPIResponse(404, {
                success: false,
                error: 'المستخدم غير موجود'
            });
        }

        // Check if user account is active
        if (!user.isActive) {
            return aws_helpers_1.Utils.createAPIResponse(403, {
                success: false,
                error: 'حسابك معطل. يرجى الاتصال بالدعم الفني'
            });
        }

        // Authenticate user with current password to verify it's correct
        let authUsername = '';
        if (user.email) {
            authUsername = user.email;
        } else if (user.phone) {
            authUsername = user.phone;
        } else if (user.cognitoUsername) {
            authUsername = user.cognitoUsername;
        } else {
            return aws_helpers_1.Utils.createAPIResponse(400, {
                success: false,
                error: 'لا يمكن العثور على بيانات المصادقة للمستخدم'
            });
        }

        // Verify current password by attempting authentication
        try {
            const authResult = await aws_helpers_1.CognitoHelper.authenticateUser(authUsername, current_password);
            if (!authResult) {
                return aws_helpers_1.Utils.createAPIResponse(401, {
                    success: false,
                    error: 'كلمة المرور الحالية غير صحيحة'
                });
            }
        } catch (authError) {
            console.error('Authentication failed:', authError);
            
            let errorMessage = 'كلمة المرور الحالية غير صحيحة';
            
            if (authError.name === 'NotAuthorizedException') {
                errorMessage = 'كلمة المرور الحالية غير صحيحة';
            } else if (authError.name === 'UserNotConfirmedException') {
                errorMessage = 'الحساب غير مؤكد';
            } else if (authError.name === 'TooManyRequestsException') {
                errorMessage = 'محاولات كثيرة جداً. يرجى المحاولة لاحقاً';
            }

            return aws_helpers_1.Utils.createAPIResponse(401, {
                success: false,
                error: errorMessage
            });
        }

        // Update password in Cognito
        const passwordUpdateResult = await aws_helpers_1.CognitoHelper.setUserPassword(user.cognitoUsername, new_password);
        
        if (!passwordUpdateResult.success) {
            return aws_helpers_1.Utils.createAPIResponse(500, {
                success: false,
                error: passwordUpdateResult.error || 'فشل في تحديث كلمة المرور'
            });
        }

        // Update user record in DynamoDB with last password change timestamp
        const currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
        await aws_helpers_1.DynamoHelper.updateUser(userId, {
            updatedAt: currentTime,
            lastPasswordChange: currentTime
        });

        console.log('Password updated successfully for user:', userId);

        return aws_helpers_1.Utils.createAPIResponse(200, {
            success: true,
            message: 'تم تغيير كلمة المرور بنجاح'
        });

    } catch (error) {
        console.error('Change password error:', error);
        return aws_helpers_1.Utils.createAPIResponse(500, {
            success: false,
            error: 'حدث خطأ في النظام. يرجى المحاولة مرة أخرى'
        });
    }
};

exports.handler = handler;
