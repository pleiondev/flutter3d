/// The stub list and the engine's list, pinned to each other.
///
/// `builtinCpuShaders` names every unimplemented stage individually rather than
/// filling gaps from `kRequiredShaders`, so that adding a shader to the engine
/// is a failure here instead of a stub appearing by itself. That only works if
/// something checks — otherwise it is a comment describing an intention.
///
/// Both directions, because they catch different mistakes. A name the engine
/// wants and this backend lacks is a renderer that will not start; a name this
/// backend has and the engine does not is a stage kept alive after its shader
/// was deleted, which nothing else would ever mention.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';

void main() {
  test('every name the engine asks for is answered', () {
    final mine = builtinCpuShaders().keys.toSet();
    final missing =
        kRequiredShaders.map((s) => s.name).where((n) => !mine.contains(n));
    expect(missing, isEmpty,
        reason: 'the engine resolves these at Renderer.create and throws on '
            'the first one it cannot find');
  });

  test('nothing is answered that the engine does not ask for', () {
    final wanted = kRequiredShaders.map((s) => s.name).toSet();
    final extra = builtinCpuShaders().keys.where((n) => !wanted.contains(n));
    expect(extra, isEmpty,
        reason: 'a stage outlived the shader it stands in for');
  });

  test('a stage that is not written refuses rather than drawing', () {
    // The property the whole design rests on. A stub that returned black would
    // produce a picture, and a picture is what everything downstream — the
    // goldens, the parity grid, a person looking at the screen — treats as
    // evidence that the pass ran.
    final pbr = builtinCpuShaders()['Pbr']!.fragment!;
    expect(() => pbr.run(Float32List(0), const ShaderBindings({}, {})),
        throwsUnsupportedError);
  });
}
