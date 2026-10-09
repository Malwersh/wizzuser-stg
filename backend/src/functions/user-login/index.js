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
    var requestBody, username, password, identifier, finalUsername, trimmedUsername, user, cognitoUsername, isEmailLogin, isPhoneLogin, formattedPhone, authResult, cognitoError_1, tempUser, isPasswordValid, authResult, currentTime, userForResponse, response, cognitoError_2, error_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('Login request received:', JSON.stringify(event.body));
                _a.label = 1;
            case 1:
                _a.trys.push([1, 17, , 18]);
                requestBody = JSON.parse(event.body || '{}');
                username = requestBody.username, password = requestBody.password, identifier = requestBody.identifier;
                finalUsername = username || identifier;
                console.log('Processing login for username:', finalUsername);
                if (!finalUsername || !password) {
                    console.log('Missing username or password');
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'اسم المستخدم وكلمة المرور مطلوبان'
                        })];
                }
                trimmedUsername = finalUsername.trim();
                console.log('Trimmed username:', trimmedUsername);
                user = null;
                cognitoUsername = '';
                isEmailLogin = false;
                isPhoneLogin = false;
                formattedPhone = '';
                console.log('Checking if username is email...');
                if (!aws_helpers_1.Utils.isValidEmail(trimmedUsername)) return [3 /*break*/, 8];
                // Email login
                console.log('Detected email login');
                isEmailLogin = true;
                cognitoUsername = trimmedUsername;
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByEmail(trimmedUsername)];
            case 2:
                // First check if user exists in DynamoDB (confirmed users)
                user = _a.sent();
                console.log('User from DynamoDB:', user ? 'found' : 'not found');
                if (!!user) return [3 /*break*/, 7];
                _a.label = 3;
            case 3:
                _a.trys.push([3, 5, , 6]);
                console.log('Checking Cognito authentication for email user');
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.authenticateUser(cognitoUsername, password)];
            case 4:
                authResult = _a.sent();
                console.log('Cognito auth result:', authResult ? 'success' : 'failed');
                // If authentication succeeds, it means user is confirmed but missing from DynamoDB (data inconsistency)
                if (authResult) {
                    console.log('User authenticated in Cognito but missing from DynamoDB');
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'خطأ في النظام. يرجى الاتصال بالدعم الفني'
                        })];
                }
                return [3 /*break*/, 6];
            case 5:
                cognitoError_1 = _a.sent();
                // Handle different Cognito error types
                if (cognitoError_1.name === 'UserNotConfirmedException') {
                    // User exists but is unconfirmed, direct to email verification
                    console.log('Email user found but unconfirmed:', trimmedUsername);
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                            success: false,
                            error: 'حسابك غير مُفعل. يرجى التحقق من البريد الإلكتروني أولاً',
                            requiresVerification: true,
                            tempUserId: cognitoUsername,
                            emailVerificationRequired: true,
                            phoneVerificationRequired: false
                        })];
                }
                else if (cognitoError_1.name === 'NotAuthorizedException') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                            success: false,
                            error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                        })];
                }
                else if (cognitoError_1.name === 'UserNotFoundException') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                            success: false,
                            error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                        })];
                }
                return [3 /*break*/, 6];
            case 6: 
            // If we reach here, user doesn't exist or credentials are wrong
            return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                    success: false,
                    error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                })];
            case 7: return [3 /*break*/, 11];
            case 8:
                // Assume it's a phone number - format and validate it
                console.log('Detected phone login, formatting phone number');
                formattedPhone = aws_helpers_1.Utils.formatPhoneNumber(trimmedUsername);
                console.log('Formatted phone:', formattedPhone);
                if (!aws_helpers_1.Utils.isValidPhone(formattedPhone)) {
                    console.log('Invalid phone format');
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'اسم المستخدم غير صحيح. يجب أن يكون بريد إلكتروني أو رقم هاتف صالح'
                        })];
                }
                // Phone login
                isPhoneLogin = true;
                cognitoUsername = formattedPhone;
                // First check if user exists in DynamoDB (confirmed users)
                console.log('Checking for confirmed phone user in DynamoDB');
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByPhone(formattedPhone)];
            case 9:
                user = _a.sent();
                console.log('Confirmed user from DynamoDB:', user ? 'found' : 'not found');
                if (!!user) return [3 /*break*/, 11];
                // User not found in permanent table, check if they exist in temp users table (unconfirmed)
                console.log('Checking for temp phone user');
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getTempUserByPhone(formattedPhone)];
            case 10:
                tempUser = _a.sent();
                console.log('Temp user found:', tempUser ? 'yes' : 'no');
                if (tempUser) {
                    // User exists but is unconfirmed, verify password and direct to phone verification
                    console.log('Phone user found but unconfirmed:', formattedPhone);
                    console.log('Verifying password for unconfirmed phone user:', formattedPhone);
                    isPasswordValid = aws_helpers_1.Utils.hashPassword(password) === tempUser.password;
                    if (!isPasswordValid) {
                        console.log('Password mismatch for user:', tempUser.tempUserId);
                        return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                                success: false,
                                error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                            })];
                    }
                    // Password is correct but user is unconfirmed - direct to phone verification WITHOUT sending new code
                    console.log('User credentials verified, directing to verification screen');
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                            success: false,
                            error: 'حسابك غير مُفعل. يرجى التحقق من رقم الهاتف أولاً',
                            requiresVerification: true,
                            tempUserId: tempUser.tempUserId,
                            emailVerificationRequired: false,
                            phoneVerificationRequired: true
                        })];
                }
                // User doesn't exist in either table
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                        success: false,
                        error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                    })];
            case 11:
                // Check if user account is active
                if (!user.isActive) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                            success: false,
                            error: 'حسابك معطل. يرجى الاتصال بالدعم الفني'
                        })];
                }
                _a.label = 12;
            case 12:
                _a.trys.push([12, 15, , 16]);
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.authenticateUser(user.cognitoUsername, password)];
            case 13:
                authResult = _a.sent();
                if (!authResult) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                            success: false,
                            error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                        })];
                }
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateUser(user.userId, {
                        lastLoginAt: currentTime,
                        updatedAt: currentTime
                    })];
            case 14:
                _a.sent();
                userForResponse = {
                    userId: user.userId,
                    name: user.name,
                    phone: user.phone,
                    email: user.email,
                    birthDate: user.birthDate,
                    gender: user.gender,
                    countryCode: user.countryCode,
                    profileImage: user.profileImage,
                    isActive: user.isActive,
                    lastLoginAt: currentTime,
                    preferredLanguage: user.preferredLanguage || 'ar',
                    addresses: user.addresses || [],
                    paymentMethods: user.paymentMethods || [],
                    cognitoUsername: user.cognitoUsername,
                    termsAccepted: user.termsAccepted,
                    privacyAccepted: user.privacyAccepted,
                    marketingConsent: user.marketingConsent,
                    createdAt: user.createdAt,
                    updatedAt: currentTime
                };
                response = {
                    success: true,
                    message: "\u0645\u0631\u062D\u0628\u0627\u064B \u0628\u0643 ".concat(user.name, "!"),
                    user: userForResponse,
                    accessToken: authResult.AccessToken,
                    refreshToken: authResult.RefreshToken
                };
                console.log('Login successful for user:', user.userId);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, response)];
            case 15:
                cognitoError_2 = _a.sent();
                console.error('Cognito authentication error:', cognitoError_2);
                // Handle different Cognito error types
                if (cognitoError_2.name === 'NotAuthorizedException') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                            success: false,
                            error: 'اسم المستخدم أو كلمة المرور غير صحيحة'
                        })];
                }
                else if (cognitoError_2.name === 'UserNotConfirmedException') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                            success: false,
                            error: 'حسابك غير مُفعل. يرجى التحقق من البريد الإلكتروني أو رقم الهاتف'
                        })];
                }
                else if (cognitoError_2.name === 'TooManyRequestsException') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(429, {
                            success: false,
                            error: 'تم تجاوز عدد المحاولات المسموحة. يرجى المحاولة لاحقاً'
                        })];
                }
                else {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                            success: false,
                            error: 'حدث خطأ أثناء تسجيل الدخول. يرجى المحاولة مرة أخرى'
                        })];
                }
                return [3 /*break*/, 16];
            case 16: return [3 /*break*/, 18];
            case 17:
                error_1 = _a.sent();
                console.error('Login error:', error_1);
                console.error('Error details:', JSON.stringify(error_1, null, 2));
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء تسجيل الدخول'
                    })];
            case 18: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
