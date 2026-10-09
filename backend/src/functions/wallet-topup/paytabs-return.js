// PayTabs Return Handler for WizzUser Wallet
// This function handles the user return from PayTabs payment page

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand } = require('@aws-sdk/lib-dynamodb');

const client = new DynamoDBClient({ region: process.env.AWS_REGION || 'us-east-1' });
const dynamodb = DynamoDBDocumentClient.from(client);

const TRANSACTIONS_TABLE = process.env.TRANSACTIONS_TABLE || 'WizzUser_transactions-dev';

exports.handler = async (event) => {
    console.log('PayTabs Return Event:', JSON.stringify(event, null, 2));
    
    try {
        // Get return parameters from PayTabs
        const queryParams = event.queryStringParameters || {};
        const {
            tran_ref,
            cart_id,
            respStatus,
            respCode,
            respMessage
        } = queryParams;
        
        console.log('[PayTabs Return] Parameters:', queryParams);
        
        // Create a user-friendly return page
        let htmlContent;
        
        if (!tran_ref || !cart_id) {
            // Missing parameters
            htmlContent = createReturnPage({
                status: 'error',
                title: 'خطأ في العملية',
                message: 'معلومات الدفع مفقودة. يرجى المحاولة مرة أخرى.',
                details: 'لم يتم العثور على تفاصيل المعاملة'
            });
        } else {
            // Try to get transaction details
            let transaction = null;
            try {
                // Search for transaction (implement based on your database structure)
                const scanParams = {
                    TableName: TRANSACTIONS_TABLE,
                    FilterExpression: 'payTabsRef = :ref OR payTabsTranRef = :ref OR reference = :cartId',
                    ExpressionAttributeValues: {
                        ':ref': tran_ref,
                        ':cartId': cart_id
                    }
                };
                
                const scanResult = await dynamodb.scan(scanParams).promise();
                if (scanResult.Items && scanResult.Items.length > 0) {
                    transaction = scanResult.Items[0];
                }
            } catch (dbError) {
                console.error('[PayTabs Return] Database error:', dbError);
            }
            
            // Determine status and create appropriate page
            const successCodes = ['100', '001', '000'];
            const isSuccessful = successCodes.includes(respCode) || respStatus === 'A';
            
            if (isSuccessful) {
                htmlContent = createReturnPage({
                    status: 'success',
                    title: 'تم الدفع بنجاح!',
                    message: 'تم شحن محفظتك بنجاح.',
                    details: transaction ? `مبلغ الشحن: ${transaction.amount} ${transaction.currency}` : 'جاري معالجة المعاملة...',
                    transactionRef: tran_ref
                });
            } else {
                htmlContent = createReturnPage({
                    status: 'failed',
                    title: 'فشل في عملية الدفع',
                    message: respMessage || 'حدث خطأ أثناء عملية الدفع.',
                    details: 'يرجى المحاولة مرة أخرى أو الاتصال بالدعم الفني.',
                    transactionRef: tran_ref
                });
            }
        }
        
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'text/html; charset=utf-8',
                'Cache-Control': 'no-cache, no-store, must-revalidate'
            },
            body: htmlContent
        };
        
    } catch (error) {
        console.error('[PayTabs Return] Error:', error);
        
        const errorHtml = createReturnPage({
            status: 'error',
            title: 'خطأ في النظام',
            message: 'حدث خطأ غير متوقع.',
            details: 'يرجى المحاولة مرة أخرى لاحقاً.'
        });
        
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'text/html; charset=utf-8'
            },
            body: errorHtml
        };
    }
};

