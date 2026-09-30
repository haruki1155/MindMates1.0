import 'package:flutter/material.dart';

/// Deliberately small, safe formatting for assistant-authored text. This is
/// not an HTML or general Markdown renderer: only bold spans, simple bullets,
/// and paragraph breaks are supported.
class MindAidFormattedText extends StatelessWidget {
  const MindAidFormattedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < lines.length; index++)
          _line(context, lines[index], base, index == lines.length - 1),
      ],
    );
  }

  Widget _line(BuildContext context, String line, TextStyle base, bool last) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      return SizedBox(height: last ? 0 : 9);
    }
    final bullet = RegExp(r'^(?:[-*])\s+').firstMatch(trimmed);
    final content = bullet == null ? trimmed : trimmed.substring(bullet.end);
    final rich = Text.rich(
      TextSpan(children: _spans(content, base)),
      style: base,
    );
    if (bullet == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 3),
        child: rich,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 7, top: 1),
            child: Text('•', style: base),
          ),
          Expanded(child: rich),
        ],
      ),
    );
  }

  List<InlineSpan> _spans(String input, TextStyle base) {
    final output = <InlineSpan>[];
    final matcher = RegExp(r'\*\*([^*]+)\*\*').allMatches(input);
    var cursor = 0;
    for (final match in matcher) {
      if (match.start > cursor) {
        output.add(TextSpan(text: input.substring(cursor, match.start)));
      }
      output.add(
        TextSpan(
          text: match.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ),
      );
      cursor = match.end;
    }
    if (cursor < input.length) {
      output.add(TextSpan(text: input.substring(cursor)));
    }
    return output.isEmpty ? [const TextSpan(text: '')] : output;
  }
}
