import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:agri_vision/src/src.dart';

/// The two documents Google Play requires the app itself to show.
enum LegalDocument {
  privacy('assets/legal/privacy_policy.md'),
  terms('assets/legal/terms.md');

  const LegalDocument(this.asset);

  /// Where the bundled copy lives.
  final String asset;
}

/// The privacy policy or the terms, readable inside the app.
///
/// Google Play requires the privacy policy to be reachable from within the
/// app, not only from the store listing. The text is bundled rather than
/// fetched: a farmer should be able to read what happens to their photos before
/// they have a connection, and before they have an account.
///
/// The bundled copy is identical to the one the backend serves at `/privacy`
/// and `/terms`; a test fails if the two drift apart.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.document, super.key});

  final LegalDocument document;

  static Future<void> open(BuildContext context, LegalDocument document) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocumentPage(document: document)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = document == LegalDocument.privacy
        ? context.l10n.privacyPolicy
        : context.l10n.termsOfUse;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(title),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(document.asset),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This document could not be opened.',
                  textAlign: TextAlign.center,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: MarkdownText(snapshot.data!, color: AppColors.dark700),
          );
        },
      ),
    );
  }
}
