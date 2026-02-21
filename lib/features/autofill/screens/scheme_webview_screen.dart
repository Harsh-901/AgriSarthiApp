import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/ocr_data_service.dart';
import '../../../core/theme/app_theme.dart';
import '../services/autofill_llm_service.dart';
import '../services/document_autoupload_service.dart';
import '../services/smart_form_mapper.dart';
import '../widgets/autofill_chatbot_sheet.dart';
import '../widgets/review_sheet.dart';

/// The main AutoFill Agent screen — an in-app WebView that hosts any
/// government portal URL, then runs the 5-phase autofill pipeline:
///
///  1. DOM extraction  (dom_extractor.js → AutofillChannel)
///  2. OCR data fetch  (OcrDataService)
///  3. SLM mapping     (AutofillLlmService → Gemma 3-1B on-device)
///  4. Form injection  (form_filler.js)
///  5. Review & confirm (ReviewSheet)
///
/// Route: /scheme-webview?url=...&name=...
class SchemeWebviewScreen extends StatefulWidget {
  final String url;
  final String schemeName;

  const SchemeWebviewScreen({
    super.key,
    required this.url,
    required this.schemeName,
  });

  @override
  State<SchemeWebviewScreen> createState() => _SchemeWebviewScreenState();
}

class _SchemeWebviewScreenState extends State<SchemeWebviewScreen> {
  // ─── State ───────────────────────────────────────────────────────────────

  late final WebViewController _webViewController;
  final OcrDataService _ocrService = OcrDataService.instance;
  final AutofillLlmService _llm = AutofillLlmService.instance;
  final SmartFormMapper _mapper = SmartFormMapper.instance;

  bool _isPageLoading = true;
  _AgentState _agentState = _AgentState.idle;
  double _modelDownloadProgress = 0.0; // 0–100

