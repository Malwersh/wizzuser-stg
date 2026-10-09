"use strict";
// AWS Services Helper Functions
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
exports.Utils = exports.EmailHelper = exports.SMSHelper = exports.CognitoHelper = exports.DynamoHelper = void 0;
var client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
var lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
var client_cognito_identity_provider_1 = require("@aws-sdk/client-cognito-identity-provider");
var client_sns_1 = require("@aws-sdk/client-sns");
var client_ses_1 = require("@aws-sdk/client-ses");
var crypto_1 = require("crypto");
// Initialize AWS clients
var dynamoClient = lib_dynamodb_1.DynamoDBDocumentClient.from(new client_dynamodb_1.DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' }), {
    marshallOptions: {
        removeUndefinedValues: true,
    },
});
var cognitoClient = new client_cognito_identity_provider_1.CognitoIdentityProviderClient({ region: process.env.AWS_REGION || 'us-east-1' });
var snsClient = new client_sns_1.SNSClient({ region: process.env.AWS_REGION || 'us-east-1' });
var sesClient = new client_ses_1.SESClient({ region: process.env.AWS_REGION || 'us-east-1' });
// Environment variables
var USERS_TABLE = process.env.USERS_TABLE;
var TEMP_USERS_TABLE = process.env.TEMP_USERS_TABLE;
var USER_POOL_ID = process.env.USER_POOL_ID;
var USER_POOL_CLIENT_ID = process.env.USER_POOL_CLIENT_ID;
/**
 * DynamoDB Helper Functions
 */
