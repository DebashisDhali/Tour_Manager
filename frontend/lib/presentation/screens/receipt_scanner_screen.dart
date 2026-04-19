import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'dart:io';
import 'package:frontend/data/services/receipt_scanner_service.dart';
import 'package:frontend/presentation/screens/scanned_receipt_form.dart';

class ReceiptScannerScreen extends ConsumerStatefulWidget {
  final String tourId;

  const ReceiptScannerScreen({required this.tourId, Key? key})
      : super(key: key);

  @override
  ConsumerState<ReceiptScannerScreen> createState() =>
      _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends ConsumerState<ReceiptScannerScreen> {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  late final ReceiptScannerService _scannerService;
  bool _isFrontCamera = false;

  @override
  void initState() {
    super.initState();
    _scannerService = ReceiptScannerService();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('📷 No camera found')),
          );
        }
        return;
      }

      final camera = cameras.first;
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('❌ Camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📷 Camera error: $e')),
        );
      }
    }
  }

  Future<void> _captureAndScan() async {
    if (!_isCameraInitialized) return;

    try {
      setState(() => _isScanning = true);

      final picture = await _cameraController.takePicture();
      final imageFile = File(picture.path);

      // Rotate if needed
      final rotatedFile = await _scannerService.rotateImageIfNeeded(imageFile);

      if (!mounted) return;

      _showScanningDialog();

      // Scan receipt
      final scannedData = await _scannerService.scanReceipt(rotatedFile);

      if (!mounted) return;
      Navigator.pop(context); // Close scanning dialog

      // Navigate to form with scanned data
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => ScannedReceiptFormScreen(
            tourId: widget.tourId,
            scannedData: scannedData,
          ),
        ),
      );

      if (result != null) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close scanning dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      if (!mounted) return;

      _showScanningDialog();

      final imageFile = File(pickedFile.path);
      final rotatedFile = await _scannerService.rotateImageIfNeeded(imageFile);
      final scannedData = await _scannerService.scanReceipt(rotatedFile);

      if (!mounted) return;
      Navigator.pop(context); // Close scanning dialog

      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => ScannedReceiptFormScreen(
            tourId: widget.tourId,
            scannedData: scannedData,
          ),
        ),
      );

      if (result != null) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close scanning dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Gallery error: $e')),
        );
      }
    }
  }

  void _showScanningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text('🔍 Scanning receipt...'),
            const SizedBox(height: 10),
            const Text(
              'Extracting amount, date, and items...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _scannerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Scan Receipt'),
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _isCameraInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController),
                // Overlay guide
                Positioned.fill(
                  child: CustomPaint(
                    painter: ReceiptOverlayPainter(),
                  ),
                ),
                // Bottom controls
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '📝 Position receipt within the frame',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Gallery button
                            FloatingActionButton.extended(
                              onPressed: _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                              backgroundColor: Colors.grey[700],
                            ),
                            // Capture button
                            FloatingActionButton(
                              onPressed: _isScanning ? null : _captureAndScan,
                              backgroundColor:
                                  _isScanning ? Colors.grey : Colors.blueAccent,
                              child: _isScanning
                                  ? const SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.camera_alt),
                            ),
                            // Info button
                            FloatingActionButton.extended(
                              onPressed: () => _showTips(),
                              icon: const Icon(Icons.info),
                              label: const Text('Tips'),
                              backgroundColor: Colors.grey[700],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt, size: 60, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text('📷 Initializing camera...'),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Or pick from gallery'),
                  ),
                ],
              ),
            ),
    );
  }

  void _showTips() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('💡 Receipt Scanning Tips'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _tipItem('📸', 'Good lighting', 'Ensure receipt is well-lit'),
              _tipItem(
                  '📄', 'Full receipt', 'Include all text and total amount'),
              _tipItem('↔️', 'Straight angle', 'Hold camera perpendicular'),
              _tipItem('🔢', 'Clear text', 'Make sure text is readable'),
              _tipItem('📊', 'Single receipt', 'Scan one receipt at a time'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _tipItem(String icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$icon $title',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(description,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

/// Custom painter for receipt guide overlay
class ReceiptOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(
      size.width * 0.1,
      size.height * 0.15,
      size.width * 0.8,
      size.height * 0.6,
    );

    // Draw rectangle guide
    canvas.drawRect(rect, paint);

    // Draw corner markers
    final cornerPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 5;

    final cornerSize = 30.0;

    // Top-left
    canvas.drawLine(Offset(rect.left, rect.top),
        Offset(rect.left + cornerSize, rect.top), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.top),
        Offset(rect.left, rect.top + cornerSize), cornerPaint);

    // Top-right
    canvas.drawLine(Offset(rect.right, rect.top),
        Offset(rect.right - cornerSize, rect.top), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + cornerSize), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.left + cornerSize, rect.bottom), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.left, rect.bottom - cornerSize), cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right, rect.bottom),
        Offset(rect.right - cornerSize, rect.bottom), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.bottom),
        Offset(rect.right, rect.bottom - cornerSize), cornerPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
