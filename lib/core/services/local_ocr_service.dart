import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

/// Performs on-device OCR on a file (image or PDF).
///
/// Uses Google ML Kit Text Recognition — no network, no API key.
/// PDFs are rendered page-by-page at 2× scale via [pdfx].
///
/// ### Multi-script strategy
/// Government documents in India mix scripts:
///  - Bank passbooks  → mostly Latin (English)
///  - 7/12 extracts   → Devanagari (Marathi) + some Latin field names
///  - Aadhaar         → Latin + Devanagari address lines
///
/// This class runs **two OCR passes** when [extraScript] is set:
///  1. Latin pass — catches English text, numbers, IFSC codes, etc.
///  2. Extra-script pass — catches script-specific text (e.g. owner names in Marathi)
///
/// The results are concatenated with a separator so downstream extractors
/// can search both halves.
class LocalOcrService {
  static LocalOcrService? _instance;
  LocalOcrService._();
  static LocalOcrService get instance => _instance ??= LocalOcrService._();

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Download [url] and return all recognised text.
  ///
  /// [docType] is used to decide which scripts to run.
  ///   • 'seven_twelve' | 'eight_a' | 'land_certificate' → Latin + Devanagari
  ///   • 'aadhaar'                                        → Latin + Devanagari
  ///   • Everything else                                  → Latin only
  Future<String> extractTextFromUrl(
    String url, {
    String? mimeHint,
    String? docType,
  }) async {
    debugPrint(
        '[LocalOCR] Downloading: ${url.length > 60 ? url.substring(0, 60) : url}…');

    late File tmpFile;
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        debugPrint('[LocalOCR] Download failed: ${resp.statusCode}');
        return '';
      }
      final contentType = mimeHint ?? resp.headers['content-type'] ?? '';
      final ext = _extensionFor(contentType, url);
      final tmpDir = await getTemporaryDirectory();
      tmpFile = File(
          '${tmpDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await tmpFile.writeAsBytes(resp.bodyBytes);
    } catch (e) {
      debugPrint('[LocalOCR] Download error: $e');
      return '';
    }

    try {
      final isPdf = tmpFile.path.endsWith('.pdf');
      final needsDevanagari = _needsDevanagari(docType ?? '');

      if (isPdf) {
        return await _ocrPdf(tmpFile, addDevanagari: needsDevanagari);
      } else {
        return await _ocrImageMultiScript(tmpFile,
            addDevanagari: needsDevanagari);
      }
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
  }

  // ─── Script selection ─────────────────────────────────────────────────────

  bool _needsDevanagari(String docType) {
    final d = docType.toLowerCase();
    return d.contains('seven_twelve') ||
        d.contains('eight_a') ||
        d.contains('land_certificate') ||
        d.contains('aadhaar') ||
        d.contains('income_cert');
  }

  // ─── PDF ──────────────────────────────────────────────────────────────────

  Future<String> _ocrPdf(File pdfFile, {bool addDevanagari = false}) async {
    final buffer = StringBuffer();
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfFile.path);
      debugPrint('[LocalOCR] PDF: ${doc.pagesCount} pages');

      final pages = doc.pagesCount.clamp(1, 5);
      for (var i = 1; i <= pages; i++) {
        final page = await doc.getPage(i);
        // 2.5× scale for better text legibility
        final pageImage = await page.render(
          width: page.width * 2.5,
          height: page.height * 2.5,
          format: PdfPageImageFormat.jpeg,
          quality: 92,
        );
        await page.close();
        if (pageImage?.bytes == null) continue;

        final tmpDir = await getTemporaryDirectory();
        final tmpImg = File(
            '${tmpDir.path}/ocr_p${i}_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tmpImg.writeAsBytes(pageImage!.bytes);

        final text =
            await _ocrImageMultiScript(tmpImg, addDevanagari: addDevanagari);
        if (text.isNotEmpty) buffer.write('$text\n\n');

        try {
          await tmpImg.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[LocalOCR] PDF OCR error: $e');
    } finally {
      await doc?.close();
    }
    return buffer.toString().trim();
  }

  // ─── Image: dual-script pass ──────────────────────────────────────────────

  /// Runs Latin OCR first (always). If [addDevanagari] is true, also runs
  /// a Devanagari pass and appends the result separated by `\n---DEVANAGARI---\n`.
  Future<String> _ocrImageMultiScript(
    File imageFile, {
    bool addDevanagari = false,
  }) async {
    final latinText = await _ocrImage(imageFile, TextRecognitionScript.latin);
    debugPrint('[LocalOCR] Latin pass: ${latinText.length} chars');

    if (!addDevanagari) return latinText;

    try {
      final devText =
          await _ocrImage(imageFile, TextRecognitionScript.devanagiri);
      debugPrint('[LocalOCR] Devanagiri pass: ${devText.length} chars');
      if (devText.isNotEmpty) {
        return '$latinText\n\n---DEVANAGARI---\n$devText';
      }
    } catch (e) {
      // Devanagiri model not available on this device/build — use Latin only.
      // This is non-fatal; numeric fields (survey no, area) come from Latin.
      debugPrint('[LocalOCR] Devanagiri pass failed (model missing?): $e');
    }
    return latinText;
  }

  // ─── Single-script pass ───────────────────────────────────────────────────

  Future<String> _ocrImage(File imageFile, TextRecognitionScript script) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final result = await recognizer.processImage(inputImage);
      return result.text;
    } catch (e) {
      debugPrint('[LocalOCR] OCR error ($script): $e');
      return '';
    } finally {
      recognizer.close();
    }
  }

  // ─── Extension helper ─────────────────────────────────────────────────────

  String _extensionFor(String contentType, String url) {
    final lower = contentType.toLowerCase();
    if (lower.contains('pdf')) return 'pdf';
    if (lower.contains('png')) return 'png';
    if (lower.contains('webp')) return 'webp';
    final urlExt = url.split('?').first.split('.').last.toLowerCase();
    if (['pdf', 'jpg', 'jpeg', 'png', 'webp'].contains(urlExt)) return urlExt;
    return 'jpg';
  }
}
