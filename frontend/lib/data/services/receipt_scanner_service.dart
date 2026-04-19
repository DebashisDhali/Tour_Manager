import 'dart:io';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

class ScannedReceiptData {
  final double? amount;
  final String? date;
  final String? vendor;
  final List<String> items;
  final String rawText;
  final String category;

  ScannedReceiptData({
    this.amount,
    this.date,
    this.vendor,
    this.items = const [],
    required this.rawText,
    this.category = 'Others',
  });

  @override
  String toString() =>
      'Receipt: Amount=$amount, Date=$date, Vendor=$vendor, Category=$category';
}

class ReceiptScannerService {
  late final TextRecognizer _textRecognizer;

  ReceiptScannerService() {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Extract text from receipt image
  Future<ScannedReceiptData> scanReceipt(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final fullText = recognizedText.text;
      print('📄 Extracted text:\n$fullText');

      // Parse the text
      final parsedData = _parseReceiptText(fullText);
      return parsedData;
    } catch (e) {
      print('❌ OCR Error: $e');
      rethrow;
    }
  }

  /// Parse receipt text to extract meaningful data
  ScannedReceiptData _parseReceiptText(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();

    double? extractedAmount;
    String? extractedDate;
    String? extractedVendor;
    final items = <String>[];
    String category = 'Others';

    // Extract vendor name (usually first non-empty line)
    extractedVendor = lines.isNotEmpty ? lines.first : null;

    // Extract amount using regex
    final amountRegex = RegExp(r'(?:Rs\.?|৳|฿|₹|BDT)?\s*(\d+(?:[,\.]\d{2})?)',
        caseSensitive: false);
    final amountMatches = amountRegex.allMatches(text);

    if (amountMatches.isNotEmpty) {
      final lastMatch = amountMatches.last;
      final amountStr = lastMatch.group(1)?.replaceAll(',', '') ?? '0';
      extractedAmount = double.tryParse(amountStr);
    }

    // Extract date using regex
    final dateRegex = RegExp(
        r'(?:(\d{1,2})[\/\-\.:](\d{1,2})[\/\-\.:](\d{2,4}))',
        caseSensitive: false);
    final dateMatch = dateRegex.firstMatch(text);
    if (dateMatch != null) {
      extractedDate = dateMatch.group(0);
    }

    // Extract items (lines with item-like patterns)
    for (final line in lines) {
      // Skip very short lines and headers
      if (line.length > 5 &&
          !line.contains('Total') &&
          !line.contains('Amount') &&
          !line.contains('Date')) {
        // Look for lines with both text and numbers (likely items)
        if (RegExp(r'\d').hasMatch(line)) {
          items.add(line);
        }
      }
    }

    // Auto-categorize based on keywords
    category = _categorizeReceipt(text);

    return ScannedReceiptData(
      amount: extractedAmount,
      date: extractedDate,
      vendor: extractedVendor,
      items: items,
      rawText: text,
      category: category,
    );
  }

  /// Auto-categorize receipt based on keywords
  String _categorizeReceipt(String text) {
    final lowerText = text.toLowerCase();

    const categoryKeywords = {
      'Food': [
        'restaurant',
        'cafe',
        'food',
        'meal',
        'lunch',
        'dinner',
        'breakfast',
        'pizza',
        'burger',
        'noodle',
        'rice',
        'khana'
      ],
      'Hotel': [
        'hotel',
        'motel',
        'resort',
        'lodge',
        'inn',
        'accommodation',
        'room',
        'bed',
        'stay'
      ],
      'Transport': [
        'taxi',
        'uber',
        'bus',
        'train',
        'flight',
        'car',
        'vehicle',
        'transport',
        'petrol',
        'gas',
        'parking'
      ],
      'Shopping': [
        'shop',
        'market',
        'mall',
        'store',
        'supermarket',
        'retail',
        'clothing',
        'apparel'
      ],
      'Entertainment': [
        'cinema',
        'movie',
        'theater',
        'show',
        'ticket',
        'entry',
        'museum',
        'park'
      ],
      'Medical': [
        'hospital',
        'doctor',
        'pharmacy',
        'medicine',
        'clinic',
        'health'
      ],
      'Utilities': [
        'water',
        'electricity',
        'internet',
        'mobile',
        'phone',
        'bill'
      ],
    };

    for (final entry in categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lowerText.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return 'Others';
  }

  /// Rotate image if needed
  Future<File> rotateImageIfNeeded(File imageFile) async {
    try {
      final image = img.decodeImage(await imageFile.readAsBytes());
      if (image == null) return imageFile;

      // Check if image is in portrait (tall)
      if (image.height < image.width) {
        final rotated = img.copyRotate(image, angle: 90);
        final rotatedFile =
            File(imageFile.path.replaceFirst('.jpg', '_rotated.jpg'));
        await rotatedFile.writeAsBytes(img.encodeJpg(rotated));
        return rotatedFile;
      }

      return imageFile;
    } catch (e) {
      print('⚠️ Image rotation failed: $e');
      return imageFile;
    }
  }

  /// Cleanup
  void dispose() {
    _textRecognizer.close();
  }
}
