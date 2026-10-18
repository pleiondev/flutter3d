/// The text a multiview pass links its programs from: every engine vertex
/// stage, declaring the view count `OVR_multiview2` asks for where GLSL ES
/// lets a declaration stand.
library;

import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/src/webgl_shaders.dart' show withViewCount;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every engine vertex stage declares the views after its extensions', () {
    // Mutation: put the layout straight after `#version`, and a stage with
    // an `#extension` of its own has a declaration before it, which GLSL ES
    // refuses to compile.
    for (final MapEntry(key: name, value: source)
        in webGlEngineShaders.vertex.entries) {
      final lines = withViewCount(source, 2).split('\n');
      final version = lines.indexWhere((l) => l.startsWith('#version'));
      final extension = lines.indexOf('#extension GL_OVR_multiview2 : require');
      final layout = lines.indexOf('layout(num_views = 2) in;');
      final lastExtension = lines.lastIndexWhere(
        (l) => l.trimLeft().startsWith('#extension'),
      );
      expect(extension, version + 1, reason: name);
      expect(layout, lastExtension + 1, reason: name);
    }
  });

  test('a stage written for multiview is left as it is', () {
    const own =
        '#version 300 es\n#extension GL_OVR_multiview2 : require\n'
        'layout(num_views = 2) in;\nvoid main() { gl_Position = vec4(0); }\n';
    expect(withViewCount(own, 2), own);
  });
}
