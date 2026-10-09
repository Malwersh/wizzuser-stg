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
    var requestBody, tempUserId, verificationType, newPhone, countryCode, command, cognitoClient, error_1, errorMessage, tempUser, currentTime, updates, messages, now, lastPhoneCodeTime, lastEmailCodeTime, minInterval, phoneToUse, formattedPhone, newPhoneCode, smsError_1, newEmailCode, emailError_1, response, error_2;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('Resend verification request received:', JSON.stringify(event.body));
                _a.label = 1;
            case 1:
                _a.trys.push([1, 22, , 23]);
                requestBody = JSON.parse(event.body || '{}');
                tempUserId = requestBody.tempUserId, verificationType = requestBody.verificationType, newPhone = requestBody.newPhone, countryCode = requestBody.countryCode;
                if (!tempUserId || !verificationType) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'معرف المستخدم المؤقت ونوع التحقق مطلوبان'
                        })];
                }
                if (!(verificationType === 'email')) return [3 /*break*/, 7];
                if (!tempUserId.includes('@')) return [3 /*break*/, 7];
                _a.label = 2;
            case 2:
                _a.trys.push([2, 6, , 7]);
                return [4 /*yield*/, Promise.resolve().then(function () { return require('@aws-sdk/client-cognito-identity-provider'); })];
            case 3:
                command = new (_a.sent()).ResendConfirmationCodeCommand({
                    ClientId: process.env.USER_POOL_CLIENT_ID,
                    Username: tempUserId,
                });
                return [4 /*yield*/, Promise.resolve().then(function () { return require('@aws-sdk/client-cognito-identity-provider'); })];
            case 4:
                cognitoClient = new (_a.sent()).CognitoIdentityProviderClient({
                    region: process.env.AWS_REGION || 'us-east-1'
                });
                return [4 /*yield*/, cognitoClient.send(command)];
            case 5:
                _a.sent();
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                        success: true,
                        message: 'تم إرسال رمز التحقق الجديد إلى البريد الإلكتروني'
                    })];
            case 6:
                error_1 = _a.sent();
                console.error('Failed to resend Cognito verification code:', error_1);
                errorMessage = 'فشل في إرسال رمز التحقق عبر البريد الإلكتروني';
                if (error_1.name === 'UserNotFoundException') {
                    errorMessage = 'المستخدم غير موجود';
                }
                else if (error_1.name === 'InvalidParameterException') {
                    errorMessage = 'البريد الإلكتروني غير صحيح';
                }
                else if (error_1.name === 'LimitExceededException') {
                    errorMessage = 'تم تجاوز عدد المحاولات المسموحة. يرجى الانتظار';
                }
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                        success: false,
                        error: errorMessage
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
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                updates = { updatedAt: currentTime };
                messages = [];
                now = Date.now();
                lastPhoneCodeTime = tempUser.lastPhoneCodeSent ? new Date(tempUser.lastPhoneCodeSent).getTime() : 0;
                lastEmailCodeTime = tempUser.lastEmailCodeSent ? new Date(tempUser.lastEmailCodeSent).getTime() : 0;
                minInterval = 60 * 1000;
                if (!(verificationType === 'phone' || verificationType === 'both')) return [3 /*break*/, 14];
                if (tempUser.phoneVerified) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'رقم الهاتف مُتحقق منه مسبقاً'
                        })];
                }
                phoneToUse = tempUser.phone;
                if (newPhone) {
                    formattedPhone = aws_helpers_1.Utils.formatPhoneNumber(newPhone, countryCode || '+964');
                    if (!aws_helpers_1.Utils.isValidPhone(formattedPhone)) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'رقم الهاتف الجديد غير صحيح'
                            })];
                    }
                    phoneToUse = formattedPhone;
                    updates.phone = formattedPhone;
                    updates.countryCode = countryCode || '+964';
                    console.log("Updating phone number from ".concat(tempUser.phone, " to ").concat(formattedPhone));
                }
                // Check rate limit for phone (skip for phone number updates)
                if (!newPhone && now - lastPhoneCodeTime < minInterval) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(429, {
                            success: false,
                            error: 'يرجى الانتظار دقيقة واحدة قبل طلب رمز جديد للهاتف'
                        })];
                }
                newPhoneCode = aws_helpers_1.Utils.generateVerificationCode();
                updates.phoneVerificationCode = newPhoneCode;
                updates.lastPhoneCodeSent = currentTime;
                _a.label = 9;
            case 9:
                _a.trys.push([9, 13, , 14]);
                if (!phoneToUse) return [3 /*break*/, 11];
                return [4 /*yield*/, aws_helpers_1.SMSHelper.sendVerificationSMS(phoneToUse, newPhoneCode)];
            case 10:
                _a.sent();
                if (newPhone) {
                    messages.push('تم تحديث رقم الهاتف وإرسال رمز التحقق الجديد');
                }
                else {
                    messages.push('تم إرسال رمز التحقق الجديد إلى رقم الهاتف');
                }
                console.log("Phone verification code sent to: ".concat(phoneToUse));
                return [3 /*break*/, 12];
            case 11: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: 'رقم الهاتف غير موجود لهذا المستخدم'
                })];
            case 12: return [3 /*break*/, 14];
            case 13:
                smsError_1 = _a.sent();
                console.error('Failed to send SMS:', smsError_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'فشل في إرسال رمز التحقق عبر الرسائل النصية'
                    })];
            case 14:
                if (!(verificationType === 'email' || verificationType === 'both')) return [3 /*break*/, 20];
                if (!tempUser.email) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'لم يتم تقديم بريد إلكتروني للتحقق منه'
                        })];
                }
                if (tempUser.emailVerified) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'البريد الإلكتروني مُتحقق منه مسبقاً'
                        })];
                }
                // Check rate limit for email
                if (now - lastEmailCodeTime < minInterval) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(429, {
                            success: false,
                            error: 'يرجى الانتظار دقيقة واحدة قبل طلب رمز جديد للبريد الإلكتروني'
                        })];
                }
                newEmailCode = aws_helpers_1.Utils.generateVerificationCode();
                updates.emailVerificationCode = newEmailCode;
                updates.lastEmailCodeSent = currentTime;
                _a.label = 15;
            case 15:
                _a.trys.push([15, 19, , 20]);
                if (!tempUser.email) return [3 /*break*/, 17];
                return [4 /*yield*/, aws_helpers_1.EmailHelper.sendVerificationEmail(tempUser.email, newEmailCode, tempUser.name)];
            case 16:
                _a.sent();
                messages.push('تم إرسال رمز التحقق الجديد إلى البريد الإلكتروني');
                console.log("Email verification code resent to: ".concat(tempUser.email));
                return [3 /*break*/, 18];
            case 17: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                    success: false,
                    error: 'البريد الإلكتروني غير موجود لهذا المستخدم'
                })];
            case 18: return [3 /*break*/, 20];
            case 19:
                emailError_1 = _a.sent();
                console.error('Failed to resend email:', emailError_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'فشل في إرسال رمز التحقق عبر البريد الإلكتروني'
                    })];
            case 20: 
            // Update temporary user with new codes and timestamps
            return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateTempUser(tempUserId, updates)];
            case 21:
                // Update temporary user with new codes and timestamps
                _a.sent();
                response = {
                    success: true,
                    message: messages.join(' و ')
                };
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, response)];
            case 22:
                error_2 = _a.sent();
                console.error('Resend verification error:', error_2);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء إعادة إرسال رمز التحقق'
                    })];
            case 23: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
