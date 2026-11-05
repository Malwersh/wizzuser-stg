import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';

/// Images are requested on demand through an authenticated loader, never a URL.
class SupportAttachmentImage extends StatefulWidget {
  const SupportAttachmentImage({super.key, required this.load});
  final Future<Uint8List> Function() load;
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
    child: const Text('تعذر عرض الصورة؛ إعادة المحاولة'),
  );
  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.image_outlined),
        label: const Text('عرض الصورة'),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _retry();
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(),
          );
        }
        return Image.memory(
          snapshot.data!,
          width: 240,
          height: 180,
          cacheWidth: 1024,
          fit: BoxFit.contain,
          semanticLabel: 'صورة مرفقة بالمحادثة',
          errorBuilder: (_, __, ___) => _retry(),
        );
      },
    );
  }
}
