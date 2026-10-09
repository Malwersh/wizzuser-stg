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
    var requestBody, tempUserId, newPhone, newEmail, tempUser, currentTime, updates, messages, formattedPhone, existingUser, newPhoneCode, smsError_1, existingEmailUser, newEmailCode, emailError_1, response, error_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('Update contact info request received:', JSON.stringify(event.body));
                _a.label = 1;
            case 1:
                _a.trys.push([1, 14, , 15]);
                requestBody = JSON.parse(event.body || '{}');
                tempUserId = requestBody.tempUserId, newPhone = requestBody.newPhone, newEmail = requestBody.newEmail;
                if (!tempUserId) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'معرف المستخدم المؤقت مطلوب'
                        })];
                }
                if (!newPhone && !newEmail) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'يجب تقديم رقم هاتف جديد أو بريد إلكتروني جديد'
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
                currentTime = aws_helpers_1.Utils.getCurrentTimestamp();
                updates = { updatedAt: currentTime };
                messages = [];
                if (!newPhone) return [3 /*break*/, 7];
                formattedPhone = aws_helpers_1.Utils.formatPhoneNumber(newPhone, tempUser.countryCode);
                if (!aws_helpers_1.Utils.isValidPhone(formattedPhone)) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'رقم الهاتف الجديد غير صحيح'
                        })];
                }
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByPhone(formattedPhone)];
            case 3:
                existingUser = _a.sent();
                if (existingUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                            success: false,
                            error: 'رقم الهاتف الجديد مسجل مسبقاً'
                        })];
                }
                newPhoneCode = aws_helpers_1.Utils.generateVerificationCode();
                updates.phone = formattedPhone;
                updates.phoneVerificationCode = newPhoneCode;
                updates.phoneVerified = false;
                updates.phoneVerificationAttempts = 0;
                updates.lastPhoneCodeSent = currentTime;
                _a.label = 4;
            case 4:
                _a.trys.push([4, 6, , 7]);
                // Send SMS to new phone number
                return [4 /*yield*/, aws_helpers_1.SMSHelper.sendVerificationSMS(formattedPhone, newPhoneCode)];
            case 5:
                // Send SMS to new phone number
                _a.sent();
                messages.push("\u062A\u0645 \u0625\u0631\u0633\u0627\u0644 \u0631\u0645\u0632 \u0627\u0644\u062A\u062D\u0642\u0642 \u0625\u0644\u0649 \u0631\u0642\u0645 \u0627\u0644\u0647\u0627\u062A\u0641 \u0627\u0644\u062C\u062F\u064A\u062F: ".concat(formattedPhone));
                console.log("Phone updated and verification code sent to: ".concat(formattedPhone));
                return [3 /*break*/, 7];
            case 6:
                smsError_1 = _a.sent();
                console.error('Failed to send SMS to new phone:', smsError_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'فشل في إرسال رمز التحقق إلى رقم الهاتف الجديد'
                    })];
            case 7:
                if (!newEmail) return [3 /*break*/, 12];
                // Validate new email
                if (!aws_helpers_1.Utils.isValidEmail(newEmail)) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'عنوان البريد الإلكتروني الجديد غير صحيح'
                        })];
                }
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByEmail(newEmail)];
            case 8:
                existingEmailUser = _a.sent();
                if (existingEmailUser) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(409, {
                            success: false,
                            error: 'البريد الإلكتروني الجديد مسجل مسبقاً'
                        })];
                }
                newEmailCode = aws_helpers_1.Utils.generateVerificationCode();
                updates.email = newEmail.trim();
                updates.emailVerificationCode = newEmailCode;
                updates.emailVerified = false;
                updates.emailVerificationAttempts = 0;
                updates.lastEmailCodeSent = currentTime;
                _a.label = 9;
            case 9:
                _a.trys.push([9, 11, , 12]);
                // Send email to new email address
                return [4 /*yield*/, aws_helpers_1.EmailHelper.sendVerificationEmail(newEmail, newEmailCode, tempUser.name)];
            case 10:
                // Send email to new email address
                _a.sent();
                messages.push("\u062A\u0645 \u0625\u0631\u0633\u0627\u0644 \u0631\u0645\u0632 \u0627\u0644\u062A\u062D\u0642\u0642 \u0625\u0644\u0649 \u0627\u0644\u0628\u0631\u064A\u062F \u0627\u0644\u0625\u0644\u0643\u062A\u0631\u0648\u0646\u064A \u0627\u0644\u062C\u062F\u064A\u062F: ".concat(newEmail));
                console.log("Email updated and verification code sent to: ".concat(newEmail));
                return [3 /*break*/, 12];
            case 11:
                emailError_1 = _a.sent();
                console.error('Failed to send email to new address:', emailError_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'فشل في إرسال رمز التحقق إلى البريد الإلكتروني الجديد'
                    })];
            case 12: 
            // Update temporary user with new contact info
            return [4 /*yield*/, aws_helpers_1.DynamoHelper.updateTempUser(tempUserId, updates)];
            case 13:
                // Update temporary user with new contact info
                _a.sent();
                response = {
                    success: true,
                    message: messages.join(' و '),
                    updatedPhone: newPhone ? updates.phone : tempUser.phone,
                    updatedEmail: newEmail ? updates.email : tempUser.email,
                    phoneVerificationRequired: !!newPhone || !tempUser.phoneVerified,
                    emailVerificationRequired: !!newEmail || (tempUser.email && !tempUser.emailVerified)
                };
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, response)];
            case 14:
                error_1 = _a.sent();
                console.error('Update contact info error:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'حدث خطأ أثناء تحديث معلومات الاتصال'
                    })];
            case 15: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
