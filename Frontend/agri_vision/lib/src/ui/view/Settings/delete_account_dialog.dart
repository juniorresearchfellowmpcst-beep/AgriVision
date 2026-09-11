import 'package:flutter/material.dart';

import 'package:agri_vision/src/src.dart';

/// "Delete account", reachable from Settings.
///
/// Google Play requires an app with sign-up to let people delete their account
/// from inside the app. Deletion is permanent, so the button stays disabled
/// until the account's email address is typed: a mis-tap, or a borrowed
/// unlocked phone, should not be able to erase a farmer's history with one
/// touch. The server checks the address too; this is not the only guard.
///
/// Pops `true` once the account is gone.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({this.service, super.key});

  /// Injectable for tests; the real one otherwise.
  final AuthService? service;

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeleteAccountDialog(),
    );
  }

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.service ?? AuthService()).deleteAccount(
        confirmEmail: _email.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canConfirm = !_busy && _email.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.deleteAccountTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deleteAccountBody,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.deleteAccountConfirmHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.themeError,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.themeError,
            foregroundColor: AppColors.light100,
          ),
          onPressed: canConfirm ? _confirm : null,
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.light100,
                  ),
                )
              : Text(l10n.deleteForever),
        ),
      ],
    );
  }
}
