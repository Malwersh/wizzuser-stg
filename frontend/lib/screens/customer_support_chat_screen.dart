import 'package:flutter/material.dart';
import '../services/customer_support_chat.dart';

/// Existing support conversation for a verified customer order.
class CustomerSupportChatScreen extends StatefulWidget {
  final String orderId, sessionId;
  final CustomerSupportChat Function()? createChat;
  const CustomerSupportChatScreen({
    super.key,
    required this.orderId,
    required this.sessionId,
    this.createChat,
  });
  @override
  State<CustomerSupportChatScreen> createState() =>
      _CustomerSupportChatScreenState();
}

class _CustomerSupportChatScreenState extends State<CustomerSupportChatScreen>
    with WidgetsBindingObserver {
  late final CustomerSupportChat _chat;
  final _text = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chat =
        widget.createChat?.call() ??
        CustomerSupportChat(
          orderId: widget.orderId,
          fixedSessionId: widget.sessionId,
        );
    _chat.addListener(_changed);
    _chat.connect();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_chat.sending &&
        _chat.status != 'closed')
      _chat.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_changed);
    _chat.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _text.text;
    final saved = await _chat.send(value);
    if (!mounted) return;
    if (saved) {
      if (_text.text == value) _text.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لم نتأكد من إرسال الرسالة. أعد المحاولة؛ لن تُحفظ مرتين.',
          ),
        ),
      );
    }
  }

  String get _status => switch (_chat.status) {
    'connecting' => 'جارٍ الاتصال بالدعم…',
    'connected' => 'متصل بالدعم',
    'closed' => 'أُغلقت المحادثة',
    'disconnected' => 'انقطع الاتصال',
    _ => 'تعذر الاتصال بالدعم',
  };
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(title: const Text('محادثة الدعم')),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(
                  Icons.support_agent,
                  color: Color(0xFF00296B),
                ),
                title: Text(_status),
                subtitle: const Text('محادثة خاصة مع فريق دعم المنصة'),
                trailing:
                    _chat.status == 'connecting'
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : !_chat.connected && _chat.status != 'closed'
                        ? TextButton(
                          onPressed:
                              () => _chat.connect(
                                newConversation: _chat.status == 'closed',
                              ),
                          child: Text(
                            _chat.status == 'closed'
                                ? 'محادثة جديدة'
                                : 'إعادة الاتصال',
                          ),
                        )
                        : null,
              ),
            ),
            if (_chat.historyError != null)
              TextButton(
                onPressed: () => _chat.loadHistory(),
                child: Text('${_chat.historyError}؛ إعادة المحاولة'),
              ),
            if (_chat.nextCursor != null)
              TextButton(
                onPressed:
                    _chat.historyLoading
                        ? null
                        : () => _chat.loadHistory(older: true),
                child: const Text('عرض الرسائل الأقدم'),
              ),
            if (_chat.historyLoading) const LinearProgressIndicator(),
            Expanded(
              child:
                  _chat.messages.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'اكتب رسالتك لفريق الدعم. ستظهر هنا الرسائل المؤكد حفظها.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _chat.messages.length,
                        itemBuilder: (context, index) {
                          final message = _chat.messages[index],
                              own = message['senderType'] == 'customer';
                          return Align(
                            alignment:
                                own
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * .8,
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    own
                                        ? const Color(0xFF00296B)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    own ? 'أنت' : 'فريق الدعم',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          own
                                              ? Colors.white
                                              : const Color(0xFF00296B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${message['text']}',
                                    style: TextStyle(
                                      height: 1.5,
                                      color:
                                          own ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  if (message['attachment'] != null)
                                    Text(
                                      'صورة مرفقة بالمحادثة',
                                      style: TextStyle(
                                        color:
                                            own ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_chat.sending,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك للدعم',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _chat.connected && !_chat.sending ? _send : null,
                    tooltip: 'إرسال للدعم',
                    icon:
                        _chat.sending
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
