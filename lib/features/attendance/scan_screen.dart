import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/di.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/finance_repository.dart';

/// QR attendance: scans a member's QR (`dgymbook://member/<gymCode>/<memberId>`), shows the verdict, keeps scanning.
class QrAttendanceScreen extends StatefulWidget {
  const QrAttendanceScreen({super.key});
  @override
  State<QrAttendanceScreen> createState() => _QrAttendanceScreenState();
}

class _QrAttendanceScreenState extends State<QrAttendanceScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _message;
  bool _ok = false;
  int _count = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy) return;
    final raw = cap.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    setState(() => _busy = true);
    try {
      final log = await getIt<AttendanceRepository>().markByQr(raw);
      setState(() {
        _ok = true;
        _count++;
        _message = '${log.name ?? 'Member'} checked in';
      });
    } on ApiException catch (e) {
      setState(() {
        _ok = false;
        _message = e.message;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() {
        _busy = false;
        _message = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('QR Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: _controller.toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: _controller.switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white70,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      e.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera permission is required to scan QR codes. Enable it in system settings.'
                          : 'The camera is unavailable on this device.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 24,
            child: Center(
              child: Text(
                'Align the member QR code within the frame',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _message == null
                  ? Text(
                      '$_count checked in this session',
                      key: const ValueKey('count'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    )
                  : Container(
                      key: ValueKey(_message),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _ok ? AppColors.success : AppColors.danger,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _ok ? Icons.check_circle : Icons.error_outline,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _message!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
