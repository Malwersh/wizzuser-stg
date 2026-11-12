import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';

/// The loader authenticates each fetch; no public or bearer URL enters the widget.
class SupportAttachmentImage extends StatefulWidget {
  const SupportAttachmentImage({
    super.key,
    required this.load,
    this.foregroundColor,
  });
  final Future<Uint8List> Function() load;
  final Color? foregroundColor;
  @override
  State<SupportAttachmentImage> createState() => _SupportAttachmentImageState();
}

class _SupportAttachmentImageState extends State<SupportAttachmentImage> {
  Future<Uint8List>? _image;
  void _load() {
    final future = Future.sync(widget.load);
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    setState(() {
      _image = future;
    });
  }

  Widget _retry() => TextButton(
    onPressed: _load,
    child: Text(
      'تعذر عرض الصورة؛ إعادة المحاولة',
      style: TextStyle(color: widget.foregroundColor),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return TextButton.icon(
        onPressed: _load,
        icon: Icon(Icons.image_outlined, color: widget.foregroundColor),
        label: Text(
          'عرض الصورة',
          style: TextStyle(color: widget.foregroundColor),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: _load,
            child: Text(
              'تعذر تحميل الصورة؛ إعادة المحاولة',
              style: TextStyle(color: widget.foregroundColor),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          );
        }
        final bytes = snapshot.data!;
        return InkWell(
          onTap:
              () => showDialog<void>(
                context: context,
                builder:
                    (context) => Dialog(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: InteractiveViewer(
                              child: Image.memory(
                                bytes,
                                errorBuilder: (_, __, ___) => _retry(),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إغلاق'),
                          ),
                        ],
                      ),
                    ),
              ),
          child: Image.memory(
            bytes,
            width: 240,
            height: 180,
            cacheWidth: 1024,
            fit: BoxFit.contain,
            semanticLabel: 'صورة مرفقة بالمحادثة',
            errorBuilder: (_, __, ___) => _retry(),
          ),
        );
      },
    );
  }
}
