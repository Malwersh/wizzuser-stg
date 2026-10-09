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
    var requestBody, name_1, password, termsAccepted, privacyAccepted, registrationType, formattedPhone, validatedEmail, existingTempUser, newVerificationCode, currentTime_1, smsError_1, cognitoPhoneCheck, existingUser_1, existingUser, cognitoEmailCheck, existingUser, cognitoResult, autoResendSuccess, _a, CognitoIdentityProviderClient, ResendConfirmationCodeCommand, cognitoClient, command, resendError_1, response_1, error_1, phoneVerificationCode, tempUserId, currentTime, tempUser, error_2, response, error_3;
    return __generator(this, function (_b) {
        switch (_b.label) {
            case 0:
                console.log('Registration request received:', JSON.stringify(event));
                console.log('HTTP Method:', event.httpMethod);
                console.log('Headers:', JSON.stringify(event.headers));
                // Handle CORS preflight request
                if (event.httpMethod === 'OPTIONS') {
                    return [2 /*return*/, {
                            statusCode: 200,
                            headers: {
                                'Access-Control-Allow-Origin': '*',
                                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET',
                                'Access-Control-Max-Age': '86400'
                            },
                            body: JSON.stringify({ message: 'OK' })
                        }];
                }
                _b.label = 1;
            case 1:
                _b.trys.push([1, 33, , 34]);
                requestBody = JSON.parse(event.body || '{}');
                name_1 = requestBody.name, password = requestBody.password, termsAccepted = requestBody.termsAccepted, privacyAccepted = requestBody.privacyAccepted, registrationType = requestBody.registrationType;
                if (!name_1 || !password) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'الاسم وكلمة المرور مطلوبان'
                        })];
                }
                if (!termsAccepted || !privacyAccepted) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'يجب الموافقة على الشروط والأحكام وسياسة الخصوصية'
                        })];
                }
                // Validate registration type and required field
                if (registrationType === 'phone') {
                    if (!requestBody.phone) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'رقم الهاتف مطلوب للتسجيل بالهاتف'
                            })];
                    }
                }
                else if (registrationType === 'email') {
                    if (!requestBody.email) {
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                                success: false,
                                error: 'البريد الإلكتروني مطلوب للتسجيل بالإيميل'
                            })];
                    }
                }
                else {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'نوع التسجيل غير صحيح. يجب أن يكون phone أو email'
                        })];
                }
                formattedPhone = '';
                validatedEmail = '';
                if (!(registrationType === 'phone')) return [3 /*break*/, 12];
                formattedPhone = aws_helpers_1.Utils.formatPhoneNumber(requestBody.phone, requestBody.countryCode);
                if (!aws_helpers_1.Utils.isValidPhone(formattedPhone)) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'رقم الهاتف غير صحيح'
                        })];
                }
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getTempUserByPhone(formattedPhone)];
            case 2:
                existingTempUser = _b.sent();
                if (!existingTempUser) return [3 /*break*/, 7];
                _b.label = 3;
            case 3:
                _b.trys.push([3, 6, , 7]);
                newVerificationCode = aws_helpers_1.Utils.generateVerificationCode();
                currentTime_1 = aws_helpers_1.Utils.getCurrentTimestamp();
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateTempUser(existingTempUser.tempUserId, {
                        phoneVerificationCode: newVerificationCode,
                        lastPhoneCodeSent: currentTime_1,
                        updatedAt: currentTime_1
                    })];
            case 4:
                _b.sent();
                // Send new SMS verification code
                return [4 /*yield*/, aws_helpers_1.SMSHelper.sendVerificationSMS(formattedPhone, newVerificationCode)];
            case 5:
                // Send new SMS verification code
                _b.sent();
                console.log('New SMS verification code sent to existing temp user:', formattedPhone);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                        success: false,
                        error: 'يوجد حساب غير مؤكد بهذا الرقم. تم إرسال رمز تحقق جديد',
                        tempUserId: existingTempUser.tempUserId,
                        phoneVerificationRequired: true,
                        emailVerificationRequired: false,
                        requiresVerification: true,
                        message: 'تم إرسال رمز التحقق الجديد بنجاح'
                    })];
            case 6:
                smsError_1 = _b.sent();
                console.error('Failed to send SMS verification code to existing user:', smsError_1);
                // Even if SMS fails, still direct to verification screen
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                        success: false,
                        error: 'يوجد حساب غير مؤكد بهذا الرقم. يرجى التحقق من رسائلك لتأكيد الحساب',
                        tempUserId: existingTempUser.tempUserId,
                        phoneVerificationRequired: true,
                        emailVerificationRequired: false,
                        requiresVerification: true
                    })];
            case 7: return [4 /*yield*/, aws_helpers_1.CognitoHelper.checkUserExistsByPhone(formattedPhone)];
            case 8:
                cognitoPhoneCheck = _b.sent();
                if (!cognitoPhoneCheck.exists) return [3 /*break*/, 10];
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByPhone(formattedPhone)];
            case 9:
                existingUser_1 = _b.sent();
                if (!existingUser_1) {
                    console.warn("Phone ".concat(formattedPhone, " exists in Cognito but not in users table. Data inconsistency detected."));
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                            success: false,
                            error: 'رقم الهاتف مسجل مسبقاً'
                        })];
                }
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                        success: false,
                        error: 'رقم الهاتف مسجل مسبقاً'
                    })];
            case 10: return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByPhone(formattedPhone)];
            case 11:
                existingUser = _b.sent();
                if (existingUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                            success: false,
                            error: 'رقم الهاتف مسجل مسبقاً'
                        })];
                }
                _b.label = 12;
            case 12:
                if (!(registrationType === 'email')) return [3 /*break*/, 15];
                validatedEmail = requestBody.email.toLowerCase().trim();
                if (!aws_helpers_1.Utils.isValidEmail(validatedEmail)) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'عنوان البريد الإلكتروني غير صحيح'
                        })];
                }
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.checkUserExistsByEmail(validatedEmail)];
            case 13:
                cognitoEmailCheck = _b.sent();
                console.log("Cognito check result for ".concat(validatedEmail, ":"), JSON.stringify(cognitoEmailCheck));
                if (cognitoEmailCheck.exists) {
                    if (!cognitoEmailCheck.isConfirmed) {
                        // User exists but is unconfirmed - guide them to verification
                        console.log("Found unconfirmed user ".concat(validatedEmail, ", guiding to verification"));
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                                success: false,
                                error: 'يوجد حساب غير مؤكد بهذا البريد الإلكتروني',
                                requiresVerification: true,
                                tempUserId: validatedEmail, // Use email as identifier
                                emailVerificationRequired: true,
                                phoneVerificationRequired: false,
                                message: 'يرجى التحقق من بريدك الإلكتروني أو طلب إعادة إرسال رمز التحقق'
                            })];
                    }
                    else {
                        // User exists and is confirmed
                        console.log("Found confirmed user ".concat(validatedEmail, ", directing to login"));
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                                success: false,
                                error: 'البريد الإلكتروني مسجل مسبقاً ومؤكد',
                                shouldLogin: true,
                                message: 'يمكنك تسجيل الدخول باستخدام هذا البريد الإلكتروني'
                            })];
                    }
                }
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByEmail(validatedEmail)];
            case 14:
                existingUser = _b.sent();
                if (existingUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                            success: false,
                            error: 'البريد الإلكتروني مسجل مسبقاً في النظام',
                            shouldLogin: true,
                            message: 'يمكنك تسجيل الدخول باستخدام هذا البريد الإلكتروني'
                        })];
                }
                _b.label = 15;
            case 15:
                if (!(registrationType === 'email')) return [3 /*break*/, 26];
                _b.label = 16;
            case 16:
                _b.trys.push([16, 25, , 26]);
                console.log('Creating Cognito user for email registration...');
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.signUpUser(validatedEmail, // username
                    password, name_1, validatedEmail, undefined, // phone not needed for email registration
                    requestBody.marketingConsent || false, requestBody.birthDate, requestBody.gender, requestBody.countryCode || '+964', termsAccepted, privacyAccepted)];
            case 17:
                cognitoResult = _b.sent();
                if (!!cognitoResult.success) return [3 /*break*/, 24];
                console.error('Cognito SignUp failed:', cognitoResult.error);
                if (!(cognitoResult.userExists && cognitoResult.isUnconfirmed)) return [3 /*break*/, 23];
                console.log("User ".concat(validatedEmail, " exists but is unconfirmed, redirecting to verification"));
                autoResendSuccess = false;
                _b.label = 18;
            case 18:
                _b.trys.push([18, 21, , 22]);
                return [4 /*yield*/, Promise.resolve().then(function () { return require('@aws-sdk/client-cognito-identity-provider'); })];
            case 19:
                _a = _b.sent(), CognitoIdentityProviderClient = _a.CognitoIdentityProviderClient, ResendConfirmationCodeCommand = _a.ResendConfirmationCodeCommand;
                cognitoClient = new CognitoIdentityProviderClient({
                    region: process.env.AWS_REGION || 'us-east-1'
                });
                command = new ResendConfirmationCodeCommand({
                    ClientId: process.env.USER_POOL_CLIENT_ID,
                    Username: validatedEmail,
                });
                return [4 /*yield*/, cognitoClient.send(command)];
            case 20:
                _b.sent();
                console.log("Verification code resent automatically to ".concat(validatedEmail));
                autoResendSuccess = true;
                return [3 /*break*/, 22];
            case 21:
                resendError_1 = _b.sent();
                console.warn('Failed to auto-resend verification code:', resendError_1);
                return [3 /*break*/, 22];
            case 22: return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                    success: false,
                    error: 'يوجد حساب غير مؤكد بهذا البريد الإلكتروني',
                    requiresVerification: true,
                    tempUserId: validatedEmail,
                    emailVerificationRequired: true,
                    phoneVerificationRequired: false,
                    message: autoResendSuccess
                        ? 'تم إرسال رمز التحقق مرة أخرى إلى بريدك الإلكتروني. يرجى التحقق من صندوق البريد والرسائل المهملة'
                        : 'يرجى التحقق من بريدك الإلكتروني أو طلب إعادة إرسال رمز التحقق'
                })];
            case 23:
                // Handle the case where user exists and is confirmed
                if (cognitoResult.userExists && !cognitoResult.isUnconfirmed) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                            success: false,
                            error: 'البريد الإلكتروني مسجل مسبقاً ومؤكد',
                            shouldLogin: true,
                            message: 'يمكنك تسجيل الدخول باستخدام هذا البريد الإلكتروني'
                        })];
                }
                // Other errors
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: cognitoResult.error || 'فشل في إرسال رمز التحقق عبر البريد الإلكتروني'
                    })];
            case 24:
                console.log('Cognito user created successfully, verification email sent automatically');
                response_1 = {
                    success: true,
                    message: 'تم إنشاء الحساب بنجاح. يرجى التحقق من البريد الإلكتروني',
                    tempUserId: validatedEmail, // Use email as identifier for email registration
                    phoneVerificationRequired: false,
                    emailVerificationRequired: true
                };
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(201, response_1)];
            case 25:
                error_1 = _b.sent();
                console.error('Failed to create Cognito user:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'فشل في إرسال رمز التحقق عبر البريد الإلكتروني'
                    })];
            case 26:
                phoneVerificationCode = aws_helpers_1.Utils.generateVerificationCode();
                tempUserId = aws_helpers_1.Utils.generateTempUserId();
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                tempUser = {
                    tempUserId: tempUserId,
                    name: name_1.trim(),
                    phone: formattedPhone,
                    email: undefined, // Phone registration doesn't use email
                    password: aws_helpers_1.Utils.hashPassword(password), // Hash password before storing
                    birthDate: requestBody.birthDate,
                    gender: requestBody.gender,
                    countryCode: requestBody.countryCode || '+964',
                    // Verification codes and status (phone only)
                    phoneVerificationCode: phoneVerificationCode,
                    emailVerificationCode: undefined,
                    phoneVerified: false,
                    emailVerified: true, // Not using email for phone registration
                    // Consent flags
                    termsAccepted: termsAccepted,
                    privacyAccepted: privacyAccepted,
                    marketingConsent: requestBody.marketingConsent || false,
                    // Metadata
                    createdAt: currentTime,
                    updatedAt: currentTime,
                    ttl: aws_helpers_1.Utils.getTTLTimestamp(24), // 24 hours expiry
                    // Verification tracking
                    phoneVerificationAttempts: 0,
                    emailVerificationAttempts: 0,
                    lastPhoneCodeSent: currentTime,
                    lastEmailCodeSent: undefined
                };
                // Save to DynamoDB temp users table
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.createTempUser(tempUser)];
            case 27:
                // Save to DynamoDB temp users table
                _b.sent();
                _b.label = 28;
            case 28:
                _b.trys.push([28, 30, , 32]);
                return [4 /*yield*/, aws_helpers_1.SMSHelper.sendVerificationSMS(formattedPhone, phoneVerificationCode)];
            case 29:
                _b.sent();
                console.log('SMS verification code sent successfully');
                return [3 /*break*/, 32];
            case 30:
                error_2 = _b.sent();
                console.error('Failed to send SMS verification:', error_2);
                // Delete temp user if verification sending failed
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.deleteTempUser(tempUserId)];
            case 31:
                // Delete temp user if verification sending failed
                _b.sent();
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'فشل في إرسال رمز التحقق عبر الرسائل النصية'
                    })];
            case 32:
                response = {
                    success: true,
                    message: 'تم إنشاء الحساب بنجاح. يرجى التحقق من رقم الهاتف',
                    tempUserId: tempUserId,
                    phoneVerificationRequired: true,
                    emailVerificationRequired: false
                };
                console.log('Phone registration successful for tempUserId:', tempUserId);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(201, response)];
            case 33:
                error_3 = _b.sent();
                console.error('Registration error:', error_3);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء إنشاء الحساب. يرجى المحاولة مرة أخرى'
                    })];
            case 34: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
