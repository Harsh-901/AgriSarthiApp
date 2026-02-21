import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Phase 4 – Review Sheet
///
/// Summary bottom sheet showing all field → value mappings before
/// the farmer confirms and the agent injects them into the WebView.
///
/// Usage:
/// ```dart
/// final confirmed = await showReviewSheet(
///   context: context,
///   mapping: {'farmer_name': 'Likhit', 'state': 'Maharashtra'},
///   onEdit: (fieldId) async { ... return newValue; },
/// );
/// if (confirmed == true) { /* inject */ }
/// ```
Future<bool> showReviewSheet({
  required BuildContext context,
  required Map<String, String?> mapping,
  required Future<String?> Function(String fieldId, String? currentValue)
      onEdit,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewSheet(mapping: mapping, onEdit: onEdit),
  );
  return result ?? false;
}

class _ReviewSheet extends StatefulWidget {
  final Map<String, String?> mapping;
  final Future<String?> Function(String, String?) onEdit;

  const _ReviewSheet({required this.mapping, required this.onEdit});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final Map<String, String?> _editableMap;

  @override
  void initState() {
    super.initState();
    _editableMap = Map.from(widget.mapping);
  }

  int get _filledCount =>
      _editableMap.values.where((v) => v != null && v.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.auto_fix_high_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Review Before Filling',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '$_filledCount of ${_editableMap.length} fields ready',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ],
                ),
              ),

              // ── Field list ──────────────────────────────────────────────
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _editableMap.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final key = _editableMap.keys.elementAt(i);
                    final value = _editableMap[key];
                    final hasValue = value != null && value.isNotEmpty;
                    return _FieldTile(
                      fieldKey: key,
                      value: value,
                      onEdit: () async {
                        final updated = await widget.onEdit(key, value);
                        if (updated != null && mounted) {
                          setState(() => _editableMap[key] = updated);
                        }
                      },
                    );
                  },
                ),
              ),

              // ── CTA ────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.flash_on_rounded),
                        label: const Text(
                          'Fill Form Now',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Single field row ─────────────────────────────────────────────────────────

class _FieldTile extends StatelessWidget {
  final String fieldKey;
  final String? value;
  final VoidCallback onEdit;

  const _FieldTile({
    required this.fieldKey,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasValue
              ? AppColors.borderLight
              : AppColors.warning.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasValue
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 18,
            color: hasValue ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _prettyKey(fieldKey),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasValue ? value! : '— not found —',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: hasValue ? AppColors.textPrimary : AppColors.warning,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppColors.textHint,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  String _prettyKey(String key) =>
      key.replaceAll(RegExp(r'[_\-]'), ' ').toUpperCase();
}
