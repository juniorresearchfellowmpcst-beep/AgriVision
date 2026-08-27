import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/domain/entity/system_links_entity.dart';

/// The addresses other software needs in order to reach this backend.
///
/// Two audiences, and the card keeps them apart because confusing them is the
/// classic field failure:
///
///  * **This app, on another handset** — needs the API base URL.
///  * **Mission Planner / QGroundControl** — needs a host and UDP port to
///    *send* telemetry to. The backend listens; the ground station sends. Get
///    that backwards and nothing arrives, with no error on either side.
///
/// Every value is one tap to copy, because the alternative is transcribing an
/// IP address by hand onto a phone keyboard in a field.
class ConnectionLinksCard extends StatelessWidget {
  const ConnectionLinksCard({
    required this.links,
    this.isLoading = false,
    this.errorMessage = '',
    this.onRefresh,
    super.key,
  });

  final SystemLinksEntity links;
  final bool isLoading;
  final String errorMessage;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (isLoading && links.apiBaseUrl.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (errorMessage.isNotEmpty && links.apiBaseUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMessage,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.themeError,
              ),
            ),
            if (onRefresh != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onRefresh, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }

    final mavlink = links.mavlink;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  links.hostname.isEmpty ? 'This server' : links.hostname,
                  style: AppTextStyle.textSmSemibold.copyWith(
                    color: AppColors.dark700,
                  ),
                ),
              ),
              if (onRefresh != null)
                InkWell(
                  onTap: onRefresh,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: AppColors.dark300,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── For the app on another device ───────────────────────────
          _GroupLabel('APP / API ADDRESS'),
          _CopyRow(
            label: 'Base URL',
            value: links.apiBaseUrl,
            hint: 'Put this in assets/.env as BASE_URL on another device.',
          ),
          for (final url in links.apiUrls.skip(1))
            _CopyRow(label: 'Also reachable at', value: url),

          const SizedBox(height: AppSpacing.md),

          // ── For ground-control software ─────────────────────────────
          _GroupLabel('GROUND STATION (MISSION PLANNER / QGC)'),

          if (!mavlink.available)
            _Note(
              'The server does not have pymavlink installed, so no telemetry '
              'link can be opened. Run: pip install pymavlink',
              tone: _NoteTone.warning,
            )
          else if (mavlink.listening && mavlink.gcsTargets.isNotEmpty) ...[
            _Note(
              'This server is listening. Point your ground station here — it '
              'sends, the server receives.',
              tone: _NoteTone.good,
            ),
            for (final target in mavlink.gcsTargets)
              _CopyRow(
                label: '${target.transport} target',
                value: target.address,
              ),
            _CopyRow(
              label: 'MAVProxy',
              value: mavlink.gcsTargets.first.mavproxy,
            ),
          ] else ...[
            _Note(
              mavlink.isSerial
                  ? 'The link is set to a serial radio, so nothing can connect '
                        'over the network.'
                  : 'This server dials out to the vehicle, so there is no '
                        'inbound port for a ground station yet.',
              tone: _NoteTone.warning,
            ),
            if (mavlink.listenUrl.isNotEmpty)
              _CopyRow(
                label: 'To accept a stream, set MAVLINK_URL',
                value: mavlink.listenUrl,
                hint: 'Then restart the server.',
              ),
            for (final target in mavlink.listenTargets.take(1))
              _CopyRow(
                label: 'It would then listen at',
                value: target.address,
              ),
          ],

          const SizedBox(height: AppSpacing.sm),
          _StatusLine(mavlink: mavlink),

          if (links.hints.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final hint in links.hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 6),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: AppColors.dark300,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hint,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark300,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppTextStyle.textXsRegular.copyWith(
        color: AppColors.dark300,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// One label/value pair with a copy button.
class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Copied $value'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.light300,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.light700),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: AppTextStyle.textSmSemibold.copyWith(
                        color: AppColors.dark700,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: AppColors.dark300,
                  ),
                ],
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(
              hint!,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _NoteTone { good, warning }

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.tone});

  final String text;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == _NoteTone.good
        ? AppColors.primary
        : AppColors.themeError;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: Icon(
              tone == _NoteTone.good
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 14,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textXsRegular.copyWith(
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live state of the telemetry link, so the operator can tell whether the
/// address above is currently doing anything.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.mavlink});

  final MavlinkLinkInfo mavlink;

  @override
  Widget build(BuildContext context) {
    final (String text, Color color) = switch (mavlink) {
      _ when mavlink.alive => ('Vehicle connected and sending heartbeats', AppColors.primary),
      _ when mavlink.connected => ('Link open, waiting for heartbeats', AppColors.themeWarning),
      _ => ('No telemetry link open', AppColors.dark300),
    };

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyle.textXsRegular.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
