/// That "no directional caster" stays no caster on its way into the shader.
///
/// The renderer writes the caster's index into `frame_params.z`, and minus one
/// when the draw was handed no map — the view model's own scene, any
/// contributor's, any frame whose sun drew nothing. GLSL's `int()` truncates
/// towards nought, so `int(-1.0 + 0.5)` is light 0: the first light of every
/// such draw was tested against the stand-in texture. With the map's depth
/// turned round, white reads as an occluder at the light, and the held box of
/// `view-model-point-shadow` went dark wherever the world's sun matrix covered
/// it. The software backend rounds with `floor` and never did.
///
/// A source check because the fault is a property of the GLSL text and only a
/// GPU executes it; the golden is the picture of it, this is the line.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the directional caster index is rounded down, not truncated', () {
    final source = File('shaders/lib/shadow.glsl').readAsStringSync();
    final read = RegExp(
      r'lightIndex\s*!=\s*([^;]*frame_params\.z[^;]*)\)\s*return',
    ).allMatches(source).map((m) => m.group(1)!).toList();
    expect(read, hasLength(1), reason: 'ShadowFactor compares its caster once');
    expect(
      read.single,
      contains('floor('),
      reason:
          'int() truncates towards nought, so the "no caster" minus one would '
          'name light 0',
    );
  });
}
