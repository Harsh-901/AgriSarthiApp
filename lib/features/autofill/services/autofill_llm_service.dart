import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Download URL — Gemma 3 1B IT, INT4 quantized, ~529 MB.
/// Hosted by litert-community (the official MediaPipe/LiteRT model hub).
const _kModelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task';

/// HuggingFace token — injected at build time from .env via --dart-define-from-file.
const _kHfToken = String.fromEnvironment('HF_TOKEN');

/// Maximum number of fields sent to the SLM in a single inference call.
/// Keeps the prompt well under the 2048-token context window.
const _kBatchSize = 8;

/// On-device SLM mapper — Phase 2 of the AutoFill Agent pipeline.
///
/// Uses Gemma 3-1B INT4 via MediaPipe (flutter_gemma) to map form fields to
/// values from the farmer's OCR data. All inference is 100% on-device.
///
/// Key design decisions to prevent the token-overflow crashes:
///  - maxTokens is capped at 2048 (the model's actual context window).
///  - `*_raw_text` OCR keys are stripped before building the prompt.
///  - Fields are processed in batches of [_kBatchSize] so the prompt stays small.
///  - The model instance is created once per [mapFieldsToProfile] call and
///    closed after all batches are done.
class AutofillLlmService {
  static AutofillLlmService? _instance;
  AutofillLlmService._();
  static AutofillLlmService get instance =>
      _instance ??= AutofillLlmService._();

  bool _isModelReady = false;

  // ─── Model bootstrap ───────────────────────────────────────────────────────

  /// Ensure the Gemma model is installed and activated for inference.
  /// [onProgress] receives 0.0–100.0 (percent).
  ///
  /// Safe to call multiple times — skips the download if already cached but
  /// always activates the model so [FlutterGemma.getActiveModel] works.
  Future<void> ensureModelInstalled({
    ValueChanged<double>? onProgress,
  }) async {
    if (_isModelReady) {
      debugPrint('[AutofillLLM] Model already active. ✓');
      return;
    }

    debugPrint('[AutofillLLM] Installing/activating Gemma 3 1B model…');

    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
    )
        .fromNetwork(
      _kModelUrl,
      token: _kHfToken,
    )
        .withProgress((pct) {
      debugPrint('[AutofillLLM] Download: $pct%');
      onProgress?.call(pct.toDouble());
    }).install();

