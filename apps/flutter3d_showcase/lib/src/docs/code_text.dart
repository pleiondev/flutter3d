/// Dart source as coloured text, in one place.
///
/// The Source tab and the code blocks of a guide look the same because they
/// are drawn by the same function, and a change of colour is one edit.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/docs/dart_highlight.dart';

/// The monospace style of code, sized from [context]'s text theme.
TextStyle codeStyle(BuildContext context) => TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: const <String>['Consolas', 'Courier New', 'monospace'],
  fontSize: 13,
  height: 1.45,
  color: Theme.of(context).colorScheme.onSurface,
);

Color _colorOf(TokenKind kind, Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  return switch (kind) {
    TokenKind.comment =>
      dark ? const Color(0xFF7F8C8D) : const Color(0xFF6A737D),
    TokenKind.string =>
      dark ? const Color(0xFF9CCC65) : const Color(0xFF22863A),
    TokenKind.number =>
      dark ? const Color(0xFFFFB74D) : const Color(0xFFB45F06),
    TokenKind.keyword =>
      dark ? const Color(0xFFB39DDB) : const Color(0xFF6F42C1),
    TokenKind.type => dark ? const Color(0xFF4DD0E1) : const Color(0xFF005CC5),
    TokenKind.annotation =>
      dark ? const Color(0xFFFF8A65) : const Color(0xFFD73A49),
    TokenKind.plain => Colors.transparent,
  };
}

/// [code] as a span tree in [base]'s style, coloured by token.
TextSpan highlightedSpan(String code, TextStyle base, Brightness brightness) =>
    TextSpan(
      style: base,
      children: <InlineSpan>[
        for (final Token token in tokenizeDart(code))
          TextSpan(
            text: token.text,
            style: token.kind == TokenKind.plain
                ? null
                : TextStyle(color: _colorOf(token.kind, brightness)),
          ),
      ],
    );
