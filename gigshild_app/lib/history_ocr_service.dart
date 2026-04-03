import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class HistoryOcrResult {
  const HistoryOcrResult({
    required this.totalAmount,
    required this.extractedAmounts,
    required this.rawText,
    required this.warnings,
  });

  final double totalAmount;
  final List<String> extractedAmounts;
  final String rawText;
  final List<String> warnings;
}

class HistoryOcrService {
  HistoryOcrService._();

  static final RegExp _currencyPattern = RegExp(
    r'(?:₹|Rs\.?|INR)\s*(\d[\d,]*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final RegExp _fallbackAmountPattern = RegExp(
    r'\b(\d[\d,]*(?:\.\d{1,2})?)\b',
    caseSensitive: false,
  );

  static Future<HistoryOcrResult> extractTotals(List<XFile> historyFiles) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final warnings = <String>[];
    final extractedAmounts = <String>[];
    final rawTexts = <String>[];
    var totalAmount = 0.0;

    try {
      for (final historyFile in historyFiles) {
        try {
          final inputImage = InputImage.fromFilePath(historyFile.path);
          final recognizedText = await textRecognizer.processImage(inputImage);
          final rawText = recognizedText.text.trim();
          if (rawText.isEmpty) {
            warnings.add('${historyFile.name}: no readable text found');
            continue;
          }

          rawTexts.add(rawText);
          final amounts = _extractAmountsFromText(rawText);
          extractedAmounts.addAll(
            amounts.map((value) => value.toStringAsFixed(2)),
          );
          totalAmount += amounts.fold(0.0, (sum, value) => sum + value);
        } catch (_) {
          warnings.add('${historyFile.name}: OCR failed');
        }
      }
    } finally {
      await textRecognizer.close();
    }

    return HistoryOcrResult(
      totalAmount: double.parse(totalAmount.toStringAsFixed(2)),
      extractedAmounts: extractedAmounts,
      rawText: rawTexts.join('\n\n'),
      warnings: warnings,
    );
  }

  static List<double> _extractAmountsFromText(String rawText) {
    final amounts = <double>[];
    final lines = rawText.split('\n');

    for (final line in lines) {
      final normalizedLine = line.trim();
      if (normalizedLine.isEmpty) {
        continue;
      }

      final lowerLine = normalizedLine.toLowerCase();
      if (lowerLine.contains('cash') && lowerLine.contains('collected')) {
        continue;
      }

      final preferredMatches = _currencyPattern.allMatches(normalizedLine);
      var addedFromLine = false;
      for (final match in preferredMatches) {
        final amount = _parseAmount(match.group(1));
        if (amount != null && amount > 0 && amount < 100000) {
          amounts.add(amount);
          addedFromLine = true;
        }
      }

      if (addedFromLine) {
        continue;
      }

      if (lowerLine.contains('earning') ||
          lowerLine.contains('earned') ||
          lowerLine.contains('total')) {
        for (final match in _fallbackAmountPattern.allMatches(normalizedLine)) {
          final amount = _parseAmount(match.group(1));
          if (amount != null && amount > 0 && amount < 100000) {
            amounts.add(amount);
          }
        }
      }
    }

    return amounts;
  }

  static double? _parseAmount(String? rawAmount) {
    if (rawAmount == null || rawAmount.isEmpty) {
      return null;
    }

    return double.tryParse(rawAmount.replaceAll(',', ''));
  }
}
