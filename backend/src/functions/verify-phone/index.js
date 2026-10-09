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
    var requestBody, tempUserId, code, verificationCode, finalCode, tempUser, updatedTempUser, primaryIdentifier, cognitoUsername, userId, currentTime, permanentUser, authResult, response, cognitoError_1, error_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('Phone verification request received:', JSON.stringify(event.body));
                _a.label = 1;
            case 1:
                _a.trys.push([1, 18, , 19]);
                requestBody = JSON.parse(event.body || '{}');
                tempUserId = requestBody.tempUserId, code = requestBody.code, verificationCode = requestBody.verificationCode;
                finalCode = code || verificationCode;
                if (!tempUserId || !finalCode) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'معرف المستخدم المؤقت ورمز التحقق مطلوبان'
                        })];
                }
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getTempUser(tempUserId)];
            case 2:
                tempUser = _a.sent();
                if (!tempUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(404, {
                            success: false,
                            error: 'المستخدم المؤقت غير موجود أو انتهت صلاحيته'
                        })];
                }
                // Check if phone is already verified
                if (tempUser.phoneVerified) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'رقم الهاتف مُتحقق منه مسبقاً'
                        })];
                }
                if (!(tempUser.phoneVerificationCode !== finalCode)) return [3 /*break*/, 6];
                // Increment attempts
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateTempUser(tempUserId, {
                        phoneVerificationAttempts: tempUser.phoneVerificationAttempts + 1,
                        updatedAt: aws_helpers_1.Utils.getCurrentTimestamp()
                    })];
            case 3:
                // Increment attempts
                _a.sent();
                if (!(tempUser.phoneVerificationAttempts >= 4)) return [3 /*break*/, 5];
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.deleteTempUser(tempUserId)];
            case 4:
                _a.sent();
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(429, {
                        success: false,
                        error: 'تم تجاوز عدد المحاولات المسموحة. يرجى إعادة التسجيل'
                    })];
            case 5: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: 'رمز التحقق غير صحيح'
                })];
            case 6: 
            // Mark phone as verified
            return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateTempUser(tempUserId, {
                    phoneVerified: true,
                    updatedAt: aws_helpers_1.Utils.getCurrentTimestamp()
                })];
            case 7:
                // Mark phone as verified
                _a.sent();
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getTempUser(tempUserId)];
            case 8:
                updatedTempUser = _a.sent();
                if (!updatedTempUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'حدث خطأ في تحديث بيانات المستخدم'
                        })];
                }
                if (!(updatedTempUser.phone && updatedTempUser.phoneVerified)) return [3 /*break*/, 16];
                _a.label = 9;
            case 9:
                _a.trys.push([9, 14, , 15]);
                primaryIdentifier = updatedTempUser.phone;
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.createCognitoUser(primaryIdentifier, updatedTempUser.email, updatedTempUser.password, updatedTempUser.name, updatedTempUser.phone // Pass phone for phone registration
                    )];
            case 10:
                cognitoUsername = _a.sent();
                userId = aws_helpers_1.Utils.generateUserId();
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                permanentUser = {
                    userId: userId,
                    cognitoUsername: cognitoUsername,
                    name: updatedTempUser.name,
                    phone: updatedTempUser.phone,
                    email: updatedTempUser.email,
                    birthDate: updatedTempUser.birthDate,
                    gender: updatedTempUser.gender,
                    countryCode: updatedTempUser.countryCode,
                    // Profile information
                    isActive: true,
                    lastLoginAt: currentTime,
                    // Consent flags
                    termsAccepted: updatedTempUser.termsAccepted,
                    privacyAccepted: updatedTempUser.privacyAccepted,
                    marketingConsent: updatedTempUser.marketingConsent || false,
                    // Metadata
                    createdAt: currentTime,
                    updatedAt: currentTime,
                    // Initialize empty arrays
                    addresses: [],
                    paymentMethods: []
                };
                // Save to permanent users table
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.createUser(permanentUser)];
            case 11:
                // Save to permanent users table
                _a.sent();
                // Delete temporary user
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.deleteTempUser(tempUserId)];
            case 12:
                // Delete temporary user
                _a.sent();
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.authenticateUser(cognitoUsername, updatedTempUser.password // Use original password
                    )];
            case 13:
                authResult = _a.sent();
                response = {
                    success: true,
                    message: 'تم التحقق من الحساب بنجاح! مرحباً بك في تطبيق زاد',
                    userId: userId,
                    accessToken: authResult.AccessToken,
                    refreshToken: authResult.RefreshToken
                };
                console.log('User account created successfully:', userId);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, response)];
            case 14:
                cognitoError_1 = _a.sent();
                console.error('Cognito creation error:', cognitoError_1);
                // If Cognito fails, keep temp user for retry
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء إنشاء الحساب. يرجى المحاولة مرة أخرى'
                    })];
            case 15: return [3 /*break*/, 17];
            case 16: 
            // This should not happen in the separated system
            return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: 'خطأ في النظام: التحقق من الهاتف غير مطلوب لهذا المستخدم'
                })];
            case 17: return [3 /*break*/, 19];
            case 18:
                error_1 = _a.sent();
                console.error('Phone verification error:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء التحقق من رقم الهاتف'
                    })];
            case 19: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
