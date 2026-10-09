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
var client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
var lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
var client = new client_dynamodb_1.DynamoDBClient({});
var docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
var PRODUCTS_TABLE = process.env.PRODUCTS_TABLE || 'WhizzMerchants_Products';
var handler = function (event) { return __awaiter(void 0, void 0, void 0, function () {
    var headers, categoryId, page, limit, command, result, products, error_1;
    var _a, _b, _c;
    return __generator(this, function (_d) {
        switch (_d.label) {
            case 0:
                headers = {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                    'Access-Control-Allow-Methods': 'GET,OPTIONS',
                };
                _d.label = 1;
            case 1:
                _d.trys.push([1, 3, , 4]);
                // Handle preflight requests
                if (event.httpMethod === 'OPTIONS') {
                    return [2 /*return*/, {
                            statusCode: 200,
                            headers: headers,
                            body: '',
                        }];
                }
                categoryId = (_a = event.queryStringParameters) === null || _a === void 0 ? void 0 : _a.categoryId;
                page = parseInt(((_b = event.queryStringParameters) === null || _b === void 0 ? void 0 : _b.page) || '1');
                limit = parseInt(((_c = event.queryStringParameters) === null || _c === void 0 ? void 0 : _c.limit) || '20');
                if (!categoryId) {
                    return [2 /*return*/, {
                            statusCode: 400,
                            headers: headers,
                            body: JSON.stringify({
                                error: 'Category ID is required',
                                message: 'معرف الفئة مطلوب'
                            }),
                        }];
                }
                console.log("Fetching products for category: ".concat(categoryId));
                command = new lib_dynamodb_1.ScanCommand({
                    TableName: PRODUCTS_TABLE,
                    FilterExpression: 'categoryId = :categoryId',
                    ExpressionAttributeValues: {
                        ':categoryId': categoryId,
                    },
                });
                return [4 /*yield*/, docClient.send(command)];
            case 2:
                result = _d.sent();
                if (!result.Items || result.Items.length === 0) {
                    return [2 /*return*/, {
                            statusCode: 200,
                            headers: headers,
                            body: JSON.stringify({
                                success: true,
                                products: [],
                                count: 0,
                                message: 'لا توجد منتجات في هذه الفئة'
                            }),
                        }];
                }
                products = result.Items.map(function (item) { return ({
                    productId: item.productId,
                    categoryId: item.categoryId,
                    businessId: item.businessId,
                    name: item.name,
                    description: item.description,
                    price: item.price,
                    imageUrl: item.imageUrl || '', // إصلاح: استخدام imageUrl من قاعدة البيانات
                    is_available: item.isAvailable !== undefined ? item.isAvailable : true, // إصلاح: استخدام isAvailable من قاعدة البيانات
                    created_at: item.createdAt,
                    updated_at: item.updatedAt,
                }); });
                // Sort products by name
                products.sort(function (a, b) { return a.name.localeCompare(b.name); });
                return [2 /*return*/, {
                        statusCode: 200,
                        headers: headers,
                        body: JSON.stringify({
                            success: true,
                            products: products,
                            count: products.length
                        }),
                    }];
            case 3:
                error_1 = _d.sent();
                console.error('Error fetching products:', error_1);
                return [2 /*return*/, {
                        statusCode: 500,
                        headers: headers,
                        body: JSON.stringify({
                            error: 'Internal server error',
                            message: 'خطأ في الخادم الداخلي',
                            details: error_1 instanceof Error ? error_1.message : 'Unknown error'
                        }),
                    }];
            case 4: return [2 /*return*/];
        }
    });
}); };
exports.handler = handler;
