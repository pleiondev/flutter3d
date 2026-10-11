/// The engine's GLSL light loops skip a plugin's light type (codes from 16
/// up, CONTRACTS "Light codes") before any branch that would read its row
/// as one of the engine's: `SampleLight` before the panel's branch, and
/// `ContributorLight` in its attenuation. The software backend's
/// transcriptions are held to the same skip by behaviour, in its own
/// `plugin_light_code_test.dart`.
///
///     dart test test/plugin_light_code_test.dart
///
/// Mutation: move the skip in `surface.glsl` below the `type > 2.5` branch,
/// or drop it from `contributor_lights.glsl`, and the order test fails.
library;

import 'package:flutter3d_shaders/compile.dart' show loadShaders;
import 'package:test/test.dart';

/// The body of the GLSL function [name] in [source], up to the next
/// function's doc comment.
String _function(String source, String name) {
  final start = source.indexOf(RegExp('\\b$name\\(int index'));
  expect(start, isNonNegative, reason: '$name is defined');
  final end = source.indexOf('\n///', start);
  return source.substring(start, end < 0 ? source.length : end);
}

void main() {
  final sources = loadShaders().sources;

  test('SampleLight leaves on a plugin code before the panel branch', () {
    final body = _function(sources['lib/surface.glsl']!, 'SampleLight');
    final skip = body.indexOf('if (type > 15.5)');
    expect(skip, isNonNegative);
    expect(skip, lessThan(body.indexOf('if (type > 2.5)')));
  });

  test('ContributorLight gives a plugin code no attenuation', () {
    final body = _function(
      sources['lib/contributor_lights.glsl']!,
      'ContributorLight',
    );
    expect(body, contains('float attenuation = type > 15.5'));
  });
}
