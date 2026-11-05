import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/support_attachment_image.dart';
import '../services/session_service.dart';
import '../services/support_chat_service.dart';
import '../services/support_conversation_store.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key, this.orderId});
  final String? orderId;
  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _text = TextEditingController();
  final _session = SessionService();
  SupportChatService? _chat;
  String? _owner;

  @override
  void initState() {
    super.initState();
    _owner = _session.currentUserId;
    _session.addListener(_identityChanged);
    if (_session.isLoggedIn && !_session.isGuest && _owner != null) {
      _chat = SupportChatService(
        orderId: widget.orderId,
        store: SecureSupportConversationStore(
          ownerId: _owner!,
          endpoint: SupportChatService.defaultEndpoint,
          orderId: widget.orderId,
        ),
        tokenProvider: () async {
          final token = await _session.getToken();
          return _session.currentUserId == _owner && _session.isLoggedIn
              ? token
              : null;
        },
      );
      _chat!.addListener(_changed);
      _chat!.connect();
    }
  }

  void _changed() {
    if (!mounted) return;
    final draft = _chat?.draft ?? '';
    if (_text.text != draft) {
      _text.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    setState(() {});
  }

  void _identityChanged() {
    if (_session.currentUserId != _owner ||
        !_session.isLoggedIn ||
        _session.isGuest) {
      final chat = _chat;
      _chat = null;
      chat?.removeListener(_changed);
      chat?.dispose();
      _text.clear();
      _changed();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_identityChanged);
    _chat?.removeListener(_changed);
    _chat?.dispose();
    _text.dispose();
    super.dispose();
  }

  bool _pickingImage = false;
  Future<void> _pickImage() async {
    final chat = _chat;
    if (_pickingImage || chat == null || !chat.ready || chat.closing) return;
    setState(() => _pickingImage = true);
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (!mounted || _chat != chat || selected == null) return;
      if (await selected.length() > SupportChatService.maxImageBytes) {
        throw StateError('Image too large');
      }
      final bytes = await selected.readAsBytes();
      if (!mounted || _chat != chat) return;
      await chat.sendImage(bytes, _text.text);
    } catch (_) {
      if (mounted && _chat == chat) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر اختيار الصورة. اختر JPEG أو PNG بحجم لا يتجاوز ٢ ميغابايت.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.orderId == null ? 'الدردشة مع الدعم' : 'الدعم بخصوص الطلب',
          ),
          actions: [
            if (chat != null && chat.closed)
              TextButton(
                onPressed: chat.startNewConversation,
                child: const Text('محادثة جديدة'),
              ),
            if (chat != null && chat.ready && !chat.closed)
              TextButton(
                onPressed:
                    chat.closing
                        ? null
                        : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('إنهاء المحادثة؟'),
                                  content: const Text(
                                    'يمكنك بدء محادثة جديدة لاحقًا.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('رجوع'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('إنهاء'),
                                    ),
                                  ],
                                ),
                          );
                          if (confirmed == true && mounted) {
                            chat.endConversation();
                          }
                        },
                child: Text(chat.closing ? 'جارٍ الإنهاء…' : 'إنهاء'),
              ),
          ],
        ),
        body:
            chat == null
                ? const Center(
                  child: Text('سجّل الدخول إلى حسابك للتواصل مع الدعم.'),
                )
                : Column(
                  children: [
                    if (chat.connecting) const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        chat.closed
                            ? 'انتهت المحادثة'
                            : chat.ready
                            ? 'يمكنك مراسلة فريق الدعم'
                            : 'بانتظار الاتصال بالدعم',
                      ),
                    ),
                    if (chat.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(child: Text(chat.error!)),
                            if (!chat.closed && !chat.connecting && !chat.ready)
                              TextButton(
                                onPressed: chat.connect,
                                child: const Text('إعادة الاتصال'),
                              ),
                          ],
                        ),
                      ),
                    if (chat.loadingHistory) const LinearProgressIndicator(),
                    if (chat.historyError != null)
                      TextButton(
                        onPressed: chat.retryHistory,
                        child: Text(chat.historyError!),
                      ),
                    if (chat.nextCursor != null && chat.historyError == null)
                      TextButton(
                        onPressed:
                            chat.loadingHistory || !chat.ready
                                ? null
                                : chat.loadOlder,
                        child: const Text('تحميل الرسائل الأقدم'),
                      ),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: chat.messages.length,
                        itemBuilder: (context, index) {
                          final message =
                              chat.messages[chat.messages.length - index - 1];
                          return Align(
                            alignment:
                                message.sender == 'customer'
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      message.sender == 'customer'
                                          ? 'أنت'
                                          : 'فريق الدعم',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                    ),
                                    SelectableText(message.text),
                                    if (message.isUploading)
                                      const Text('جارٍ رفع الصورة…'),
                                    if (message.attachmentId != null)
                                      SupportAttachmentImage(
                                        key: ValueKey(
                                          '${chat.sessionId}:${message.attachmentId}',
                                        ),
                                        load:
                                            () => chat.loadImage(
                                              message.attachmentId!,
                                            ),
                                      ),
                                    if (message.sender == 'customer')
                                      Text(
                                        switch (message.status) {
                                          'accepted' => 'تم الحفظ',
                                          'unknown' => 'لم يتأكد الإرسال',
                                          'failed' => 'تعذر الإرسال',
                                          _ => 'جارٍ الإرسال…',
                                        },
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (!chat.closed)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _text,
                                  maxLength: 4000,
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText: 'اكتب رسالتك',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) => chat.draft = value,
                                ),
                              ),
                              if (chat.imagesAvailable)
                                IconButton(
                                  tooltip: 'إرفاق صورة',
                                  onPressed:
                                      chat.ready &&
                                              !chat.closing &&
                                              !_pickingImage
                                          ? _pickImage
                                          : null,
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'إرسال',
                                onPressed:
                                    chat.ready && !chat.closing
                                        ? () {
                                          if (chat.send(_text.text)) {
                                            _text.clear();
                                          }
                                        }
                                        : null,
                                icon: const Icon(Icons.send),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}
