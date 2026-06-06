import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart' show AppRadius;

import '../core/freemium/freemium_service.dart';
import '../main.dart' show isSpanishNotifier;

/// A "Save Scenario" button that pins the current calculator result.
///
/// - **Premium users**: shows a name-entry dialog before saving.
/// - **Free users**: saves immediately without a label (3 max pinned slots).
class SaveScenarioButton extends StatefulWidget {
  /// Called when the user confirms the save. [label] is null for free users.
  final Future<void> Function(String? label) onSave;

  const SaveScenarioButton({super.key, required this.onSave});

  @override
  State<SaveScenarioButton> createState() => _SaveScenarioButtonState();
}

class _SaveScenarioButtonState extends State<SaveScenarioButton> {
  bool _saving = false;

  bool get _isEs => isSpanishNotifier.value;

  Future<void> _handleTap() async {
    String? label;

    if (freemiumService.hasFullAccess) {
      label = await _showNameDialog();
      if (label == null) return;
      if (label.trim().isEmpty) label = null;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(label);
      if (!mounted) return;
      final hasLabel = label != null && label.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasLabel
                ? (_isEs ? 'Escenario "$label" guardado' : 'Scenario "$label" saved')
                : (_isEs ? 'Escenario guardado' : 'Scenario saved'),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_isEs ? 'Guardar Escenario' : 'Save Scenario'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: _isEs ? 'Nombre (opcional)' : 'Scenario name (optional)',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_isEs ? 'Guardar' : 'Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : _handleTap,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bookmark_add_outlined, size: 18),
        label: Text(_saving
            ? (_isEs ? 'Guardando…' : 'Saving…')
            : (_isEs ? 'Guardar Escenario' : 'Save Scenario')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}
