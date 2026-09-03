import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/core.dart';

/// Renders the crop advisor's answer the way Gemini's own app renders it.
///
/// The model replies in Markdown — `**bold**` lead-ins, `### headings`,
/// `* bullets`, numbered steps. Painted with a plain `Text` widget the farmer
/// reads the punctuation instead of the answer: literal asterisks around every
/// emphasised phrase and a row of hashes above every section. On a phone held
/// in the sun that is the difference between advice and noise.
///
/// A hand-written renderer rather than a package, for two reasons. The
/// well-known one (`flutter_markdown`) is discontinued, and the subset the
/// model actually emits is small and closed: headings, bullets, numbered
/// items, bold, italic, inline code, fenced code, rules, and paragraphs. That
/// subset fits in one file and can be tested directly, and it lets the
/// typography match the rest of the app instead of a package's defaults.
///
/// Anything unrecognised falls through as plain text, so a construct this does
/// not know about is shown rather than swallowed.
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.source, {
    required this.color,
    this.selectable = true,
    super.key,
  });

  final String source;

  /// Body colour. Headings and emphasis derive from it so one bubble reads as
  /// one voice on either background.
  final Color color;

  /// Farmers copy doses and product names out of answers, so this defaults on.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(source);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].spacingAbove),
          _build(context, blocks[i]),
        ],
      ],
    );
  }

  Widget _build(BuildContext context, _Block block) {
    final base = AppTextStyle.textSmRegular.copyWith(color: color, height: 1.5);

    switch (block.kind) {
      case _Kind.heading:
        return Text(
          block.text,
          style: AppTextStyle.textMdSemibold.copyWith(
            color: color,
            height: 1.35,
          ),
        );

      case _Kind.rule:
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 2),
          color: color.withValues(alpha: 0.18),
        );

      case _Kind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: SelectableText(
            block.text,
            style: base.copyWith(
              // A fenced block really is code — a command, where column
              // alignment carries meaning — so it keeps the monospace face.
              // The fallback chain names families that actually exist on the
              // platforms this ships to, rather than trusting the generic
              // alias alone.
              fontFamily: 'monospace',
              fontFamilyFallback: const [
                'RobotoMono',
                'Droid Sans Mono',
                'Menlo',
                'Courier New',
                'monospace',
              ],
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        );

      case _Kind.bullet:
      case _Kind.numbered:
        // A hanging indent, so a wrapped second line lines up under the first
        // word rather than under the marker.
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: block.kind == _Kind.numbered ? 22 : 16,
                child: Text(
                  block.kind == _Kind.numbered ? '${block.marker}.' : '•',
                  style: base.copyWith(
                    color: color.withValues(alpha: 0.65),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(child: _inline(block.text, base)),
            ],
          ),
        );

      case _Kind.paragraph:
        return _inline(block.text, base);
    }
  }

  Widget _inline(String text, TextStyle base) {
    final span = TextSpan(children: _spans(text, base), style: base);
    return selectable
        ? SelectableText.rich(span)
        : Text.rich(span);
  }

  // ── inline: **bold**, *italic*, `code` ────────────────────────────────

  static final _inlinePattern = RegExp(
    // Order matters: ** must be tried before *, or bold parses as two italics.
    r'(\*\*(?<b>.+?)\*\*)'
    r'|(__(?<b2>.+?)__)'
    r'|(`(?<c>[^`]+)`)'
    r'|(\*(?<i>[^*\n]+?)\*)'
    r'|(_(?<i2>[^_\n]+?)_)',
    dotAll: true,
  );

  List<TextSpan> _spans(String text, TextStyle base) {
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in _inlinePattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final bold = match.namedGroup('b') ?? match.namedGroup('b2');
      final italic = match.namedGroup('i') ?? match.namedGroup('i2');
      final code = match.namedGroup('c');

      if (bold != null) {
        spans.add(TextSpan(
          text: bold,
          style: base.copyWith(fontWeight: FontWeight.w600),
        ));
      } else if (code != null) {
        // Tinted, but deliberately *not* switched to a monospace family.
        //
        // Inline code here is almost always a product name or a dose —
        // "Hexaconazole 5% EC", "400 ml/acre" — not something anyone types at
        // a shell, so the monospace face buys no clarity. What it does buy is
        // a font-matching risk: "monospace" is not a real family on every
        // platform, and a face that resolves without the needed glyphs paints
        // the dose as a row of boxes. A farmer cannot read a dose that is not
        // there, so the tint carries the emphasis on its own.
        spans.add(TextSpan(
          text: code,
          style: base.copyWith(
            backgroundColor: color.withValues(alpha: 0.08),
            fontWeight: FontWeight.w500,
          ),
        ));
      } else if (italic != null) {
        spans.add(TextSpan(
          text: italic,
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  // ── blocks ────────────────────────────────────────────────────────────

  static final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^\s{0,6}[-*+•]\s+(.*)$');
  static final _numbered = RegExp(r'^\s{0,6}(\d{1,2})[.)]\s+(.*)$');
  static final _ruleLine = RegExp(r'^\s{0,3}([-*_])\s*(\1\s*){2,}$');

  static List<_Block> _parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];
    final paragraph = <String>[];
    var inFence = false;
    final fence = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_Block(_Kind.paragraph, paragraph.join(' ').trim()));
      paragraph.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.trimLeft().startsWith('```')) {
        if (inFence) {
          blocks.add(_Block(_Kind.code, fence.join('\n')));
          fence.clear();
          inFence = false;
        } else {
          flushParagraph();
          inFence = true;
        }
        continue;
      }
      if (inFence) {
        fence.add(raw);
        continue;
      }

      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }
      if (_ruleLine.hasMatch(line)) {
        flushParagraph();
        blocks.add(_Block(_Kind.rule, ''));
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        flushParagraph();
        blocks.add(_Block(_Kind.heading, heading.group(2)!.trim()));
        continue;
      }

      final numbered = _numbered.firstMatch(line);
      if (numbered != null) {
        flushParagraph();
        blocks.add(_Block(
          _Kind.numbered,
          numbered.group(2)!.trim(),
          marker: numbered.group(1),
        ));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_Block(_Kind.bullet, bullet.group(1)!.trim()));
        continue;
      }

      paragraph.add(line.trim());
    }

    // An unterminated fence is a truncated answer, not a reason to lose text.
    if (inFence && fence.isNotEmpty) {
      blocks.add(_Block(_Kind.code, fence.join('\n')));
    }
    flushParagraph();

    return blocks;
  }
}

enum _Kind { paragraph, heading, bullet, numbered, code, rule }

class _Block {
  const _Block(this.kind, this.text, {this.marker});

  final _Kind kind;
  final String text;
  final String? marker;

  /// Space above this block when it follows another.
  ///
  /// List items sit closer together than paragraphs do — a bulleted list with
  /// paragraph spacing reads as several unrelated statements rather than one
  /// list.
  double get spacingAbove => switch (kind) {
    _Kind.heading => AppSpacing.md,
    _Kind.bullet || _Kind.numbered => 5,
    _Kind.rule => AppSpacing.sm,
    _ => AppSpacing.sm,
  };
}
