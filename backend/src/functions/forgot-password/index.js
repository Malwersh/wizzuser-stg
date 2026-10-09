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
    var requestBody, username, trimmedUsername, isEmailLogin, isPhoneLogin, formattedPhone, error_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('=== Forgot Password Handler ===');
                console.log('Event:', JSON.stringify(event, null, 2));
                // Handle CORS preflight
                if (event.httpMethod === 'OPTIONS') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, { message: 'OK' })];
                }
                _a.label = 1;
            case 1:
                _a.trys.push([1, 6, , 7]);
                requestBody = JSON.parse(event.body || '{}');
                username = requestBody.username;
                // Validate input
                if (!username) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'يرجى إدخال اسم المستخدم (البريد الإلكتروني أو رقم الهاتف)'
                        })];
                }
                trimmedUsername = username.trim();
                console.log('Processing password reset for:', trimmedUsername);
                isEmailLogin = false;
                isPhoneLogin = false;
                formattedPhone = '';
                // Determine if it's email or phone
                if (aws_helpers_1.Utils.isValidEmail(trimmedUsername)) {
                    console.log('Detected email login');
                    isEmailLogin = true;
                }
                else {
                    console.log('Detected phone login, formatting phone number');
                    formattedPhone = aws_helpers_1.Utils.formatPhoneNumber(trimmedUsername);
                    if (!aws_helpers_1.Utils.isValidPhone(formattedPhone)) {
                        console.log('Invalid phone format');
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'اسم المستخدم غير صحيح. يجب أن يكون بريد إلكتروني أو رقم هاتف صالح'
                            })];
                    }
                    isPhoneLogin = true;
                }
                if (!isEmailLogin) return [3 /*break*/, 3];
                return [4 /*yield*/, handleEmailPasswordReset(trimmedUsername)];
            case 2: 
            // Handle email password reset
            return [2 /*return*/, _a.sent()];
            case 3:
                if (!isPhoneLogin) return [3 /*break*/, 5];
                return [4 /*yield*/, handlePhonePasswordReset(formattedPhone)];
            case 4: 
            // Handle phone password reset
            return [2 /*return*/, _a.sent()];
            case 5: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: 'نوع المستخدم غير صحيح'
                })];
            case 6:
                error_1 = _a.sent();
                console.error('Forgot password error:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ في النظام. يرجى المحاولة مرة أخرى'
                    })];
            case 7: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
function handleEmailPasswordReset(email) {
    return __awaiter(this, void 0, void 0, function () {
        var user, cognitoCheck, resetResult, error_2;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    console.log('=== Email Password Reset ===');
                    console.log('Email:', email);
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 6, , 7]);
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByEmail(email)];
                case 2:
                    user = _a.sent();
                    if (!!user) return [3 /*break*/, 4];
                    return [4 /*yield*/, aws_helpers_1.CognitoHelper.checkUserExistsByEmail(email)];
                case 3:
                    cognitoCheck = _a.sent();
                    if (!cognitoCheck.exists) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(404, {
                                success: false,
                                error: 'لا يوجد حساب مرتبط بهذا البريد الإلكتروني'
                            })];
                    }
                    if (cognitoCheck.exists && !cognitoCheck.isConfirmed) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'الحساب غير مؤكد. يرجى تأكيد البريد الإلكتروني أولاً'
                            })];
                    }
                    _a.label = 4;
                case 4:
                    // Check if user account is active
                    if (user && !user.isActive) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                                success: false,
                                error: 'حسابك معطل. يرجى الاتصال بالدعم الفني'
                            })];
                    }
                    return [4 /*yield*/, aws_helpers_1.CognitoHelper.initiatePasswordReset(email)];
                case 5:
                    resetResult = _a.sent();
                    if (!resetResult.success) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: resetResult.error || 'فشل في إرسال رمز إعادة تعيين كلمة المرور'
                            })];
                    }
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                            success: true,
                            message: 'تم إرسال رمز إعادة تعيين كلمة المرور إلى بريدك الإلكتروني',
                            resetToken: resetResult.resetToken // For frontend to use in confirm step
                        })];
                case 6:
                    error_2 = _a.sent();
                    console.error('Email password reset error:', error_2);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'حدث خطأ أثناء إرسال رمز إعادة التعيين'
                        })];
                case 7: return [2 /*return*/];
            }
        });
    });
}
function handlePhonePasswordReset(phone) {
    return __awaiter(this, void 0, void 0, function () {
        var user, resetToken, verificationCode, currentTime, expiryTime, smsError_1, error_3;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    console.log('=== Phone Password Reset ===');
                    console.log('Phone:', phone);
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 9, , 10]);
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByPhone(phone)];
                case 2:
                    user = _a.sent();
                    if (!user) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(404, {
                                success: false,
                                error: 'لا يوجد حساب مرتبط برقم الهاتف هذا'
                            })];
                    }
                    // Check if user account is active
                    if (!user.isActive) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                                success: false,
                                error: 'حسابك معطل. يرجى الاتصال بالدعم الفني'
                            })];
                    }
                    resetToken = aws_helpers_1.Utils.generateResetToken();
                    verificationCode = aws_helpers_1.Utils.generateVerificationCode();
                    currentTime = Math.floor(Date.now() / 1000);
                    expiryTime = aws_helpers_1.Utils.getExpiryTimestamp(15);
                    // Store reset token in DynamoDB with expiry
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.createPasswordResetToken({
                            resetToken: resetToken,
                            userId: user.userId,
                            phone: phone,
                            verificationCode: verificationCode,
                            isUsed: false,
                            createdAt: currentTime,
                            expiresAt: expiryTime,
                            ttl: aws_helpers_1.Utils.getTTLTimestamp(1) // 1 hour TTL for DynamoDB
                        })];
                case 3:
                    // Store reset token in DynamoDB with expiry
                    _a.sent();
                    _a.label = 4;
                case 4:
                    _a.trys.push([4, 6, , 8]);
                    return [4 /*yield*/, aws_helpers_1.SMSHelper.sendPasswordResetSMS(phone, verificationCode)];
                case 5:
                    _a.sent();
                    console.log('Password reset SMS sent successfully to:', phone);
                    return [3 /*break*/, 8];
                case 6:
                    smsError_1 = _a.sent();
                    console.error('Failed to send password reset SMS:', smsError_1);
                    // Clean up the reset token if SMS failed
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.deletePasswordResetToken(resetToken)];
                case 7:
                    // Clean up the reset token if SMS failed
                    _a.sent();
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'فشل في إرسال رمز التحقق عبر الرسائل النصية'
                        })];
                case 8: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                        success: true,
                        message: 'تم إرسال رمز إعادة تعيين كلمة المرور إلى رقم هاتفك',
                        resetToken: resetToken // For frontend to use in confirm step
                    })];
                case 9:
                    error_3 = _a.sent();
                    console.error('Phone password reset error:', error_3);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'حدث خطأ أثناء إرسال رمز إعادة التعيين'
                        })];
                case 10: return [2 /*return*/];
            }
        });
    });
}