  /// Fields extracted from the live DOM via dom_extractor.js (Phase 1).
  List<Map<String, dynamic>> _extractedFields = [];

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AutofillChannel',
        onMessageReceived: _onFieldsExtracted,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isPageLoading = true),
          onPageFinished: _onPageFinished,
          onHttpError: (e) =>
              debugPrint('[WebView] HTTP error: ${e.response?.statusCode}'),
          onWebResourceError: (e) =>
              debugPrint('[WebView] Error: ${e.description}'),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  // ─── Phase 1: DOM extraction ────────────────────────────────────────────

  Future<void> _onPageFinished(String url) async {
    setState(() => _isPageLoading = false);
    debugPrint('[AutoFill] Page loaded: $url – injecting extractor…');
    await _injectDomExtractor();
  }

  Future<void> _injectDomExtractor() async {
    final js = await rootBundle.loadString('assets/scripts/dom_extractor.js');
    try {
      await _webViewController.runJavaScript(js);
    } catch (e) {
      debugPrint('[AutoFill] DOM extractor injection error: $e');
    }
  }

  void _onFieldsExtracted(JavaScriptMessage message) {
    try {
      final list =
          (jsonDecode(message.message) as List).cast<Map<String, dynamic>>();
      setState(() => _extractedFields = list);
      debugPrint('[AutoFill] Phase 1: extracted ${list.length} fields.');
    } catch (e) {
      debugPrint('[AutoFill] Failed to parse extracted fields: $e');
    }
  }

  // ─── Pipeline orchestrator ───────────────────────────────────────────────

  Future<void> _runAutofillPipeline() async {
    if (_agentState != _AgentState.idle) return;

    // ── 0. Ensure fields are available ────────────────────────────────────
    if (_extractedFields.isEmpty) {
      await _injectDomExtractor();
      await Future.delayed(const Duration(milliseconds: 600));
      if (_extractedFields.isEmpty && mounted) {
        _showSnack('No form fields detected on this page.', isError: true);
        return;
      }
    }

    // ── 1. Fetch OCR data from farmer's documents ──────────────────────────
    setState(() => _agentState = _AgentState.loadingProfile);
    final ocrData = await _ocrService.fetchOcrData();
    if (ocrData.isEmpty) {
      if (mounted) {
        _showSnack(
            'No document data found. Please upload your documents first.',
            isError: true);
      }
      setState(() => _agentState = _AgentState.idle);
      return;
    }

    if (!mounted) return;

    // ── 2. 3-stage smart mapping ───────────────────────────────────────────
    //   Stage 1: alias match  (instant, no LLM)
    //   Stage 2: targeted snippet search  (regex on relevant doc section)
    //   Stage 3: Gemma LLM  (only residual fields + focused snippets)
    setState(() => _agentState = _AgentState.thinking);

    SmartMappingResult smartResult;
    try {
      smartResult = await _mapper.map(
        fields: _extractedFields,
        ocrData: ocrData,
        // Only download Gemma when there are still-missing fields after
        // stages 1 & 2 — avoids the 529 MB download for simple forms.
        ensureLlmReady: () async {
          if (!mounted) return;
          setState(() {
            _agentState = _AgentState.downloading;
            _modelDownloadProgress = 0.0;
          });
          await _llm.ensureModelInstalled(
            onProgress: (pct) {
              if (mounted) setState(() => _modelDownloadProgress = pct);
            },
          );
          if (mounted) setState(() => _agentState = _AgentState.thinking);
        },
      );
    } catch (e) {
      debugPrint('[AutoFill] SmartMapper failed: $e');
      if (mounted) {
        _showSnack('Mapping failed. Please try again.', isError: true);
        setState(() => _agentState = _AgentState.idle);
      }
      return;
    }

    debugPrint(
        '[AutoFill] SmartMapper: ${smartResult.confident.length} confident, '
        '${smartResult.needsUser.length} need user');

    if (!mounted) return;

    // ── 3. Inject confident values into the live form ─────────────────────
    setState(() => _agentState = _AgentState.filling);
    // Convert confident Map<String,String> to Map<String,String?> for filler
    final mapping = <String, String?>{...smartResult.confident};
    await _injectFormFiller(mapping);

    if (!mounted) return;

    // ── 3b. Auto-upload documents for file inputs ─────────────────────────
    final fileFields = _extractedFields
        .where((f) => (f['type'] as String?) == 'file')
        .toList();
    if (fileFields.isNotEmpty) {
      for (final field in fileFields) {
        if (!mounted) return;
        final key = (field['id'] as String? ?? '').isNotEmpty
            ? field['id'] as String
            : field['name'] as String? ?? '';
        final label = (field['label'] as String?) ?? key;
        final result = await DocumentAutoUploadService.instance.tryAutoUpload(
          fieldKey: key,
          fieldLabel: label,
          runJs: (js) async {
            try {
              final r =
                  await _webViewController.runJavaScriptReturningResult(js);
              return r.toString();
            } catch (e) {
              return '{"ok":false,"reason":"$e"}';
            }
          },
        );
        if (result.isSuccess && mounted) {
          _showSnack('📄 Uploaded ${result.info} for "$label"');
        } else if (result.isNotFound && mounted) {
          _showSnack(
            'ℹ️ No document found for "$label" — please attach manually.',
            isError: false,
          );
        }
      }
    }

    if (!mounted) return;

    // ── 4. NLP chatbot for uncertain / missing fields ─────────────────────
    if (smartResult.needsUser.isNotEmpty) {
      setState(() => _agentState = _AgentState.highlighting);

      // Highlight all fields that need user attention first
      await _highlightFields(smartResult.needsUser.map((f) => f.key).toList());

      // Single chatbot conversation for all of them
      final userAnswers = await showAutofillChatbotSheet(
        context: context,
        fieldsToAsk: smartResult.needsUser,
      );

      // Inject user-provided values immediately
      if (userAnswers.isNotEmpty && mounted) {
        setState(() => _agentState = _AgentState.filling);
        for (final entry in userAnswers.entries) {
          await _injectSingleValue(entry.key, entry.value);
          mapping[entry.key] = entry.value;
        }
      }

      await _highlightFields([]); // clear highlights
    }

    if (!mounted) return;

    // ── 5. Review sheet — user confirms before submitting ─────────────────
    setState(() => _agentState = _AgentState.reviewing);
    final confirmed = await showReviewSheet(
      context: context,
      mapping: mapping,
      onEdit: (fieldId, currentValue) async => null,
    );

    if (!confirmed || !mounted) {
      setState(() => _agentState = _AgentState.idle);
      return;
    }

    if (mounted) {
      _showSnack('✅ Form filled! Please review and tap Submit.');
      setState(() => _agentState = _AgentState.done);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _agentState = _AgentState.idle);
    }
  }

  // ─── Phase 4: Form injection ─────────────────────────────────────────────

  /// Serialize [mapping] and inject form_filler.js into the WebView.
  /// Returns the list of field keys that could not be filled.
  Future<List<String>> _injectFormFiller(Map<String, String?> mapping) async {
    final template =
        await rootBundle.loadString('assets/scripts/form_filler.js');
    final mappingJson = jsonEncode(mapping);
    final js = template.replaceFirst('MAPPING_JSON', mappingJson);

    try {
      final result = await _webViewController.runJavaScriptReturningResult(js);
      debugPrint('[AutoFill] form_filler raw result: $result');

      // Android's WebView wraps JS string return values in an extra JSON layer,
      // so JSON.stringify({...}) comes back as "\"{ ... }\"" in Dart.
      // We decode once; if the result is still a String, decode again.
      dynamic firstDecode = jsonDecode(result.toString());
      final Map<String, dynamic> parsed = firstDecode is String
          ? jsonDecode(firstDecode) as Map<String, dynamic>
          : firstDecode as Map<String, dynamic>;

      debugPrint('[AutoFill] form_filler parsed: $parsed');
      return (parsed['skippedKeys'] as List<dynamic>? ?? []).cast<String>();
    } catch (e) {
      debugPrint('[AutoFill] Form filler error: $e');
      return [];
    }
  }

  /// Inject a single key→value into the live form using the React-safe setter.
  Future<void> _injectSingleValue(String key, String value) async {
    // Escape both key and value for safe JS string embedding
    final safeKey = key.replaceAll("'", r"\'");
    final safeVal = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final js = '''
(function() {
  var el = document.getElementById('$safeKey') ||
           document.querySelector('[name="$safeKey"]');
  if (!el) return;
  var tag = el.tagName.toUpperCase();
  if (tag === 'SELECT') {
    var opts = el.options;
    var lc = '$safeVal'.toLowerCase().trim();
    for (var i = 0; i < opts.length; i++) {
      if (opts[i].value.toLowerCase().trim() === lc ||
          opts[i].text.toLowerCase().trim() === lc) {
        var ns = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype,'value');
        if (ns && ns.set) ns.set.call(el, opts[i].value);
        else el.selectedIndex = i;
        el.dispatchEvent(new Event('change',{bubbles:true}));
        return;
      }
    }
  } else if (el.type === 'checkbox') {
    el.checked = ('$safeVal' === 'true' || '$safeVal' === 'yes' || '$safeVal' === '1');
    el.dispatchEvent(new Event('change',{bubbles:true}));
  } else {
    var ni = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
    if (ni && ni.set) ni.set.call(el,'$safeVal');
    else el.value = '$safeVal';
    el.dispatchEvent(new InputEvent('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
  }
})();
''';
    try {
      await _webViewController.runJavaScript(js);
    } catch (e) {
      debugPrint('[AutoFill] Single inject error for $key: $e');
    }
  }

  Future<void> _highlightFields(List<String> keys) async {
    final template =
        await rootBundle.loadString('assets/scripts/field_highlighter.js');
    final js = template.replaceFirst('HIGHLIGHT_JSON', jsonEncode(keys));
    try {
      await _webViewController.runJavaScript(js);
    } catch (e) {
      debugPrint('[AutoFill] Highlight error: $e');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0.5,
        leading: const BackButton(color: AppColors.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.schemeName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.url,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textHint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: () => _webViewController.reload(),
            tooltip: 'Reload',
          ),
        ],
        bottom: _isPageLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.borderLight,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          // ── WebView ────────────────────────────────────────────────────
          WebViewWidget(controller: _webViewController),

          // ── Agent overlay ──────────────────────────────────────────────
          if (_agentState != _AgentState.idle &&
              _agentState != _AgentState.done)
            _AgentStatusOverlay(
              state: _agentState,
              downloadProgress: _modelDownloadProgress,
            ),
        ],
      ),
      floatingActionButton: _buildAgentFab(),
    );
  }

  Widget _buildAgentFab() {
    final isWorking =
        _agentState != _AgentState.idle && _agentState != _AgentState.done;

    return FloatingActionButton.extended(
      onPressed: isWorking ? null : _runAutofillPipeline,
      backgroundColor: isWorking ? AppColors.textHint : AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 6,
      icon: isWorking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.auto_fix_high_rounded),
      label: Text(
        isWorking ? 'Agent Working…' : '✨  AutoFill',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }
}

