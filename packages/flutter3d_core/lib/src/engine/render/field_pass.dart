/// A field that evolves by full-screen passes — `H5`.
///
/// **Compute without compute.** Two render targets of one spec, one holding
/// the field as it is and one to write the next step into; [step] draws a
/// kernel over the whole of it, reading the current texel and writing the
/// next, and then the two swap. A kernel is an ordinary fragment stage through
/// `FullscreenVertex`, so it runs wherever the engine runs: a probe update, a
/// simulation grid, a blur that has to happen many times. And a vertex stage
/// can read the field straight back by sampling it, which is how a height
/// field or a particle state reaches geometry without a readback.
///
/// Where `GraphicsDevice.supportsCompute` is true a compute pass does the same
/// thing with less ceremony; this is the path every backend has.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// Two targets, a current one, and the kernels that step between them.
final class FieldPass {
  FieldPass(this.device, this.spec)
    : _current = device.createTexture(spec),
      _next = device.createTexture(spec);

  final GraphicsDevice device;

  /// Both targets' size, format and storage. A field worth stepping is
  /// usually `r16g16b16a16Float` or `r32g32b32a32Float`.
  final RenderTargetSpec spec;

  TextureHandle _current;
  TextureHandle _next;
  final Map<ShaderHandle, PipelineHandle> _pipelines =
      <ShaderHandle, PipelineHandle>{};

  /// How many steps have run.
  int steps = 0;

  /// The field as it stands: the target the last [step] wrote, or the first
  /// one before any step has run. Sample it, draw into it to set a start, or
  /// read it back.
  TextureHandle get current => _current;

  /// One step: [kernel] reads `field_texture` — [current], sampled nearest and
  /// clamped — and writes every texel of the other target, which becomes
  /// [current]. [bind] binds whatever else the kernel declares.
  void step(
    ShaderHandle kernel, {
    void Function(PassEncoder pass)? bind,
    String label = 'field step',
  }) {
    final vertex = device.shaders['FullscreenVertex'];
    if (vertex == null) {
      throw StateError(
        'this device has no FullscreenVertex stage, which every field kernel '
        'is drawn through',
      );
    }
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: _next, loadAction: LoadAction.dontCare),
        ],
        label: label,
      ),
    );
    pass
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..setBlend(null)
      ..bindPipeline(
        _pipelines[kernel] ??= device.createPipeline(vertex, kernel),
      )
      ..bindTexture(
        kernel,
        'field_texture',
        _current,
        sampler: SamplerOptions.nearestClamp,
      );
    bind?.call(pass);
    pass
      ..bindVertexData(ByteData.sublistView(_triangle()), 3)
      ..bindIndexData(
        ByteData.sublistView(Uint16List.fromList(const <int>[0, 1, 2])),
        IndexType.int16,
        3,
      )
      ..draw()
      ..submit();
    final written = _next;
    _next = _current;
    _current = written;
    steps++;
  }

  /// A triangle covering the target, with texture coordinates that put a
  /// texel of [current] under the same texel of the target on every backend
  /// — the pairing `Renderer`'s own full-screen passes use, for the reason
  /// given there: on a backend whose row zero is the bottom, clip `y = +1` is
  /// the last row, and an unflipped pairing turns the field over every step.
  Float32List _triangle() {
    final flip = device.framebufferOrigin == FramebufferOrigin.bottomLeft;
    final top = flip ? 2.0 : -1.0;
    final bottom = flip ? 0.0 : 1.0;
    return Float32List.fromList(<double>[
      -1.0, -1.0, 0.0, bottom, //
      3.0, -1.0, 2.0, bottom, //
      -1.0, 3.0, 0.0, top, //
    ]);
  }

  /// Releases both targets.
  void dispose() {
    device
      ..releaseTexture(_current)
      ..releaseTexture(_next);
  }
}