// Helper function to create HTML return page
function createReturnPage({ status, title, message, details, transactionRef }) {
    const statusColors = {
        success: '#28a745',
        failed: '#dc3545',
        error: '#6c757d'
    };
    
    const statusIcons = {
        success: '✅',
        failed: '❌',
        error: '⚠️'
    };
    
    const color = statusColors[status] || '#6c757d';
    const icon = statusIcons[status] || '⚠️';
    
    return `
    <!DOCTYPE html>
    <html lang="ar" dir="rtl">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${title} - WizzUser</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            
            body {
                font-family: 'Arial', sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
                direction: rtl;
                text-align: right;
            }
            
            .container {
                background: white;
                padding: 40px;
                border-radius: 15px;
                box-shadow: 0 10px 30px rgba(0,0,0,0.2);
                max-width: 500px;
                width: 100%;
                text-align: center;
                animation: slideIn 0.5s ease-out;
            }
            
            @keyframes slideIn {
                from {
                    opacity: 0;
                    transform: translateY(-30px);
                }
                to {
                    opacity: 1;
                    transform: translateY(0);
                }
            }
            
            .icon {
                font-size: 60px;
                margin-bottom: 20px;
                display: block;
            }
            
            .title {
                color: ${color};
                font-size: 28px;
                font-weight: bold;
                margin-bottom: 15px;
            }
            
            .message {
                color: #333;
                font-size: 18px;
                margin-bottom: 15px;
                line-height: 1.6;
            }
            
            .details {
                color: #666;
                font-size: 14px;
                margin-bottom: 25px;
                padding: 15px;
                background: #f8f9fa;
                border-radius: 8px;
                border-right: 4px solid ${color};
            }
            
            .transaction-ref {
                color: #495057;
                font-size: 12px;
                margin-top: 20px;
                padding: 10px;
                background: #e9ecef;
                border-radius: 5px;
                font-family: monospace;
            }
            
            .button {
                background: ${color};
                color: white;
                padding: 12px 30px;
                border: none;
                border-radius: 25px;
                font-size: 16px;
                cursor: pointer;
                text-decoration: none;
                display: inline-block;
                transition: all 0.3s ease;
                margin: 10px;
            }
            
            .button:hover {
                opacity: 0.9;
                transform: translateY(-2px);
            }
            
            .button-secondary {
                background: #6c757d;
            }
            
            .footer {
                margin-top: 30px;
                padding-top: 20px;
                border-top: 1px solid #eee;
                color: #666;
                font-size: 12px;
            }
            
            @media (max-width: 480px) {
                .container {
                    padding: 30px 20px;
                }
                
                .title {
                    font-size: 24px;
                }
                
                .message {
                    font-size: 16px;
                }
            }
        </style>
    </head>
    <body>
        <div class="container">
            <span class="icon">${icon}</span>
            <h1 class="title">${title}</h1>
            <p class="message">${message}</p>
            <div class="details">${details}</div>
            
            ${transactionRef ? `<div class="transaction-ref">رقم المعاملة: ${transactionRef}</div>` : ''}
            
            <div style="margin-top: 30px;">
                <a href="#" onclick="closeWindow()" class="button">العودة للتطبيق</a>
                ${status === 'failed' ? '<a href="#" onclick="retryPayment()" class="button button-secondary">إعادة المحاولة</a>' : ''}
            </div>
            
            <div class="footer">
                <p>WizzUser - نظام إدارة المحافظ الإلكترونية</p>
                <p>في حالة وجود مشاكل، يرجى الاتصال بالدعم الفني</p>
            </div>
        </div>
        
        <script>
            function closeWindow() {
                // Try to close the window/tab
                if (window.opener) {
                    window.close();
                } else {
                    // If opened in same tab, try to go back
                    window.history.back();
                }
            }
            
            function retryPayment() {
                // Redirect back to app for retry
                closeWindow();
            }
            
            // Auto-close after 10 seconds for successful payments
            ${status === 'success' ? `
                setTimeout(() => {
                    closeWindow();
                }, 10000);
                
                // Show countdown
                let countdown = 10;
                const countdownElement = document.createElement('p');
                countdownElement.style.color = '#666';
                countdownElement.style.fontSize = '14px';
                countdownElement.style.marginTop = '15px';
                document.querySelector('.container').appendChild(countdownElement);
                
                const updateCountdown = () => {
                    countdownElement.textContent = \`سيتم إغلاق النافذة تلقائياً خلال \${countdown} ثانية\`;
                    countdown--;
                    if (countdown >= 0) {
                        setTimeout(updateCountdown, 1000);
                    }
                };
                updateCountdown();
            ` : ''}
        </script>
    </body>
    </html>`;
}
