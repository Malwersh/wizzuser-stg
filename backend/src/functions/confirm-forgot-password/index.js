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
    var requestBody, username, confirmationCode, newPassword, resetToken, trimmedUsername, isEmailLogin, isPhoneLogin, formattedPhone, error_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('=== Confirm Forgot Password Handler ===');
                console.log('Event:', JSON.stringify(event, null, 2));
                // Handle CORS preflight
                if (event.httpMethod === 'OPTIONS') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, { message: 'OK' })];
                }
                _a.label = 1;
            case 1:
                _a.trys.push([1, 6, , 7]);
                requestBody = JSON.parse(event.body || '{}');
                username = requestBody.username, confirmationCode = requestBody.confirmationCode, newPassword = requestBody.newPassword, resetToken = requestBody.resetToken;
                // Validate input
                if (!username || !confirmationCode || !newPassword) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'جميع الحقول مطلوبة: اسم المستخدم، رمز التحقق، كلمة المرور الجديدة'
                        })];
                }
                // Validate password strength
                if (!aws_helpers_1.Utils.isValidPassword(newPassword)) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'كلمة المرور يجب أن تحتوي على 8 أحرف على الأقل وتشمل أحرف كبيرة وصغيرة وأرقام'
                        })];
                }
                trimmedUsername = username.trim();
                console.log('Processing password confirmation for:', trimmedUsername);
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
                return [4 /*yield*/, handleEmailPasswordConfirmation(trimmedUsername, confirmationCode, newPassword)];
            case 2: 
            // Handle email password confirmation
            return [2 /*return*/, _a.sent()];
            case 3:
                if (!isPhoneLogin) return [3 /*break*/, 5];
                // Handle phone password confirmation
                if (!resetToken) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'رمز إعادة التعيين مطلوب'
                        })];
                }
                return [4 /*yield*/, handlePhonePasswordConfirmation(formattedPhone, confirmationCode, newPassword, resetToken)];
            case 4: return [2 /*return*/, _a.sent()];
            case 5: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: 'نوع المستخدم غير صحيح'
                })];
            case 6:
                error_1 = _a.sent();
                console.error('Confirm forgot password error:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ في النظام. يرجى المحاولة مرة أخرى'
                    })];
            case 7: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
function handleEmailPasswordConfirmation(email, confirmationCode, newPassword) {
    return __awaiter(this, void 0, void 0, function () {
        var confirmResult, user, currentTime, error_2;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    console.log('=== Email Password Confirmation ===');
                    console.log('Email:', email);
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 6, , 7]);
                    return [4 /*yield*/, aws_helpers_1.CognitoHelper.confirmPasswordReset(email, confirmationCode, newPassword)];
                case 2:
                    confirmResult = _a.sent();
                    if (!confirmResult.success) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: confirmResult.error || 'رمز التحقق غير صحيح أو منتهي الصلاحية'
                            })];
                    }
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByEmail(email)];
                case 3:
                    user = _a.sent();
                    if (!user) return [3 /*break*/, 5];
                    currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateUser(user.userId, {
                            updatedAt: currentTime
                        })];
                case 4:
                    _a.sent();
                    _a.label = 5;
                case 5: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                        success: true,
                        message: 'تم تغيير كلمة المرور بنجاح. يمكنك الآن تسجيل الدخول بكلمة المرور الجديدة'
                    })];
                case 6:
                    error_2 = _a.sent();
                    console.error('Email password confirmation error:', error_2);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'حدث خطأ أثناء تغيير كلمة المرور'
                        })];
                case 7: return [2 /*return*/];
            }
        });
    });
}
function handlePhonePasswordConfirmation(phone, confirmationCode, newPassword, resetToken) {
    return __awaiter(this, void 0, void 0, function () {
        var resetData, currentTime, user, cognitoResult, error_3;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    console.log('=== Phone Password Confirmation ===');
                    console.log('Phone:', phone);
                    console.log('Reset Token:', resetToken);
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 9, , 10]);
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.getPasswordResetToken(resetToken)];
                case 2:
                    resetData = _a.sent();
                    if (!resetData) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'رمز إعادة التعيين غير صحيح أو منتهي الصلاحية'
                            })];
                    }
                    // Check if token is already used
                    if (resetData.isUsed) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'تم استخدام رمز إعادة التعيين مسبقاً'
                            })];
                    }
                    currentTime = Math.floor(Date.now() / 1000);
                    if (!(currentTime > resetData.expiresAt)) return [3 /*break*/, 4];
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.deletePasswordResetToken(resetToken)];
                case 3:
                    _a.sent();
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'انتهت صلاحية رمز إعادة التعيين. يرجى طلب رمز جديد'
                        })];
                case 4:
                    // Verify phone matches
                    if (resetData.phone !== phone) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'رقم الهاتف غير متطابق'
                            })];
                    }
                    // Verify confirmation code
                    if (resetData.verificationCode !== confirmationCode) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'رمز التحقق غير صحيح'
                            })];
                    }
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByPhone(phone)];
                case 5:
                    user = _a.sent();
                    if (!user) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(404, {
                                success: false,
                                error: 'المستخدم غير موجود'
                            })];
                    }
                    return [4 /*yield*/, aws_helpers_1.CognitoHelper.setUserPassword(user.cognitoUsername, newPassword)];
                case 6:
                    cognitoResult = _a.sent();
                    if (!cognitoResult.success) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                                success: false,
                                error: 'فشل في تحديث كلمة المرور'
                            })];
                    }
                    // Mark reset token as used
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.updatePasswordResetToken(resetToken, {
                            isUsed: true,
                            usedAt: currentTime
                        })];
                case 7:
                    // Mark reset token as used
                    _a.sent();
                    // Update user record in DynamoDB
                    return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateUser(user.userId, {
                            updatedAt: new Date().toISOString()
                        })];
                case 8:
                    // Update user record in DynamoDB
                    _a.sent();
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                            success: true,
                            message: 'تم تغيير كلمة المرور بنجاح. يمكنك الآن تسجيل الدخول بكلمة المرور الجديدة'
                        })];
                case 9:
                    error_3 = _a.sent();
                    console.error('Phone password confirmation error:', error_3);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'حدث خطأ أثناء تغيير كلمة المرور'
                        })];
                case 10: return [2 /*return*/];
            }
        });
    });
}
