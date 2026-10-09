import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/feedback.dart';

/// A picked image ready to upload: raw bytes (for preview) plus the JSON form the API expects.
class PickedImage {
  PickedImage(this.bytes, this.contentType);
  final List<int> bytes;
  final String contentType;
  Map<String, dynamic> toJson() => {
    'data': base64Encode(bytes),
    'contentType': contentType,
  };
}

String _mimeFor(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Camera / gallery chooser. Images are downscaled and re-encoded by the picker, which keeps
/// uploads well under the server's 5 MB limit.
Future<PickedImage?> pickImage(
  BuildContext context, {
  int maxSide = 1080,
  int quality = 80,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final f = await ImagePicker().pickImage(
      source: source,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      imageQuality: quality,
    );
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (context.mounted) {
        showToast(context, 'Max file size is 5MB', error: true);
      }
      return null;
    }
    return PickedImage(bytes, _mimeFor(f.path));
  } catch (_) {
    if (context.mounted) showToast(context, 'Upload failed', error: true);
    return null;
  }
}