var DynamoHelper = /** @class */ (function () {
    function DynamoHelper() {
    }
    // Temp Users Table Operations
    DynamoHelper.createTempUser = function (tempUser) {
        return __awaiter(this, void 0, void 0, function () {
            var command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.PutCommand({
                            TableName: TEMP_USERS_TABLE,
                            Item: tempUser
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    DynamoHelper.getTempUser = function (tempUserId) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.GetCommand({
                            TableName: TEMP_USERS_TABLE,
                            Key: { tempUserId: tempUserId }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        return [2 /*return*/, result.Item || null];
                }
            });
        });
    };
    DynamoHelper.updateTempUser = function (tempUserId, updates) {
        return __awaiter(this, void 0, void 0, function () {
            var updateExpression, expressionAttributeNames, expressionAttributeValues, _i, _a, _b, key, value, command;
            return __generator(this, function (_c) {
                switch (_c.label) {
                    case 0:
                        updateExpression = [];
                        expressionAttributeNames = {};
                        expressionAttributeValues = {};
                        for (_i = 0, _a = Object.entries(updates); _i < _a.length; _i++) {
                            _b = _a[_i], key = _b[0], value = _b[1];
                            updateExpression.push("#".concat(key, " = :").concat(key));
                            expressionAttributeNames["#".concat(key)] = key;
                            expressionAttributeValues[":".concat(key)] = value;
                        }
                        command = new lib_dynamodb_1.UpdateCommand({
                            TableName: TEMP_USERS_TABLE,
                            Key: { tempUserId: tempUserId },
                            UpdateExpression: "SET ".concat(updateExpression.join(', ')),
                            ExpressionAttributeNames: expressionAttributeNames,
                            ExpressionAttributeValues: expressionAttributeValues
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _c.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    DynamoHelper.deleteTempUser = function (tempUserId) {
        return __awaiter(this, void 0, void 0, function () {
            var command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.DeleteCommand({
                            TableName: TEMP_USERS_TABLE,
                            Key: { tempUserId: tempUserId }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    // Check for existing temp user by phone
    DynamoHelper.getTempUserByPhone = function (phone) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        command = new lib_dynamodb_1.ScanCommand({
                            TableName: TEMP_USERS_TABLE,
                            FilterExpression: 'phone = :phone',
                            ExpressionAttributeValues: { ':phone': phone }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _b.sent();
                        return [2 /*return*/, ((_a = result.Items) === null || _a === void 0 ? void 0 : _a[0]) || null];
                }
            });
        });
    };
    // Check for existing temp user by email
    DynamoHelper.getTempUserByEmail = function (email) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        command = new lib_dynamodb_1.ScanCommand({
                            TableName: TEMP_USERS_TABLE,
                            FilterExpression: 'email = :email',
                            ExpressionAttributeValues: { ':email': email }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _b.sent();
                        return [2 /*return*/, ((_a = result.Items) === null || _a === void 0 ? void 0 : _a[0]) || null];
                }
            });
        });
    };
    // Users Table Operations
    DynamoHelper.createUser = function (user) {
        return __awaiter(this, void 0, void 0, function () {
            var command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.PutCommand({
                            TableName: USERS_TABLE,
                            Item: user
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    DynamoHelper.getUser = function (userId) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.GetCommand({
                            TableName: USERS_TABLE,
                            Key: { userId: userId }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        return [2 /*return*/, result.Item || null];
                }
            });
        });
    };
    DynamoHelper.getUserByEmail = function (email) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        command = new lib_dynamodb_1.QueryCommand({
                            TableName: USERS_TABLE,
                            IndexName: 'email-index',
                            KeyConditionExpression: 'email = :email',
                            ExpressionAttributeValues: { ':email': email }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _b.sent();
                        return [2 /*return*/, ((_a = result.Items) === null || _a === void 0 ? void 0 : _a[0]) || null];
                }
            });
        });
    };
    DynamoHelper.getUserByPhone = function (phone) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        command = new lib_dynamodb_1.QueryCommand({
                            TableName: USERS_TABLE,
                            IndexName: 'phone-index',
                            KeyConditionExpression: 'phone = :phone',
                            ExpressionAttributeValues: { ':phone': phone }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _b.sent();
                        return [2 /*return*/, ((_a = result.Items) === null || _a === void 0 ? void 0 : _a[0]) || null];
                }
            });
        });
    };
    DynamoHelper.updateUser = function (userId, updates) {
        return __awaiter(this, void 0, void 0, function () {
            var updateExpression, expressionAttributeNames, expressionAttributeValues, _i, _a, _b, key, value, command;
            return __generator(this, function (_c) {
                switch (_c.label) {
                    case 0:
                        updateExpression = [];
                        expressionAttributeNames = {};
                        expressionAttributeValues = {};
                        for (_i = 0, _a = Object.entries(updates); _i < _a.length; _i++) {
                            _b = _a[_i], key = _b[0], value = _b[1];
                            updateExpression.push("#".concat(key, " = :").concat(key));
                            expressionAttributeNames["#".concat(key)] = key;
                            expressionAttributeValues[":".concat(key)] = value;
                        }
                        command = new lib_dynamodb_1.UpdateCommand({
                            TableName: USERS_TABLE,
                            Key: { userId: userId },
                            UpdateExpression: "SET ".concat(updateExpression.join(', ')),
                            ExpressionAttributeNames: expressionAttributeNames,
                            ExpressionAttributeValues: expressionAttributeValues
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _c.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    // Password Reset Tokens Table Operations
    DynamoHelper.createPasswordResetToken = function (resetData) {
        return __awaiter(this, void 0, void 0, function () {
            var command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.PutCommand({
                            TableName: 'PasswordResetTokens', // We'll need to create this table
                            Item: resetData
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    DynamoHelper.getPasswordResetToken = function (resetToken) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.GetCommand({
                            TableName: 'PasswordResetTokens',
                            Key: { resetToken: resetToken }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        return [2 /*return*/, result.Item || null];
                }
            });
        });
    };
    DynamoHelper.updatePasswordResetToken = function (resetToken, updates) {
        return __awaiter(this, void 0, void 0, function () {
            var updateExpression, expressionAttributeNames, expressionAttributeValues, _i, _a, _b, key, value, command;
            return __generator(this, function (_c) {
                switch (_c.label) {
                    case 0:
                        updateExpression = [];
                        expressionAttributeNames = {};
                        expressionAttributeValues = {};
                        for (_i = 0, _a = Object.entries(updates); _i < _a.length; _i++) {
                            _b = _a[_i], key = _b[0], value = _b[1];
                            updateExpression.push("#".concat(key, " = :").concat(key));
                            expressionAttributeNames["#".concat(key)] = key;
                            expressionAttributeValues[":".concat(key)] = value;
                        }
                        command = new lib_dynamodb_1.UpdateCommand({
                            TableName: 'PasswordResetTokens',
                            Key: { resetToken: resetToken },
                            UpdateExpression: "SET ".concat(updateExpression.join(', ')),
                            ExpressionAttributeNames: expressionAttributeNames,
                            ExpressionAttributeValues: expressionAttributeValues
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _c.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    DynamoHelper.deletePasswordResetToken = function (resetToken) {
        return __awaiter(this, void 0, void 0, function () {
            var command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new lib_dynamodb_1.DeleteCommand({
                            TableName: 'PasswordResetTokens',
                            Key: { resetToken: resetToken }
                        });
                        return [4 /*yield*/, dynamoClient.send(command)];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    return DynamoHelper;
}());
exports.DynamoHelper = DynamoHelper;
/**
 * Cognito Helper Functions
 */
var CognitoHelper = /** @class */ (function () {
    function CognitoHelper() {
    }
    CognitoHelper.createCognitoUser = function (primaryIdentifier, email, password, name, phone) {
        return __awaiter(this, void 0, void 0, function () {
            var isPhoneRegistration, username, userAttributes, createCommand, setPasswordCommand;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        isPhoneRegistration = phone && Utils.isValidPhone(phone);
                        username = isPhoneRegistration ? phone : primaryIdentifier;
                        userAttributes = [
                            { Name: 'name', Value: name }
                        ];
                        // Add phone attributes if phone registration
                        if (isPhoneRegistration && phone) {
                            userAttributes.push({ Name: 'phone_number', Value: phone }, { Name: 'phone_number_verified', Value: 'true' });
                        }
                        // Add email attributes if email is provided
                        if (email) {
                            userAttributes.push({ Name: 'email', Value: email }, { Name: 'email_verified', Value: 'true' });
                        }
                        createCommand = new client_cognito_identity_provider_1.AdminCreateUserCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: username,
                            MessageAction: 'SUPPRESS', // Don't send welcome email
                            UserAttributes: userAttributes
                        });
                        return [4 /*yield*/, cognitoClient.send(createCommand)];
                    case 1:
                        _a.sent();
                        setPasswordCommand = new client_cognito_identity_provider_1.AdminSetUserPasswordCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: username,
                            Password: password,
                            Permanent: true
                        });
                        return [4 /*yield*/, cognitoClient.send(setPasswordCommand)];
                    case 2:
                        _a.sent();
                        return [2 /*return*/, username];
                }
            });
        });
    };
    CognitoHelper.authenticateUser = function (username, password) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        command = new client_cognito_identity_provider_1.AdminInitiateAuthCommand({
                            UserPoolId: USER_POOL_ID,
                            ClientId: USER_POOL_CLIENT_ID,
                            AuthFlow: 'ADMIN_NO_SRP_AUTH',
                            AuthParameters: {
                                USERNAME: username,
                                PASSWORD: password
                            }
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        return [2 /*return*/, result.AuthenticationResult];
                }
            });
        });
    };
    /**
     * Check if a user exists in Cognito by phone number
     */
    CognitoHelper.checkUserExistsByPhone = function (phone) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result, user, error_1;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 2, , 3]);
                        command = new client_cognito_identity_provider_1.ListUsersCommand({
                            UserPoolId: USER_POOL_ID,
                            Filter: "phone_number = \"".concat(phone, "\"")
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        if (result.Users && result.Users.length > 0) {
                            user = result.Users[0];
                            return [2 /*return*/, {
                                    exists: true,
                                    username: user.Username,
                                    status: user.UserStatus
                                }];
                        }
                        return [2 /*return*/, { exists: false }];
                    case 2:
                        error_1 = _a.sent();
                        console.error('Error checking user by phone:', error_1);
                        return [2 /*return*/, { exists: false }];
                    case 3: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Check if a user exists in Cognito by email with detailed status
     * Uses AdminGetUser as a fallback since ListUsers may have eventual consistency issues
     */
    CognitoHelper.checkUserExistsByEmail = function (email) {
        return __awaiter(this, void 0, void 0, function () {
            var listCommand, listResult, user, userStatus, isConfirmed, canReregister, getUserCommand, getUserResult, userStatus, isConfirmed, canReregister, getUserError_1, error_2;
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        _b.trys.push([0, 6, , 7]);
                        listCommand = new client_cognito_identity_provider_1.ListUsersCommand({
                            UserPoolId: USER_POOL_ID,
                            Filter: "email = \"".concat(email, "\"")
                        });
                        return [4 /*yield*/, cognitoClient.send(listCommand)];
                    case 1:
                        listResult = _b.sent();
                        console.log("Checking email ".concat(email, " in Cognito with ListUsers. Found ").concat(((_a = listResult.Users) === null || _a === void 0 ? void 0 : _a.length) || 0, " users"));
                        if (listResult.Users && listResult.Users.length > 0) {
                            user = listResult.Users[0];
                            userStatus = user.UserStatus;
                            isConfirmed = userStatus === 'CONFIRMED';
                            canReregister = userStatus === 'UNCONFIRMED' || userStatus === 'FORCE_CHANGE_PASSWORD';
                            console.log("User found with ListUsers: ".concat(email, ", Status: ").concat(userStatus, ", IsConfirmed: ").concat(isConfirmed, ", Can reregister: ").concat(canReregister));
                            return [2 /*return*/, {
                                    exists: true,
                                    username: user.Username,
                                    status: userStatus,
                                    isConfirmed: isConfirmed,
                                    canReregister: canReregister
                                }];
                        }
                        _b.label = 2;
                    case 2:
                        _b.trys.push([2, 4, , 5]);
                        getUserCommand = new client_cognito_identity_provider_1.AdminGetUserCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: email
                        });
                        return [4 /*yield*/, cognitoClient.send(getUserCommand)];
                    case 3:
                        getUserResult = _b.sent();
                        userStatus = getUserResult.UserStatus;
                        isConfirmed = userStatus === 'CONFIRMED';
                        canReregister = userStatus === 'UNCONFIRMED' || userStatus === 'FORCE_CHANGE_PASSWORD';
                        console.log("User found with AdminGetUser: ".concat(email, ", Status: ").concat(userStatus, ", IsConfirmed: ").concat(isConfirmed, ", Can reregister: ").concat(canReregister));
                        return [2 /*return*/, {
                                exists: true,
                                username: email,
                                status: userStatus,
                                isConfirmed: isConfirmed,
                                canReregister: canReregister
                            }];
                    case 4:
                        getUserError_1 = _b.sent();
                        if (getUserError_1.name === 'UserNotFoundException') {
                            console.log("No user found in Cognito for email: ".concat(email));
                            return [2 /*return*/, { exists: false, canReregister: true }];
                        }
                        // If it's another error, log it but continue
                        console.log("AdminGetUser failed for ".concat(email, ":"), getUserError_1.message);
                        return [3 /*break*/, 5];
                    case 5:
                        console.log("No user found in Cognito for email: ".concat(email));
                        return [2 /*return*/, { exists: false, canReregister: true }];
                    case 6:
                        error_2 = _b.sent();
                        console.error('Error checking user by email:', error_2);
                        return [2 /*return*/, { exists: false, canReregister: true }];
                    case 7: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Check if a user exists in Cognito by username
     */
    CognitoHelper.checkUserExistsByUsername = function (username) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result, error_3;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 2, , 3]);
                        command = new client_cognito_identity_provider_1.AdminGetUserCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: username
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        return [2 /*return*/, {
                                exists: true,
                                status: result.UserStatus
                            }];
                    case 2:
                        error_3 = _a.sent();
                        if (error_3.name === 'UserNotFoundException') {
                            return [2 /*return*/, { exists: false }];
                        }
                        console.error('Error checking user by username:', error_3);
                        return [2 /*return*/, { exists: false }];
                    case 3: return [2 /*return*/];
                }
            });
        });
    }; /**
     * Sign up a new user using Cognito's built-in email service
     * This automatically sends verification email without SES sandbox restrictions
     */
    CognitoHelper.signUpUser = function (username, password, name, email, phone, marketingConsent, birthDate, gender, countryCode, termsAccepted, privacyAccepted) {
        return __awaiter(this, void 0, void 0, function () {
            var userAttributes, command, result, error_4, errorMessage, userExists, isUnconfirmed, userCheck, checkError_1;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 2, , 9]);
                        userAttributes = [
                            { Name: 'name', Value: name },
                            { Name: 'email', Value: email }
                        ];
                        if (phone) {
                            userAttributes.push({ Name: 'phone_number', Value: phone });
                        }
                        if (marketingConsent !== undefined) {
                            userAttributes.push({ Name: 'custom:marketing_consent', Value: marketingConsent.toString() });
                        }
                        // Add additional user attributes as custom attributes
                        if (birthDate) {
                            userAttributes.push({ Name: 'birthdate', Value: birthDate });
                        }
                        if (gender) {
                            userAttributes.push({ Name: 'gender', Value: gender });
                        }
                        // Only add marketing_consent to Cognito as custom attribute since it's defined in schema
                        // Skip other custom attributes that aren't defined in the User Pool schema
                        command = new client_cognito_identity_provider_1.SignUpCommand({
                            ClientId: USER_POOL_CLIENT_ID,
                            Username: username,
                            Password: password,
                            UserAttributes: userAttributes
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        result = _a.sent();
                        console.log('Cognito SignUp successful:', result.UserSub);
                        return [2 /*return*/, {
                                success: true,
                                userSub: result.UserSub
                            }];
                    case 2:
                        error_4 = _a.sent();
                        console.error('Cognito SignUp failed:', error_4);
                        errorMessage = 'فشل في إنشاء الحساب';
                        userExists = false;
                        isUnconfirmed = false;
                        if (!(error_4.name === 'UsernameExistsException')) return [3 /*break*/, 7];
                        userExists = true;
                        _a.label = 3;
                    case 3:
                        _a.trys.push([3, 5, , 6]);
                        return [4 /*yield*/, this.checkUserExistsByEmail(email)];
                    case 4:
                        userCheck = _a.sent();
                        if (userCheck.exists && !userCheck.isConfirmed) {
                            isUnconfirmed = true;
                            errorMessage = 'يوجد حساب غير مؤكد بهذا البريد الإلكتروني';
                        }
                        else {
                            errorMessage = 'البريد الإلكتروني مسجل مسبقاً';
                        }
                        return [3 /*break*/, 6];
                    case 5:
                        checkError_1 = _a.sent();
                        console.error('Error checking user status:', checkError_1);
                        errorMessage = 'البريد الإلكتروني مسجل مسبقاً';
                        return [3 /*break*/, 6];
                    case 6: return [3 /*break*/, 8];
                    case 7:
                        if (error_4.name === 'InvalidPasswordException') {
                            errorMessage = 'كلمة المرور لا تلبي المتطلبات المطلوبة';
                        }
                        else if (error_4.name === 'InvalidParameterException') {
                            errorMessage = 'البيانات المدخلة غير صحيحة';
                        }
                        _a.label = 8;
                    case 8: return [2 /*return*/, {
                            success: false,
                            error: errorMessage,
                            userExists: userExists,
                            isUnconfirmed: isUnconfirmed
                        }];
                    case 9: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Confirm user sign up with verification code
     */
    CognitoHelper.confirmSignUp = function (username, confirmationCode) {
        return __awaiter(this, void 0, void 0, function () {
            var command, error_5, errorMessage;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 2, , 3]);
                        command = new client_cognito_identity_provider_1.ConfirmSignUpCommand({
                            ClientId: USER_POOL_CLIENT_ID,
                            Username: username,
                            ConfirmationCode: confirmationCode
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        _a.sent();
                        console.log('Cognito ConfirmSignUp successful for:', username);
                        return [2 /*return*/, { success: true }];
                    case 2:
                        error_5 = _a.sent();
                        console.error('Cognito ConfirmSignUp failed:', error_5);
                        errorMessage = 'رمز التحقق غير صحيح';
                        if (error_5.name === 'CodeMismatchException') {
                            errorMessage = 'رمز التحقق غير صحيح';
                        }
                        else if (error_5.name === 'ExpiredCodeException') {
                            errorMessage = 'رمز التحقق منتهي الصلاحية';
                        }
                        else if (error_5.name === 'UserNotFoundException') {
                            errorMessage = 'المستخدم غير موجود';
                        }
                        return [2 /*return*/, {
                                success: false,
                                error: errorMessage
                            }];
                    case 3: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Delete unconfirmed user from Cognito
     */
    CognitoHelper.deleteUnconfirmedUser = function (username) {
        return __awaiter(this, void 0, void 0, function () {
            var userCheck, command, error_6;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 5, , 6]);
                        return [4 /*yield*/, this.checkUserExistsByUsername(username)];
                    case 1:
                        userCheck = _a.sent();
                        if (!userCheck.exists) {
                            console.log("User ".concat(username, " does not exist in Cognito, nothing to delete"));
                            return [2 /*return*/, { success: true }]; // Consider this success since the goal is achieved
                        }
                        if (!(userCheck.status === 'UNCONFIRMED' || userCheck.status === 'FORCE_CHANGE_PASSWORD')) return [3 /*break*/, 3];
                        command = new client_cognito_identity_provider_1.AdminDeleteUserCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: username
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 2:
                        _a.sent();
                        console.log("Deleted unconfirmed user ".concat(username, " from Cognito"));
                        return [2 /*return*/, { success: true }];
                    case 3:
                        console.log("User ".concat(username, " is confirmed (").concat(userCheck.status, "), not deleting"));
                        return [2 /*return*/, {
                                success: false,
                                error: 'لا يمكن حذف مستخدم مؤكد'
                            }];
                    case 4: return [3 /*break*/, 6];
                    case 5:
                        error_6 = _a.sent();
                        console.error('Error deleting unconfirmed user:', error_6);
                        if (error_6.name === 'UserNotFoundException') {
                            return [2 /*return*/, { success: true }]; // User already doesn't exist
                        }
                        return [2 /*return*/, {
                                success: false,
                                error: 'فشل في حذف المستخدم غير المؤكد'
                            }];
                    case 6: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Initiate password reset for email users using Cognito
     */
    CognitoHelper.initiatePasswordReset = function (username) {
        return __awaiter(this, void 0, void 0, function () {
            var ForgotPasswordCommand, command, error_7, errorMessage;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 3, , 4]);
                        return [4 /*yield*/, Promise.resolve().then(function () { return require('@aws-sdk/client-cognito-identity-provider'); })];
                    case 1:
                        ForgotPasswordCommand = (_a.sent()).ForgotPasswordCommand;
                        command = new ForgotPasswordCommand({
                            ClientId: USER_POOL_CLIENT_ID,
                            Username: username
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 2:
                        _a.sent();
                        console.log('Password reset initiated for:', username);
                        return [2 /*return*/, {
                                success: true,
                                resetToken: username // For email users, we use the email as the reset token
                            }];
                    case 3:
                        error_7 = _a.sent();
                        console.error('Failed to initiate password reset:', error_7);
                        errorMessage = 'فشل في إرسال رمز إعادة تعيين كلمة المرور';
                        if (error_7.name === 'UserNotFoundException') {
                            errorMessage = 'المستخدم غير موجود';
                        }
                        else if (error_7.name === 'InvalidParameterException') {
                            errorMessage = 'بيانات غير صحيحة';
                        }
                        else if (error_7.name === 'LimitExceededException') {
                            errorMessage = 'تم تجاوز حد المحاولات. يرجى المحاولة لاحقاً';
                        }
                        return [2 /*return*/, {
                                success: false,
                                error: errorMessage
                            }];
                    case 4: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Confirm password reset for email users using Cognito
     */
    CognitoHelper.confirmPasswordReset = function (username, confirmationCode, newPassword) {
        return __awaiter(this, void 0, void 0, function () {
            var ConfirmForgotPasswordCommand, command, error_8, errorMessage;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 3, , 4]);
                        return [4 /*yield*/, Promise.resolve().then(function () { return require('@aws-sdk/client-cognito-identity-provider'); })];
                    case 1:
                        ConfirmForgotPasswordCommand = (_a.sent()).ConfirmForgotPasswordCommand;
                        command = new ConfirmForgotPasswordCommand({
                            ClientId: USER_POOL_CLIENT_ID,
                            Username: username,
                            ConfirmationCode: confirmationCode,
                            Password: newPassword
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 2:
                        _a.sent();
                        console.log('Password reset confirmed for:', username);
                        return [2 /*return*/, { success: true }];
                    case 3:
                        error_8 = _a.sent();
                        console.error('Failed to confirm password reset:', error_8);
                        errorMessage = 'رمز التحقق غير صحيح أو منتهي الصلاحية';
                        if (error_8.name === 'CodeMismatchException') {
                            errorMessage = 'رمز التحقق غير صحيح';
                        }
                        else if (error_8.name === 'ExpiredCodeException') {
                            errorMessage = 'رمز التحقق منتهي الصلاحية';
                        }
                        else if (error_8.name === 'UserNotFoundException') {
                            errorMessage = 'المستخدم غير موجود';
                        }
                        else if (error_8.name === 'InvalidPasswordException') {
                            errorMessage = 'كلمة المرور الجديدة غير صالحة';
                        }
                        return [2 /*return*/, {
                                success: false,
                                error: errorMessage
                            }];
                    case 4: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Set user password in Cognito (for phone users)
     */
    CognitoHelper.setUserPassword = function (cognitoUsername, newPassword) {
        return __awaiter(this, void 0, void 0, function () {
            var command, error_9, errorMessage;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 2, , 3]);
                        command = new client_cognito_identity_provider_1.AdminSetUserPasswordCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: cognitoUsername,
                            Password: newPassword,
                            Permanent: true
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        _a.sent();
                        console.log('Password updated for user:', cognitoUsername);
                        return [2 /*return*/, { success: true }];
                    case 2:
                        error_9 = _a.sent();
                        console.error('Failed to set user password:', error_9);
                        errorMessage = 'فشل في تحديث كلمة المرور';
                        if (error_9.name === 'UserNotFoundException') {
                            errorMessage = 'المستخدم غير موجود';
                        }
                        else if (error_9.name === 'InvalidParameterException') {
                            errorMessage = 'كلمة المرور غير صالحة';
                        }
                        else if (error_9.name === 'InvalidPasswordException') {
                            errorMessage = 'كلمة المرور الجديدة لا تلبي متطلبات الأمان';
                        }
                        return [2 /*return*/, {
                                success: false,
                                error: errorMessage
                            }];
                    case 3: return [2 /*return*/];
                }
            });
        });
    };
    /**
     * Get user information from Cognito including custom attributes
     */
    CognitoHelper.getCognitoUserAttributes = function (username) {
        return __awaiter(this, void 0, void 0, function () {
            var command, result, userData, _i, _a, attr, attrName, error_10, errorMessage;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        _b.trys.push([0, 2, , 3]);
                        command = new client_cognito_identity_provider_1.AdminGetUserCommand({
                            UserPoolId: USER_POOL_ID,
                            Username: username
                        });
                        return [4 /*yield*/, cognitoClient.send(command)];
                    case 1:
                        result = _b.sent();
                        userData = {
                            username: result.Username,
                            userStatus: result.UserStatus,
                            enabled: result.Enabled,
                            userCreateDate: result.UserCreateDate,
                            userLastModifiedDate: result.UserLastModifiedDate
                        };
                        // Parse user attributes
                        if (result.UserAttributes) {
                            for (_i = 0, _a = result.UserAttributes; _i < _a.length; _i++) {
                                attr = _a[_i];
                                if (attr.Name && attr.Value) {
                                    attrName = attr.Name.startsWith('custom:')
                                        ? attr.Name.substring(7)
                                        : attr.Name;
                                    userData[attrName] = attr.Value;
                                }
                            }
                        }
                        console.log('Retrieved Cognito user data:', JSON.stringify(userData, null, 2));
                        return [2 /*return*/, {
                                success: true,
                                userData: userData
                            }];
                    case 2:
                        error_10 = _b.sent();
                        console.error('Error getting Cognito user attributes:', error_10);
                        errorMessage = 'فشل في الحصول على معلومات المستخدم';
                        if (error_10.name === 'UserNotFoundException') {
                            errorMessage = 'المستخدم غير موجود';
                        }
                        return [2 /*return*/, {
                                success: false,
                                error: errorMessage
                            }];
                    case 3: return [2 /*return*/];
                }
            });
        });
    };
    return CognitoHelper;
}());
exports.CognitoHelper = CognitoHelper;
/**
 * SMS Helper Functions
 */
var SMSHelper = /** @class */ (function () {
    function SMSHelper() {
    }
    SMSHelper.sendVerificationSMS = function (phone, code) {
        return __awaiter(this, void 0, void 0, function () {
            var message, command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        message = "\u0631\u0645\u0632 \u0627\u0644\u062A\u062D\u0642\u0642 \u0644\u062A\u0637\u0628\u064A\u0642 \u0632\u0627\u062F: ".concat(code, "\n\u0644\u0627 \u062A\u0634\u0627\u0631\u0643 \u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632 \u0645\u0639 \u0623\u062D\u062F.\n\u0635\u0627\u0644\u062D \u0644\u0645\u062F\u0629 10 \u062F\u0642\u0627\u0626\u0642.");
                        command = new client_sns_1.PublishCommand({
                            PhoneNumber: phone,
                            Message: message
                        });
                        return [4 /*yield*/, snsClient.send(command)];
                    case 1:
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    SMSHelper.sendPasswordResetSMS = function (phone, code) {
        return __awaiter(this, void 0, void 0, function () {
            var message, command;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        message = "\u0631\u0645\u0632 \u0625\u0639\u0627\u062F\u0629 \u062A\u0639\u064A\u064A\u0646 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u0644\u062A\u0637\u0628\u064A\u0642 \u0632\u0627\u062F: ".concat(code, "\n\u0644\u0627 \u062A\u0634\u0627\u0631\u0643 \u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632 \u0645\u0639 \u0623\u062D\u062F.\n\u0635\u0627\u0644\u062D \u0644\u0645\u062F\u0629 15 \u062F\u0642\u064A\u0642\u0629.");
                        command = new client_sns_1.PublishCommand({
                            PhoneNumber: phone,
                            Message: message,
                            MessageAttributes: {
                                'AWS.SNS.SMS.SenderID': {
                                    DataType: 'String',
                                    StringValue: 'FOODAPP'
                                },
                                'AWS.SNS.SMS.SMSType': {
                                    DataType: 'String',
                                    StringValue: 'Transactional'
                                }
                            }
                        });
                        return [4 /*yield*/, snsClient.send(command)];
                    case 1:
                        _a.sent();
                        console.log("Password reset SMS sent to ".concat(phone));
                        return [2 /*return*/];
                }
            });
        });
    };
    return SMSHelper;
}());
exports.SMSHelper = SMSHelper;
/**
 * Email Helper Functions
 */
var EmailHelper = /** @class */ (function () {
    function EmailHelper() {
    }
    EmailHelper.sendVerificationEmail = function (email, code, name) {
        return __awaiter(this, void 0, void 0, function () {
            var subject, htmlBody, textBody, command, error_11;
            var _a, _b, _c, _d;
            return __generator(this, function (_e) {
                switch (_e.label) {
                    case 0:
                        subject = 'تأكيد حسابك في تطبيق زاد';
                        htmlBody = "\n      <div dir=\"rtl\" style=\"font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;\">\n        <div style=\"background: linear-gradient(135deg, #00c1e8, #0099b8); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;\">\n          <h1 style=\"color: white; margin: 0; font-size: 28px;\">\u0645\u0631\u062D\u0628\u0627\u064B ".concat(name, "</h1>\n        </div>\n        \n        <div style=\"background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px;\">\n          <h2 style=\"color: #333; text-align: center;\">\u062A\u0623\u0643\u064A\u062F \u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u0628\u0631\u064A\u062F \u0627\u0644\u0625\u0644\u0643\u062A\u0631\u0648\u0646\u064A</h2>\n          \n          <p style=\"color: #666; font-size: 16px; line-height: 1.6;\">\n            \u0634\u0643\u0631\u0627\u064B \u0644\u062A\u0633\u062C\u064A\u0644\u0643 \u0641\u064A \u062A\u0637\u0628\u064A\u0642 \u0632\u0627\u062F! \u0644\u0625\u0643\u0645\u0627\u0644 \u0625\u0646\u0634\u0627\u0621 \u062D\u0633\u0627\u0628\u0643\u060C \u064A\u0631\u062C\u0649 \u0627\u0633\u062A\u062E\u062F\u0627\u0645 \u0631\u0645\u0632 \u0627\u0644\u062A\u062D\u0642\u0642 \u0627\u0644\u062A\u0627\u0644\u064A:\n          </p>\n          \n          <div style=\"background: white; padding: 20px; text-align: center; border-radius: 8px; margin: 20px 0; border: 2px dashed #00c1e8;\">\n            <h1 style=\"color: #00c1e8; font-size: 32px; margin: 0; letter-spacing: 8px;\">").concat(code, "</h1>\n          </div>\n          \n          <p style=\"color: #666; font-size: 14px;\">\n            \u2022 \u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632 \u0635\u0627\u0644\u062D \u0644\u0645\u062F\u0629 <strong>10 \u062F\u0642\u0627\u0626\u0642</strong> \u0641\u0642\u0637<br>\n            \u2022 \u0644\u0627 \u062A\u0634\u0627\u0631\u0643 \u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632 \u0645\u0639 \u0623\u062D\u062F<br>\n            \u2022 \u0625\u0630\u0627 \u0644\u0645 \u062A\u0642\u0645 \u0628\u0637\u0644\u0628 \u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632\u060C \u064A\u0631\u062C\u0649 \u062A\u062C\u0627\u0647\u0644 \u0647\u0630\u0647 \u0627\u0644\u0631\u0633\u0627\u0644\u0629\n          </p>\n          \n          <div style=\"text-align: center; margin-top: 30px;\">\n            <p style=\"color: #999; font-size: 12px;\">\n              \u0641\u0631\u064A\u0642 \u062A\u0637\u0628\u064A\u0642 \u0632\u0627\u062F<br>\n              \u0644\u0644\u0645\u0633\u0627\u0639\u062F\u0629: support@foodapp.com\n            </p>\n          </div>\n        </div>\n      </div>\n    ");
                        textBody = "\n\u0645\u0631\u062D\u0628\u0627\u064B ".concat(name, "\u060C\n\n\u0634\u0643\u0631\u0627\u064B \u0644\u062A\u0633\u062C\u064A\u0644\u0643 \u0641\u064A \u062A\u0637\u0628\u064A\u0642 \u0632\u0627\u062F! \n\n\u0631\u0645\u0632 \u0627\u0644\u062A\u062D\u0642\u0642 \u0627\u0644\u062E\u0627\u0635 \u0628\u0643: ").concat(code, "\n\n\u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632 \u0635\u0627\u0644\u062D \u0644\u0645\u062F\u0629 10 \u062F\u0642\u0627\u0626\u0642 \u0641\u0642\u0637.\n\u0644\u0627 \u062A\u0634\u0627\u0631\u0643 \u0647\u0630\u0627 \u0627\u0644\u0631\u0645\u0632 \u0645\u0639 \u0623\u062D\u062F.\n\n\u0641\u0631\u064A\u0642 \u062A\u0637\u0628\u064A\u0642 \u0632\u0627\u062F\n    ");
                        command = new client_ses_1.SendEmailCommand({
                            Source: process.env.SES_FROM_EMAIL || 'noreply@foodapp.com',
                            Destination: { ToAddresses: [email] },
                            Message: {
                                Subject: { Data: subject, Charset: 'UTF-8' },
                                Body: {
                                    Html: { Data: htmlBody, Charset: 'UTF-8' },
                                    Text: { Data: textBody, Charset: 'UTF-8' }
                                }
                            }
                        });
                        _e.label = 1;
                    case 1:
                        _e.trys.push([1, 3, , 4]);
                        return [4 /*yield*/, sesClient.send(command)];
                    case 2:
                        _e.sent();
                        console.log("Email sent successfully to ".concat(email));
                        return [3 /*break*/, 4];
                    case 3:
                        error_11 = _e.sent();
                        console.error('Failed to send email:', error_11);
                        // Enhanced error handling with specific AWS SES errors
                        if (error_11.name === 'SendingQuotaExceededException') {
                            throw new Error('تم تجاوز الحد اليومي لإرسال الإيميلات (50 رسالة). يرجى المحاولة غداً أو استخدم رقم الهاتف للتسجيل.');
                        }
                        else if (error_11.name === 'MessageRejected') {
                            throw new Error('تم رفض الإيميل. تأكد من صحة عنوان البريد الإلكتروني.');
                        }
                        else if (error_11.name === 'MailFromDomainNotVerifiedException') {
                            throw new Error('نطاق الإرسال غير مُحقق. يرجى استخدام رقم الهاتف للتسجيل.');
                        }
                        else if (error_11.name === 'AccountSendingPausedException') {
                            throw new Error('تم إيقاف خدمة الإرسال مؤقتاً. يرجى استخدام رقم الهاتف للتسجيل.');
                        }
                        else if (((_a = error_11.message) === null || _a === void 0 ? void 0 : _a.includes('not verified')) || ((_b = error_11.message) === null || _b === void 0 ? void 0 : _b.includes('Email address not verified'))) {
                            throw new Error('عذراً، نظام الإرسال في وضع الاختبار حالياً. يرجى استخدام رقم الهاتف للتسجيل.');
                        }
                        else if ((_c = error_11.message) === null || _c === void 0 ? void 0 : _c.includes('Daily sending quota exceeded')) {
                            throw new Error('تم تجاوز الحد اليومي لإرسال الإيميلات (50 رسالة). يرجى المحاولة غداً أو استخدم رقم الهاتف.');
                        }
                        else if ((_d = error_11.message) === null || _d === void 0 ? void 0 : _d.includes('sandbox')) {
                            throw new Error('نظام الإرسال في وضع التطوير. يرجى استخدام رقم الهاتف للتسجيل.');
                        }
                        throw new Error("\u0641\u0634\u0644 \u0641\u064A \u0625\u0631\u0633\u0627\u0644 \u0631\u0645\u0632 \u0627\u0644\u062A\u062D\u0642\u0642 \u0639\u0628\u0631 \u0627\u0644\u0628\u0631\u064A\u062F \u0627\u0644\u0625\u0644\u0643\u062A\u0631\u0648\u0646\u064A. \u064A\u0631\u062C\u0649 \u0627\u0633\u062A\u062E\u062F\u0627\u0645 \u0631\u0642\u0645 \u0627\u0644\u0647\u0627\u062A\u0641 \u0644\u0644\u062A\u0633\u062C\u064A\u0644.");
                    case 4: return [2 /*return*/];
                }
            });
        });
    };
    return EmailHelper;
}());
exports.EmailHelper = EmailHelper;
/**
 * Utility Functions
 */
var Utils = /** @class */ (function () {
    function Utils() {
    }
    Utils.generateVerificationCode = function () {
        return Math.floor(100000 + Math.random() * 900000).toString();
    };
    Utils.generateTempUserId = function () {
        return 'temp_' + (0, crypto_1.randomBytes)(16).toString('hex');
    };
    Utils.generateUserId = function () {
        return 'user_' + (0, crypto_1.randomBytes)(16).toString('hex');
    };
    Utils.hashPassword = function (password) {
        return (0, crypto_1.createHash)('sha256').update(password).digest('hex');
    };
    Utils.formatPhoneNumber = function (phone, countryCode) {
        if (countryCode === void 0) { countryCode = '+964'; }
        // Remove any existing country code and format
        var cleanPhone = phone.replace(/^\+?964/, '').replace(/\D/g, '');
        // Handle Iraqi phone number formats:
        // - If starts with 07, remove the leading 0 to get 7XXXXXXXX (10 digits starting with 7)
        // - If starts with 7, keep as is (already 10 digits starting with 7)
        if (cleanPhone.startsWith('07')) {
            cleanPhone = cleanPhone.substring(1); // Remove leading 0
        }
        // Ensure it's exactly 10 digits starting with 7
        if (!cleanPhone.startsWith('7') || cleanPhone.length !== 10) {
            // Try to fix common formats
            if (cleanPhone.startsWith('0') && cleanPhone.length === 11) {
                cleanPhone = cleanPhone.substring(1);
            }
        }
        return "".concat(countryCode).concat(cleanPhone);
    };
    Utils.isValidEmail = function (email) {
        var emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    };
    Utils.isValidPhone = function (phone) {
        // Iraqi phone number validation
        // Format: +964 followed by 10 digits starting with 7
        // Examples: +9647901234567, +9647701234567, +9647801234567
        var phoneRegex = /^\+9647[0-9]{9}$/;
        return phoneRegex.test(phone);
    };
    Utils.getCurrentTimestamp = function () {
        return new Date().toISOString();
    };
    Utils.getTTLTimestamp = function (hoursFromNow) {
        if (hoursFromNow === void 0) { hoursFromNow = 24; }
        return Math.floor(Date.now() / 1000) + (hoursFromNow * 60 * 60);
    };
    Utils.createAPIResponse = function (statusCode, body) {
        return {
            statusCode: statusCode,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'
            },
            body: JSON.stringify(body)
        };
    };
    Utils.generateResetToken = function () {
        // Generate a secure reset token
        return Utils.generateUserId() + '_' + Date.now().toString();
    };
    Utils.getExpiryTimestamp = function (minutesFromNow) {
        if (minutesFromNow === void 0) { minutesFromNow = 15; }
        return Math.floor(Date.now() / 1000) + (minutesFromNow * 60);
    };
    Utils.isValidPassword = function (password) {
        // Password must be at least 8 characters and contain:
        // - At least one uppercase letter
        // - At least one lowercase letter  
        // - At least one number
        // - At least one special character
        var passwordRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$/;
        return passwordRegex.test(password);
    };
    return Utils;
}());
exports.Utils = Utils;
