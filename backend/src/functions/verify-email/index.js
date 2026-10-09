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
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
var aws_helpers_1 = require("../../utils/aws-helpers");
var handler = function (event) { return __awaiter(void 0, void 0, void 0, function () {
    var requestBody, tempUserId, code, verificationCode, finalCode, cognitoResult_1, currentTime, userId, cognitoUserResult, cognitoData, permanentUser, userCreationError_1, tempUser, cognitoResult, currentTime, userId, permanentUser, response, error_1, error_2;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('Email verification request received:', JSON.stringify(event.body));
                _a.label = 1;
            case 1:
                _a.trys.push([1, 19, , 20]);
                requestBody = JSON.parse(event.body || '{}');
                tempUserId = requestBody.tempUserId, code = requestBody.code, verificationCode = requestBody.verificationCode;
                finalCode = code || verificationCode;
                if (!tempUserId || !finalCode) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'معرف المستخدم المؤقت ورمز التحقق مطلوبان'
                        })];
                }
                if (!tempUserId.includes('@')) return [3 /*break*/, 7];
                console.log('Direct Cognito email verification for:', tempUserId);
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.confirmSignUp(tempUserId, finalCode)];
            case 2:
                cognitoResult_1 = _a.sent();
                if (!cognitoResult_1.success) {
                    console.error('Cognito ConfirmSignUp failed:', cognitoResult_1.error);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: cognitoResult_1.error || 'رمز التحقق غير صحيح'
                        })];
                }
                console.log('Cognito user confirmed successfully');
                _a.label = 3;
            case 3:
                _a.trys.push([3, 6, , 7]);
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                userId = aws_helpers_1.Utils.generateUserId();
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.getCognitoUserAttributes(tempUserId)];
            case 4:
                cognitoUserResult = _a.sent();
                if (!cognitoUserResult.success || !cognitoUserResult.userData) {
                    console.error('Failed to get user data from Cognito:', cognitoUserResult.error);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'فشل في الحصول على معلومات المستخدم من Cognito'
                        })];
                }
                cognitoData = cognitoUserResult.userData;
                console.log('Retrieved Cognito data for direct email verification:', cognitoData);
                permanentUser = {
                    userId: userId,
                    cognitoUsername: tempUserId, // email as Cognito username
                    name: cognitoData.name || 'User',
                    phone: cognitoData.phone_number || undefined,
                    email: tempUserId,
                    birthDate: cognitoData.birth_date || undefined,
                    gender: cognitoData.gender || undefined,
                    countryCode: cognitoData.country_code || '+964',
                    profileImage: undefined,
                    isActive: true,
                    lastLoginAt: undefined,
                    termsAccepted: cognitoData.terms_accepted === 'true' || true,
                    privacyAccepted: cognitoData.privacy_accepted === 'true' || true,
                    marketingConsent: cognitoData.marketing_consent === 'true' || false,
                    createdAt: currentTime,
                    updatedAt: currentTime,
                    preferredLanguage: 'ar',
                    addresses: [],
                    paymentMethods: []
                };
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.createUser(permanentUser)];
            case 5:
                _a.sent();
                console.log('Permanent user created successfully');
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                        success: true,
                        message: 'تم تأكيد البريد الإلكتروني بنجاح',
                        userId: userId,
                        verified: true
                    })];
            case 6:
                userCreationError_1 = _a.sent();
                console.error('Failed to create permanent user:', userCreationError_1);
                // Still return success since Cognito verification succeeded
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                        success: true,
                        message: 'تم تأكيد البريد الإلكتروني بنجاح',
                        verified: true
                    })];
            case 7: return [4 /*yield*/, aws_helpers_1.DynamoHelper.getTempUser(tempUserId)];
            case 8:
                tempUser = _a.sent();
                if (!tempUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(404, {
                            success: false,
                            error: 'المستخدم المؤقت غير موجود أو انتهت صلاحيته'
                        })];
                }
                // Check if email verification is required
                if (!tempUser.email) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'لم يتم تقديم بريد إلكتروني للتحقق منه'
                        })];
                }
                // Use Cognito ConfirmSignUp for DynamoDB users with email
                console.log('Confirming Cognito user signup for DynamoDB user...');
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.confirmSignUp(tempUser.email, finalCode)];
            case 9:
                cognitoResult = _a.sent();
                if (!!cognitoResult.success) return [3 /*break*/, 13];
                console.error('Cognito ConfirmSignUp failed:', cognitoResult.error);
                // Increment attempts in temp user
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateTempUser(tempUserId, {
                        emailVerificationAttempts: tempUser.emailVerificationAttempts + 1,
                        updatedAt: aws_helpers_1.Utils.getCurrentTimestamp()
                    })];
            case 10:
                // Increment attempts in temp user
                _a.sent();
                if (!(tempUser.emailVerificationAttempts >= 4)) return [3 /*break*/, 12];
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.deleteTempUser(tempUserId)];
            case 11:
                _a.sent();
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(429, {
                        success: false,
                        error: 'تم تجاوز عدد المحاولات المسموحة. يرجى إعادة التسجيل'
                    })];
            case 12: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: cognitoResult.error || 'رمز التحقق غير صحيح'
                })];
            case 13:
                console.log('Cognito user confirmed successfully');
                _a.label = 14;
            case 14:
                _a.trys.push([14, 17, , 18]);
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                userId = aws_helpers_1.Utils.generateUserId();
                permanentUser = {
                    userId: userId,
                    cognitoUsername: tempUser.email, // email as Cognito username
                    name: tempUser.name,
                    phone: tempUser.phone, // ✅ Fix: Keep phone from tempUser instead of undefined
                    email: tempUser.email,
                    birthDate: tempUser.birthDate,
                    gender: tempUser.gender,
                    countryCode: tempUser.countryCode,
                    profileImage: undefined,
                    isActive: true,
                    lastLoginAt: undefined,
                    termsAccepted: tempUser.termsAccepted,
                    privacyAccepted: tempUser.privacyAccepted,
                    marketingConsent: tempUser.marketingConsent || false,
                    createdAt: currentTime,
                    updatedAt: currentTime,
                    preferredLanguage: 'ar',
                    addresses: [],
                    paymentMethods: []
                };
                // Save permanent user to database
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.createUser(permanentUser)];
            case 15:
                // Save permanent user to database
                _a.sent();
                // Clean up temporary user data
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.deleteTempUser(tempUserId)];
            case 16:
                // Clean up temporary user data
                _a.sent();
                console.log('Permanent user created successfully:', userId);
                response = {
                    success: true,
                    message: 'تم تأكيد البريد الإلكتروني بنجاح! يمكنك الآن تسجيل الدخول',
                    userId: userId
                };
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, response)];
            case 17:
                error_1 = _a.sent();
                console.error('Error creating permanent user:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء إنشاء الحساب الدائم'
                    })];
            case 18: return [3 /*break*/, 20];
            case 19:
                error_2 = _a.sent();
                console.error('Email verification error:', error_2);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء تأكيد البريد الإلكتروني'
                    })];
            case 20: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
