import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';

/// The survey flight, start to finish.
///
/// One screen with three faces rather than three screens, because it is one
/// continuous job and the operator's hands are usually full:
///
///   setup     → which cameras, which crop, what to look for
///   flying    → the CNN's rolling verdict as the aircraft moves
///   summary   → crop health, action plan, tank plan, treatment map, and the
///               authorisation that turns all of it into a spray
///
/// Which face shows is driven by the *run's* state, not by navigation. That is
/// what lets a second handset open this screen mid-flight and land on the
/// in-flight readout rather than on a setup form for a survey already in the
/// air.
class SurveyPage extends StatefulWidget {
  const SurveyPage({this.runId, super.key});

  /// Open a finished run straight from history.
  final int? runId;

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  /// Held from initState rather than looked up in dispose().
  ///
  /// `context.read` walks the element tree, and by the time dispose() runs the
  /// element is deactivated — Flutter asserts on that ("Looking up a
  /// deactivated widget's ancestor is unsafe"). It survived casual use because
  /// the assert only fires in debug, but it is a real throw waiting for
  /// whichever navigation happens to tear this page down at the wrong moment.
  late final SurveyCubit _survey;

  @override
  void initState() {
    super.initState();
    _survey = context.read<SurveyCubit>();
    _survey.load();
    // The crop list is the same catalogue the field-scan screen uses; loading
    // it here means the picker is populated by the time the operator reaches it.
    context.read<FieldScanCubit>().load();
    if (widget.runId != null) _survey.openSummary(widget.runId!);
  }

  @override
  void dispose() {
    // Stops the polling, not the flight: the scan runs on the server and keeps
    // going. Coming back adopts it again.
    _survey.stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SurveyCubit, SurveyState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage ||
          a.sprayMessage != b.sprayMessage ||
          a.lastShotMessage != b.lastShotMessage,
      listener: (context, state) {
        if (state.errorMessage.isNotEmpty) {
          Toast.error(state.errorMessage, AppColors.themeError);
        } else if (state.sprayMessage != null) {
          Toast.success(state.sprayMessage!, AppColors.themeSuccess);
        } else if (state.lastShotMessage != null) {
          Toast.success(state.lastShotMessage!, AppColors.themeSuccess);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.tertiary,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: AppColors.light100,
            elevation: 0,
            title: Text(
              _titleFor(state),
              style: AppTextStyle.textLgSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
            actions: [
              if (state.hasSummary)
                IconButton(
                  tooltip: 'New survey',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<SurveyCubit>().reset(),
                ),
              if (state.isFlying)
                IconButton(
                  tooltip: 'Abandon this survey',
                  icon: const Icon(Icons.close),
                  onPressed: () => _confirmCancel(context),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: switch (state) {
              _ when state.hasSummary => SurveySummaryView(state: state),
              _ when state.isFlying => SurveyFlightView(state: state),
              _ => SurveySetupView(state: state),
            },
          ),
        );
      },
    );
  }

  String _titleFor(SurveyState state) {
    if (state.hasSummary) return 'Survey Report';
    if (state.isFlying) return 'Survey in Progress';
    return 'Survey Flight';
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final cubit = context.read<SurveyCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandon this survey?'),
        content: const Text(
          'The scan stops and nothing is summarised. What has been captured '
          'so far stays on the ground station.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep flying'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.themeError),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (confirmed == true) cubit.cancel();
  }
}
