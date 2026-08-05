import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/capture/capture_cubit.dart';

/// Live capture from the drone's cameras.
///
/// The aircraft carries two camera systems and they feed different things:
/// the multispectral rig becomes a K-means **spray prescription**, and the
/// ordinary RGB camera becomes a **weed + disease scan**. One press of
/// Capture triggers all of them at once — the bands of a shot have to describe
/// the same patch of ground, or the index maths is comparing two moments.
///
/// Cameras are registered by the operator; nothing is invented. A camera that
/// does not exist cannot take a picture, and a fake one in the list is worse
/// than an empty list.
class LiveCapturePage extends StatefulWidget {
  const LiveCapturePage({super.key});

  @override
  State<LiveCapturePage> createState() => _LiveCapturePageState();
}

class _LiveCapturePageState extends State<LiveCapturePage> {
  @override
  void initState() {
    super.initState();
    context.read<CaptureCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(
          'Drone Capture',
          style: AppTextStyle.textLgSemibold.copyWith(color: AppColors.light100),
        ),
        actions: [
          IconButton(
            tooltip: 'New session',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => context.read<CaptureCubit>().newSession(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<CaptureCubit, CaptureState>(
          builder: (context, state) {
            if (state.isBusy && !state.loaded) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: () => context.read<CaptureCubit>().load(refresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _ReadinessCard(state: state),
                  const SizedBox(height: AppSpacing.lg),
                  _CameraListCard(state: state),
                  const SizedBox(height: AppSpacing.lg),
                  _CaptureCard(state: state),
                  if (state.errorMessage.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ErrorBanner(message: state.errorMessage),
                  ],
                  if (state.lastShot != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ShotCard(shot: state.lastShot!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _NextStepsCard(state: state),
                  if (state.shots.length > 1) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ShotHistory(shots: state.shots),
                  ],
                  const SizedBox(height: 60),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Readiness ────────────────────────────────────────────────────────────────

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final registry = state.registry;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.videocam_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Camera systems', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _StatusRow(
            ok: registry.readyForMultispectral,
            label: 'Multispectral rig',
            okText: 'Ready — ${registry.multispectralBands.join(', ')}',
            // Say exactly what is missing: without red + NIR no vegetation
            // index can be computed at all, so there is no prescription.
            missingText:
                'Needs at least a red and an NIR band feed to build a spray '
                'prescription.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatusRow(
            ok: registry.hasRgb,
            label: 'RGB camera',
            okText: 'Ready — feeds the weed & disease scan',
            missingText: 'Add the normal IP camera to scan for weeds and disease.',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.label,
    required this.okText,
    required this.missingText,
  });

  final bool ok;
  final String label, okText, missingText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: ok ? AppColors.themeSuccess : AppColors.themeWarning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyle.textSmSemibold),
              Text(
                ok ? okText : missingText,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Camera registry ──────────────────────────────────────────────────────────

class _CameraListCard extends StatelessWidget {
  const _CameraListCard({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Registered feeds (${state.registry.cameras.length})',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              TextButton.icon(
                onPressed: () => _CameraSheet.show(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          if (state.registry.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No cameras yet. Add the drone\'s band feeds (RTSP, MJPEG or a '
                'snapshot URL) and its RGB camera.',
                style: AppTextStyle.textSmRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            )
          else
            ...state.registry.cameras.map(
              (camera) => _CameraRow(camera: camera),
            ),
        ],
      ),
    );
  }
}

class _CameraRow extends StatelessWidget {
  const _CameraRow({required this.camera});

  final CameraFeed camera;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: camera.isMultispectral
                  ? AppColors.primaryFade
                  : AppColors.light500,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              camera.band?.replaceAll('_', ' ').toUpperCase() ?? 'RGB',
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(camera.name, style: AppTextStyle.textSmSemibold),
                Text(
                  camera.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Test feed',
            icon: const Icon(Icons.wifi_tethering, size: 20),
            onPressed: () async {
              final cubit = context.read<CaptureCubit>();
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                const SnackBar(content: Text('Testing feed…')),
              );
              final probe = await cubit.testCamera(cameraId: camera.id);
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    probe.reachable
                        ? '${camera.name}: live '
                              '(${probe.width}×${probe.height}, '
                              '${probe.latencyMs} ms)'
                        : '${camera.name}: ${probe.message}',
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => context.read<CaptureCubit>().removeCamera(camera.id),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for registering one camera.
class _CameraSheet extends StatefulWidget {
  const _CameraSheet();

  static Future<void> show(BuildContext context) {
    final cubit = context.read<CaptureCubit>();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.light100,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => BlocProvider.value(value: cubit, child: const _CameraSheet()),
    );
  }

  @override
  State<_CameraSheet> createState() => _CameraSheetState();
}

class _CameraSheetState extends State<_CameraSheet> {
  static const _bands = ['blue', 'green', 'red', 'red_edge', 'nir'];

  final _name = TextEditingController();
  final _url = TextEditingController();
  final _fov = TextEditingController(text: '62');
  String _role = 'multispectral';
  String _band = 'nir';
  bool _saving = false;
  CameraProbe? _probe;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _fov.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a camera feed', style: AppTextStyle.textLgSemibold),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'multispectral',
                  label: Text('Multispectral'),
                ),
                ButtonSegment(value: 'rgb', label: Text('RGB')),
              ],
              selected: {_role},
              onSelectionChanged: (value) => setState(() => _role = value.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'NIR band / Nose camera',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Stream or snapshot URL',
                hintText: 'rtsp://192.168.1.50:554/stream1',
                border: OutlineInputBorder(),
              ),
            ),
            if (_role == 'multispectral') ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _band,
                decoration: const InputDecoration(
                  labelText: 'Band this sensor sees',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final band in _bands)
                    DropdownMenuItem(
                      value: band,
                      child: Text(band.replaceAll('_', ' ')),
                    ),
                ],
                onChanged: (value) => setState(() => _band = value ?? 'nir'),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _fov,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Horizontal field of view (degrees)',
                // Without the FOV a prescription still renders; it just can't
                // be turned into coordinates the drone can fly to.
                helperText: 'Needed to turn a prescription into spray waypoints',
                border: OutlineInputBorder(),
              ),
            ),
            if (_probe != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    _probe!.reachable ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: _probe!.reachable
                        ? AppColors.themeSuccess
                        : AppColors.themeError,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _probe!.message,
                      style: AppTextStyle.textXsRegular,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _test,
                    child: const Text('Test feed'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _test() async {
    if (_url.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final probe = await context.read<CaptureCubit>().testCamera(
      url: _url.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _probe = probe;
      _saving = false;
    });
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty) {
      setState(
        () => _probe = const CameraProbe(
          reachable: false,
          message: 'A camera needs a stream or snapshot URL.',
        ),
      );
      return;
    }
    setState(() => _saving = true);

    final ok = await context.read<CaptureCubit>().addCamera(
      name: _name.text.trim().isEmpty
          ? (_role == 'rgb' ? 'RGB camera' : '$_band band')
          : _name.text.trim(),
      role: _role,
      url: _url.text.trim(),
      band: _role == 'multispectral' ? _band : null,
      fovDeg: double.tryParse(_fov.text.trim()),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }
}

// ── Capture ──────────────────────────────────────────────────────────────────

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Capture', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Every enabled feed is grabbed at the same instant and stamped with '
            'the aircraft\'s position.',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            initialValue: state.fieldName,
            decoration: const InputDecoration(
              labelText: 'Block / field name (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => context.read<CaptureCubit>().setFieldName(value),
          ),
          if (state.sessionId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Session ${state.sessionId}',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: state.isCapturing || !state.hasCameras
                  ? null
                  : () => context.read<CaptureCubit>().shoot(),
              icon: state.isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.light100,
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(state.isCapturing ? 'Capturing…' : 'Capture now'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state.isCapturing
                  ? null
                  : () => _uploadFrames(context),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Upload frames instead'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For a rig that records to a card, or to try the whole chain with '
            'no cameras attached. Name each file after its band (nir, red, '
            'red_edge, green, blue) — anything else is treated as RGB.',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark100),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadFrames(BuildContext context) async {
    final cubit = context.read<CaptureCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await MediaPicker.pickImages();
      if (files.isEmpty) return;

      final bands = <String, MediaFile>{};
      for (final file in files) {
        bands[_bandOf(file.name)] = file;
      }
      await cubit.uploadFrames(bands);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// Guess the band from the filename, the same way the analyzer does.
  /// `red_edge` is checked before `red` — otherwise every red-edge file would
  /// be filed as the red band.
  String _bandOf(String filename) {
    final name = filename.toLowerCase();
    for (final band in ['red_edge', 'rededge', 'nir', 'red', 'green', 'blue']) {
      if (name.contains(band)) {
        return band == 'rededge' ? 'red_edge' : band;
      }
    }
    return 'rgb';
  }
}

// ── Shot ─────────────────────────────────────────────────────────────────────

class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.shot});

  final CaptureShot shot;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Latest shot', style: AppTextStyle.textMdSemibold),
              ),
              _Pill(
                text: shot.analysable ? 'Analysable' : 'Not analysable',
                color: shot.analysable
                    ? AppColors.themeSuccess
                    : AppColors.themeWarning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            shot.hasFix
                ? '${shot.frames.length} frame(s) · geotagged'
                : '${shot.frames.length} frame(s) · no GPS fix, so this shot '
                      'cannot become spray waypoints',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shot.frames.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final frame = shot.frames[index];
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox(
                        width: 96,
                        height: 72,
                        child: frame.previewUrl == null
                            ? Container(color: AppColors.light500)
                            : Image.network(
                                frame.previewUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Container(color: AppColors.light500),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(frame.label, style: AppTextStyle.textXsMedium),
                  ],
                );
              },
            ),
          ),
          if (shot.errors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // A dead band is reported, not silently dropped — the operator
            // needs to know which sensor did not answer.
            ...shot.errors.entries.map(
              (entry) => Text(
                '${entry.key}: ${entry.value}',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.themeError,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShotHistory extends StatelessWidget {
  const _ShotHistory({required this.shots});

  final List<CaptureShot> shots;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This session', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.sm),
          ...shots.take(12).map(
            (shot) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                shot.analysable ? Icons.grain : Icons.photo_camera_back_outlined,
                color: AppColors.primary,
              ),
              title: Text(
                shot.bands.isEmpty ? 'RGB frame' : shot.bands.join(', '),
                style: AppTextStyle.textSmMedium,
              ),
              subtitle: Text(
                shot.shotId,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark100,
                ),
              ),
              trailing: shot.analysable
                  ? TextButton(
                      onPressed: () => Navigator.of(context).pushNamed(
                        AppRouterNames.spray,
                        arguments: shot.shotId,
                      ),
                      child: const Text('Prescribe'),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Next steps ───────────────────────────────────────────────────────────────

class _NextStepsCard extends StatelessWidget {
  const _NextStepsCard({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final analysable = state.analysableShot;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What next', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.md),
          _NextStep(
            icon: Icons.scatter_plot_outlined,
            title: 'Build a spray prescription',
            detail:
                'K-means the multispectral shot into severe / moderate / healthy '
                'zones and see how much pesticide targeting would save.',
            enabled: analysable != null,
            disabledReason:
                'Capture a multispectral shot with a red + NIR pair first.',
            onTap: () => Navigator.of(
              context,
            ).pushNamed(AppRouterNames.spray, arguments: analysable?.shotId),
          ),
          const Divider(height: AppSpacing.xxl),
          _NextStep(
            icon: Icons.pest_control_outlined,
            title: 'Scan for weeds & disease',
            detail:
                'Run the CNN over the RGB frames from this low-pace pass to find '
                'weed patches and name the likely crop disease.',
            enabled: state.sessionId != null,
            disabledReason: 'Capture at least one RGB frame first.',
            onTap: () => Navigator.of(
              context,
            ).pushNamed(AppRouterNames.fieldScan, arguments: state.sessionId),
          ),
        ],
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.enabled,
    required this.disabledReason,
    required this.onTap,
  });

  final IconData icon;
  final String title, detail, disabledReason;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: enabled ? AppColors.primary : AppColors.dark100),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.textSmSemibold.copyWith(
                    color: enabled ? AppColors.dark700 : AppColors.dark100,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled ? detail : disabledReason,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ],
            ),
          ),
          if (enabled)
            const Icon(Icons.chevron_right, color: AppColors.dark100),
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        text,
        style: AppTextStyle.textXsSemibold.copyWith(color: color),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.themeError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.themeError.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.themeError,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.themeError,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
