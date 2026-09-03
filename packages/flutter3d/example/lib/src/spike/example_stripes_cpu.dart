/// `shaders/example_stripes.frag`, in Dart, for the software backend.
///
/// The bundle the `loaded-shader` golden loads carries compiled sections for
/// the two hardware backends and nothing the software rasteriser could run —
/// it compiles nothing, and answers a bundle's names with the Dart stages the
/// device already has. So the example hands this to `CpuDevice.shaders` under
/// the same name, and the bundle loads there too.
///
/// **Transcribed from the GLSL, not invented**, the rule every stage in
/// `flutter3d_cpu` follows: the arithmetic is the fragment shader's line for
/// line, so the software golden lands beside the hardware one rather than
/// drawing a different set of stripes.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:vector_math/vector_math.dart';

final class ExampleStripesShader implements CpuFragmentShader {
  const ExampleStripesShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final n = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2])
      ..normalize();
    // `fract(n.y * 3.0 + 0.25)`, then `step(0.5, …)`.
    final t = n.y * 3.0 + 0.25;
    final band = (t - t.floorToDouble()) >= 0.5 ? 1.0 : 0.0;
    final warm = Vector3(0.90, 0.45, 0.08);
    final cool = Vector3(0.10, 0.30, 0.85);
    final lit = 0.55 + 0.45 * n.y.clamp(0.0, 1.0);
    final colour = (warm + (cool - warm).scaled(band)).scaled(lit);
    // `WriteSurface(colour, 1.0)`: fogged, and the surface geometry written
    // beside it, fully rough.
    return writeLit(
      c,
      v,
      b,
      colour: colour,
      alpha: 1.0,
      normal: n,
      roughness: 1.0,
    );
  }
}
