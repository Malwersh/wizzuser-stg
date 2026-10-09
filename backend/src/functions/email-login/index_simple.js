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
    var requestBody, email, password, authResult, userData, authError_1, error_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                console.log('Email login request received:', JSON.stringify(event.body));
                _a.label = 1;
            case 1:
                _a.trys.push([1, 7, , 8]);
                requestBody = JSON.parse(event.body || '{}');
                email = requestBody.email, password = requestBody.password;
                // Validate input
                if (!email || !password) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'البريد الإلكتروني وكلمة المرور مطلوبان'
                        })];
                }
                // Validate email format
                if (!aws_helpers_1.Utils.isValidEmail(email)) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(400, {
                            success: false,
                            error: 'صيغة البريد الإلكتروني غير صحيحة'
                        })];
                }
                console.log("Attempting email login for: ".concat(email));
                _a.label = 2;
            case 2:
                _a.trys.push([2, 5, , 6]);
                return [4 /*yield*/, aws_helpers_1.CognitoHelper.authenticateUser(email, password)];
            case 3:
                authResult = _a.sent();
                if (!authResult) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                            success: false,
                            error: 'البريد الإلكتروني أو كلمة المرور غير صحيحة'
                        })];
                }
                return [4 /*yield*/, aws_helpers_1.DynamoHelper.getUserByEmail(email)];
            case 4:
                userData = _a.sent();
                if (userData) {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(200, {
                            success: true,
                            message: 'تم تسجيل الدخول بنجاح',
                            user: {
                                userId: userData.userId,
                                name: userData.name,
                                email: userData.email,
                                phone: userData.phone
                            },
                            tokens: {
                                accessToken: authResult.AccessToken,
                                refreshToken: authResult.RefreshToken,
                                idToken: authResult.IdToken
                            }
                        })];
                }
                else {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(404, {
                            success: false,
                            error: 'بيانات المستخدم غير موجودة'
                        })];
                }
                return [3 /*break*/, 6];
            case 5:
                authError_1 = _a.sent();
                console.error('Authentication failed:', authError_1);
                if (authError_1.name === 'UserNotConfirmedException') {
                    return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(403, {
                            success: false,
                            error: 'يجب تأكيد البريد الإلكتروني أولاً',
                            requiresVerification: true,
                            email: email
                        })];
                }
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(401, {
                        success: false,
                        error: 'البريد الإلكتروني أو كلمة المرور غير صحيحة'
                    })];
            case 6: return [3 /*break*/, 8];
            case 7:
                error_1 = _a.sent();
                console.error('Email login error:', error_1);
                return [2 /*return*/, aws_helpers_1.Utils.createAPIResponse(500, {
                        success: false,
                        error: 'خطأ في الخادم الداخلي'
                    })];
            case 8: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
