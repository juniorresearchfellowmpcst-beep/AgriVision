import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/advisor/advisor_cubit.dart';

/// "More information": the scan, its photo, and whatever the farmer asks next.
///
/// The detectors answer a narrow question well — is this canopy sick, and with
/// what, out of the conditions this crop gets in Madhya Pradesh. They cannot
/// answer the questions that come after it: is it safe to spray at flowering,
/// what happens if it rains tomorrow, can I use what is already in the shed.
///
/// This screen is where those go. The app's own diagnosis is sent with every
/// question so the advisor builds on it rather than quietly replacing it —
/// a farmer shown two different disease names with no explanation is worse off
/// than before they asked.
class AdvisorPage extends StatefulWidget {
  const AdvisorPage({
    this.context_,
    this.image,
    this.frameId,
    this.scanId,
    this.diseaseScanId,
    this.runId,
    this.subject,
    this.language = AppLanguage.english,
    super.key,
  });

  /// The app's own diagnosis, sent with every question.
  final Map<String, dynamic>? context_;

  /// A photo the phone holds. The ids below name one the server already has,
  /// which is the cheaper route on a field connection.
  final MediaFile? image;
  final int? frameId;
  final int? scanId;
  final int? diseaseScanId;
  final int? runId;

  /// What the conversation is about, for the subtitle.
  final String? subject;

  /// Which language to answer in. Passed explicitly rather than inferred from
  /// the farmer's typing: somebody who types their question in Hinglish still
  /// usually wants the answer in the language they set the app to.
  final AppLanguage language;

  /// Push the chat with its own cubit — one conversation per scan.
  ///
  /// Deliberately not app-scoped: carrying a conversation across to a
  /// different field would let the advisor answer about the wrong crop, which
  /// is worse than making the farmer ask again.
  static Future<void> open(
    BuildContext context, {
    Map<String, dynamic>? context_,
    MediaFile? image,
    int? frameId,
    int? scanId,
    int? diseaseScanId,
    int? runId,
    String? subject,
    AppLanguage language = AppLanguage.english,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => AdvisorCubit(),
          child: AdvisorPage(
            context_: context_,
            image: image,
            frameId: frameId,
            scanId: scanId,
            diseaseScanId: diseaseScanId,
            runId: runId,
            subject: subject,
            language: language,
          ),
        ),
      ),
    );
  }

  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends State<AdvisorPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    context.read<AdvisorCubit>().open(
      context: widget.context_,
      image: widget.image,
      frameId: widget.frameId,
      scanId: widget.scanId,
      diseaseScanId: widget.diseaseScanId,
      runId: widget.runId,
      subject: widget.subject,
      language: widget.language,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = preset ?? _controller.text;
    if (text.trim().isEmpty) return;
    context.read<AdvisorCubit>().ask(text);
    _controller.clear();
    // After the frame the new bubbles exist in, not before it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.cropAdvisor,
              style: AppTextStyle.textLgSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
            if (widget.subject != null && widget.subject!.isNotEmpty)
              Text(
                widget.subject!,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.light100.withOpacity(0.75),
                ),
              ),
          ],
        ),
      ),
      body: BlocConsumer<AdvisorCubit, AdvisorState>(
        listenWhen: (a, b) => a.messages.length != b.messages.length,
        listener: (_, __) =>
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd()),
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.isUnavailable) {
            return _Unavailable(message: state.availability.message);
          }

          return Column(
            children: [
              Expanded(
                child: state.hasConversation
                    ? ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: state.messages.length,
                        itemBuilder: (_, index) => _Bubble(
                          message: state.messages[index],
                          onRetry: context.read<AdvisorCubit>().retryLast,
                        ),
                      )
                    : _Opening(
                        suggestions: state.suggestions,
                        subject: widget.subject,
                        onPick: _send,
                      ),
              ),
              _Composer(
                controller: _controller,
                enabled: !state.isAsking,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The screen before the first question.
class _Opening extends StatelessWidget {
  const _Opening({
    required this.suggestions,
    required this.subject,
    required this.onPick,
  });

  final List<String> suggestions;
  final String? subject;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF8E6FD8).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 28,
              color: Color(0xFF8E6FD8),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          subject == null || subject!.isEmpty
              ? context.l10n.askAboutYourCrop
              : context.l10n.askAbout(subject!),
          textAlign: TextAlign.center,
          style: AppTextStyle.textXlSemibold,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.advisorAttached,
          textAlign: TextAlign.center,
          style: AppTextStyle.textSmRegular.copyWith(
            color: AppColors.dark300,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        // Starter questions tailored to the diagnosis: asking "how do I treat
        // this" about a healthy canopy would waste the farmer's first tap.
        for (final question in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Material(
              color: AppColors.light100,
              borderRadius: BorderRadius.circular(AppRadius.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(question),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          question,
                          style: AppTextStyle.textSmMedium,
                        ),
                      ),
                      const Icon(
                        Icons.north_east,
                        size: 15,
                        color: AppColors.dark100,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.advisorNeedsInternet,
          textAlign: TextAlign.center,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark100),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onRetry});

  final AdvisorMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.light100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.lg),
            topRight: const Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(isUser ? AppRadius.lg : AppRadius.sm),
            bottomRight: Radius.circular(isUser ? AppRadius.sm : AppRadius.lg),
          ),
          border: isUser ? null : Border.all(color: AppColors.light500),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.hasImage) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 13,
                    color: AppColors.light100.withOpacity(0.85),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'photo attached',
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.light100.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (message.pending)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (message.failed) ...[
              // The failed turn stays on screen carrying its reason. Dropping
              // it would leave the farmer looking at their own question with
              // no explanation.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 15,
                    color: AppColors.themeError,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      message.error!,
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.themeError,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.refresh, size: 15),
                label: Text(context.l10n.tryAgain),
              ),
            ] else
              SelectableText(
                message.text,
                style: AppTextStyle.textSmRegular.copyWith(
                  color: isUser ? AppColors.light100 : AppColors.dark700,
                  height: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.light100,
        border: Border(top: BorderSide(color: AppColors.light500)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText:
                        enabled ? context.l10n.askAQuestion : context.l10n.thinking,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 46,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8E6FD8),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: enabled ? onSend : null,
                  child: const Icon(Icons.arrow_upward, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No key configured on this server. Nothing went wrong — the feature simply
/// does not exist here, and saying so beats a button that fails when tapped.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: AppColors.dark100,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'The crop advisor is not set up',
              style: AppTextStyle.textLgSemibold,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message.isEmpty
                  ? 'Ask whoever runs the ground station to add a Gemini API '
                      'key to the backend configuration.'
                  : message,
              textAlign: TextAlign.center,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark300,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Everything else in the app works without internet. This is the '
              'one part that does not.',
              textAlign: TextAlign.center,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