    _isModelReady = true;
    debugPrint('[AutofillLLM] Model ready. ✓');
  }

  // ─── Inference ─────────────────────────────────────────────────────────────

  /// Map form fields to OCR data values using on-device Gemma inference.
  ///
  /// Strips raw-text OCR keys, batches fields into groups of [_kBatchSize],
  /// runs one inference call per batch, and merges the results.
  ///
  /// Returns {field-id/name → value | null}.
  Future<Map<String, String?>> mapFieldsToProfile({
    required Map<String, dynamic> ocrData,
    required List<Map<String, dynamic>> extractedFields,
  }) async {
    if (!_isModelReady) {
      throw StateError(
          '[AutofillLLM] Model not ready. Call ensureModelInstalled() first.');
    }

    // ── Sanitise OCR data ─────────────────────────────────────────────────
    // Strip *_raw_text keys — they are large snippets of raw document text
    // intended for human context, not for the SLM prompt. Including them
    // was the primary cause of token-overflow crashes.
    final sanitizedOcr = Map<String, dynamic>.fromEntries(
      ocrData.entries
          .where((e) =>
              !e.key.endsWith('_raw_text') &&
              e.value != null &&
              e.value.toString().isNotEmpty)
          .take(25), // max 25 structured key-value pairs
    );

    final profileJson =
        const JsonEncoder.withIndent('  ').convert(sanitizedOcr);
    // Hard-cap at 500 chars to guarantee it fits in the budget
    final cappedProfile =
        profileJson.length > 500 ? profileJson.substring(0, 500) : profileJson;

    debugPrint(
        '[AutofillLLM] ${extractedFields.length} fields → batching into groups of $_kBatchSize');

    final merged = <String, String?>{};

    // ── Batch processing ──────────────────────────────────────────────────
    // IMPORTANT: We create a FRESH model instance per batch.
    // The MediaPipe LLM engine accumulates KV-cache across chat() calls
    // within the same InferenceModel instance. If we reuse the model,
    // current_step grows with each batch and eventually exceeds maxTokens,
    // causing a native OUT_OF_RANGE error followed by a SIGSEGV null-deref
    // crash. Creating a new model per batch resets the KV-cache to zero.
    for (int i = 0; i < extractedFields.length; i += _kBatchSize) {
      final batchEnd = (i + _kBatchSize).clamp(0, extractedFields.length);
      final batch = extractedFields.sublist(i, batchEnd);
      final batchNum = (i ~/ _kBatchSize) + 1;
      debugPrint('[AutofillLLM] Batch $batchNum: fields $i–${batchEnd - 1}');

      // Compact fields for this batch
      final compactFields = batch.map((f) {
        final copy = Map<String, dynamic>.from(f)
          ..remove('placeholder')
          ..remove('required');
        if (copy.containsKey('options')) {
          copy['options'] = (copy['options'] as List).take(5).toList();
        }
        return copy;
      }).toList();

      var fieldsJson = jsonEncode(compactFields);
      if (fieldsJson.length > 600) fieldsJson = fieldsJson.substring(0, 600);

      final prompt = _buildPrompt(cappedProfile, fieldsJson);

      // Fresh model → zero KV-cache → guaranteed to fit within maxTokens
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      );
      try {
        final batchResult = await _runInference(model, prompt);
        merged.addAll(batchResult);
      } finally {
        await model.close();
        debugPrint('[AutofillLLM] Batch $batchNum model closed.');
      }
    }

    debugPrint(
        '[AutofillLLM] Final mapping: ${merged.entries.where((e) => e.value != null).length}/${merged.length} fields filled');
    return merged;
  }

  // ─── Prompt builder ────────────────────────────────────────────────────────

  String _buildPrompt(String profileJson, String fieldsJson) =>
      '''<start_of_turn>user
You are a form-filling assistant for Indian farmers.
Return ONLY a valid JSON object mapping each field "id" or "name" to the best value from the farmer profile.
Rules:
- Use the "id" as key when non-empty, else use "name".
- Use JSON null for any field you cannot fill confidently.
- Date format: YYYY-MM-DD.
- For select fields, pick the closest option value.

Farmer Profile:
$profileJson

Form Fields:
$fieldsJson
<end_of_turn>
<start_of_turn>model
''';

  // ─── Single inference call ─────────────────────────────────────────────────

  Future<Map<String, String?>> _runInference(
    InferenceModel model,
    String prompt,
  ) async {
    try {
      final chat = await model.createChat();
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await chat.generateChatResponse();

      final rawText = switch (response) {
        TextResponse(:final token) => token,
        _ => '',
      };
      debugPrint('[AutofillLLM] Raw batch response: $rawText');
      return _parseJsonMapping(rawText);
    } catch (e) {
      debugPrint('[AutofillLLM] Inference error: $e');
      return {};
    }
  }

  // ─── JSON parser ───────────────────────────────────────────────────────────

  Map<String, String?> _parseJsonMapping(String raw) {
    var cleaned = raw.trim();
    // Strip ``` fences in case the model wraps output
    cleaned = cleaned.replaceAll(RegExp(r'```[a-z]*\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```\s*', multiLine: true), '');

    // Extract first valid {...} JSON block
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      debugPrint('[AutofillLLM] No JSON block found in response.');
      return {};
    }

    cleaned = cleaned.substring(start, end + 1);

    try {
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v?.toString()));
    } catch (e) {
      debugPrint('[AutofillLLM] JSON parse error: $e\nRaw: $cleaned');
      return {};
    }
  }
}
