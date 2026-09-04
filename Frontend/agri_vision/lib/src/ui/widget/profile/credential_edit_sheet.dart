import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/credentials/credentials_cubit.dart';

/// Bottom sheet for filling in one pilot credential — its number, who issued
/// it, and when it expires.
///
/// The expiry date is the point of the screen: the server derives the
/// valid / expiring / expired badge from it, so leaving it blank means the
/// app can never warn the operator that their licence lapsed.
class CredentialEditSheet extends StatefulWidget {
  const CredentialEditSheet({super.key, required this.credential});

  final PilotCredentialEntity credential;

  /// Returns true when the credential was saved.
  static Future<bool?> show(
    BuildContext context, {
    required PilotCredentialEntity credential,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<CredentialsCubit>(),
        child: CredentialEditSheet(credential: credential),
      ),
    );
  }

  @override
  State<CredentialEditSheet> createState() => _CredentialEditSheetState();
}

class _CredentialEditSheetState extends State<CredentialEditSheet> {
  late final TextEditingController _identifierCtrl;
  late final TextEditingController _issuerCtrl;
  DateTime? _expiresOn;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final credential = widget.credential;
    _identifierCtrl = TextEditingController(
      text: credential.isBlank ? '' : credential.value,
    );
    _issuerCtrl = TextEditingController(text: credential.issuer ?? '');
    _expiresOn = credential.expiresOn;
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _issuerCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresOn ?? DateTime(now.year + 1, now.month, now.day),
      // Past dates stay selectable: an already-lapsed licence is exactly the
      // state the operator needs to be able to record.
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) setState(() => _expiresOn = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await context.read<CredentialsCubit>().update(
        id: widget.credential.id,
        identifier: _identifierCtrl.text.trim(),
        issuer: _issuerCtrl.text.trim(),
        expiresOn: _expiresOn,
        clearExpiry: _expiresOn == null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _expiresOn == null
        ? 'No expiry set'
        : DateFormat('d MMM yyyy').format(_expiresOn!);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.credential.icon, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.credential.label,
                    style: AppTextStyle.textLgBold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _Field(
              label: 'CREDENTIAL NUMBER',
              controller: _identifierCtrl,
              hint: 'e.g. DGCA RPA-2024-MH-04871',
            ),
            const SizedBox(height: AppSpacing.md),
            _Field(
              label: 'ISSUED BY',
              controller: _issuerCtrl,
              hint: 'e.g. DGCA',
            ),
            const SizedBox(height: AppSpacing.md),

            Text(
              'EXPIRES ON',
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark100,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              onTap: _pickExpiry,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.light300,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.light500),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: AppColors.dark300,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        expiryLabel,
                        style: AppTextStyle.textMdRegular.copyWith(
                          color: _expiresOn == null
                              ? AppColors.dark300
                              : AppColors.dark900,
                        ),
                      ),
                    ),
                    if (_expiresOn != null)
                      GestureDetector(
                        onTap: () => setState(() => _expiresOn = null),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.dark300,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Without an expiry date the app cannot warn you before this '
                'credential lapses.',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error,
                style: AppTextStyle.textSmRegular.copyWith(
                  color: AppColors.themeError,
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: AppTextStyle.textMdSemibold.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.light100,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.light100,
                              ),
                            ),
                          )
                        : Text(
                            'Save',
                            style: AppTextStyle.textMdSemibold.copyWith(
                              color: AppColors.light100,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyle.textXsSemibold.copyWith(
            color: AppColors.dark100,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          style: AppTextStyle.textMdRegular,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.light300,
            hintText: hint,
            hintStyle: AppTextStyle.textMdRegular.copyWith(
              color: AppColors.dark100,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.light500),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.light500),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
