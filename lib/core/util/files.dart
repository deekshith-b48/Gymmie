import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/feedback.dart';

/// Writes [bytes] to a temp file and opens the system share sheet (CSV / PDF exports).
Future<void> shareBytes(
  BuildContext context,
  Uint8List bytes,
  String filename,
  String mime, {
  String? text,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final f = File('${dir.path}/$safe');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: mime)],
        text: text,
        subject: filename,
      ),
    );
  } catch (e) {
    if (context.mounted) showToast(context, 'Export unavailable', error: true);
  }
}