// ─── Agent state enum ─────────────────────────────────────────────────────────

enum _AgentState {
  idle,
  downloading, // Downloading / activating the SLM (only if Stage 3 needed)
  loadingProfile, // Fetching OCR data from documents
  thinking, // 3-stage smart mapping running
  filling, // Injecting values into the live form
  highlighting, // Chatbot open for uncertain/missing fields
  reviewing, // Review sheet open
  done,
}

// ─── Overlay widget ───────────────────────────────────────────────────────────

class _AgentStatusOverlay extends StatelessWidget {
  final _AgentState state;
  final double downloadProgress; // 0–100

  const _AgentStatusOverlay({
    required this.state,
    required this.downloadProgress,
  });

  String get _label => switch (state) {
        _AgentState.downloading => '⬇️  Loading AI for tricky fields…',
        _AgentState.loadingProfile => '📂 Loading your documents…',
        _AgentState.thinking => '🔍 Matching fields to your documents…',
        _AgentState.filling => '✍️  Filling the form…',
        _AgentState.highlighting => '💬 Confirming a few details…',
        _AgentState.reviewing => '📋 Reviewing…',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.88),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              // Download progress bar — only shown while model is downloading
              if (state == _AgentState.downloading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: downloadProgress / 100,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${downloadProgress.toStringAsFixed(0)}%  (~529 MB, first run only)',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
              if (state == _AgentState.thinking) ...[
                const SizedBox(height: 6),
                const Text(
                  'Smart matching — alias → snippet search → on-device AI',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
