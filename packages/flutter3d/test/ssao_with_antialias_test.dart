/// `gfx-08n`: occlusion and smooth edges in the same frame, and what the
/// pass costs.
///
///     flutter test test/ssao_with_antialias_test.dart
///
/// **The mutual exclusion this row was waiting on is gone, and this is the
/// check that says so.** `gfx-08n`'s own text names the reason SSAO was never
/// turned on by default: "it was exactly `gfx-04n` that blocked turning it
/// on". A game had to choose between shadows in the corners and smooth edges,
/// because the surface buffer SSAO reads turns MSAA off for the whole scene.
/// `gfx-04n` built FXAA into the pass graph — anti-aliasing that runs *after*
/// the surface buffer rather than instead of it — and the pair has never been
/// drawn together since.
///
/// So: an inside corner, occlusion on, anti-aliasing on, and three questions
/// answered with numbers rather than with a golden. Does the corner still
/// darken with FXAA in the graph? Do the edges still smooth with SSAO in it?
/// And what does the occlusion pass cost, which is the second half of this
/// row's own acceptance.
///
/// **The frame itself is `gfx-08n`'s remaining half and is not here.** Its
/// acceptance names a recorded frame, and flipping the default moves every
/// golden that has a crease in it — which is every golden with a model in it
/// — on four backends, three of which this machine cannot record. What that
/// costs is `gfx-07n`'s sentence for the same situation: recaptured in one
/// commit.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 96;

typedef _Shot = ({Uint8List pixels, int ssaoMicros, bool hadAntialias});

/// An inside corner of a flat grey room, lit by ambient alone — the shape
/// `ambient-occlusion-corner` uses, and for the same reason: with no light
/// and no texture, every difference in the picture is the occlusion.
Future<_Shot> _corner({
  required bool occlusion,
  required bool antialias,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();

  final wall = Material(name: 'wall', baseColor: Vector4(0.8, 0.8, 0.8, 1.0));
  // Two walls and a floor meeting at the origin: three inside edges, which is
  // what an occlusion term has to find.
  for (final (Vector3 size, Vector3 at) in <(Vector3, Vector3)>[
    (Vector3(2.8, 0.1, 2.8), Vector3(0.0, -1.4, 0.0)),
    (Vector3(0.1, 2.8, 2.8), Vector3(-1.4, 0.0, 0.0)),
    (Vector3(2.8, 2.8, 0.1), Vector3(0.0, 0.0, -1.4)),
  ]) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: size).build()),
        wall,
        name: 'wall',
      )..setPosition(at.x, at.y, at.z),
    );
  }

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: CameraNode()
          ..setPosition(1.8, 1.5, 1.8)
          ..lookAt(Vector3(-0.6, -0.6, -0.6)),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      shadows: const ShadowSettings(enabled: false),
      // The scene's own radius rather than the default: the room is 2.8
      // metres across and the default half metre reaches a third as far,
      // which is `ambient-occlusion-corner`'s own note and the same reason.
      ambientOcclusion: AmbientOcclusionSettings(
        enabled: occlusion,
        radius: 0.9,
        strength: 1.0,
      ),
      antiAlias: AntiAliasSettings(enabled: antialias),
    ),
  );

  final ssao = frame.passes.where((FramePass p) => p.name == 'ssao');
  return (
    pixels: (await device.readPixels(frame.frame))!.buffer.asUint8List(),
    ssaoMicros: ssao.isEmpty ? 0 : ssao.first.micros,
    hadAntialias: frame.passes.any(
      (FramePass p) => p.name == 'antialias' && p.active,
    ),
  );
}

/// The mean brightness of a band — the corner darkens, the open wall does
/// not.
double _mean(Uint8List rgba, {required int fromRow, required int toRow}) {
  var total = 0;
  var count = 0;
  for (var y = fromRow; y < toRow; y++) {
    for (var x = 0; x < _width; x++) {
      total += rgba[(y * _width + x) * 4 + 1];
      count++;
    }
  }
  return total / count;
}

void main() {
  test('the corner still darkens with anti-aliasing in the graph', () async {
    // The half of the mutual exclusion that was SSAO's. If the surface buffer
    // and the anti-aliasing pass still fought, this is where it would show:
    // the occlusion would be gone, not merely softer.
    final plain = await _corner(occlusion: false, antialias: true);
    final occluded = await _corner(occlusion: true, antialias: true);

    expect(
      _mean(occluded.pixels, fromRow: 0, toRow: _height),
      lessThan(_mean(plain.pixels, fromRow: 0, toRow: _height)),
      reason: 'occlusion has to darken the room it is turned on in',
    );
  });

  test('the edges still smooth with occlusion in the graph', () async {
    // And the half that was anti-aliasing's. `gfx-04n` put FXAA after the
    // surface buffer rather than instead of it, and this is that sentence as
    // a check: the pass runs, and it runs in a frame that also has SSAO.
    final both = await _corner(occlusion: true, antialias: true);
    expect(both.hadAntialias, isTrue);

    final aliased = await _corner(occlusion: true, antialias: false);
    expect(
      both.pixels,
      isNot(aliased.pixels),
      reason: 'a pass that changes nothing is a pass that did not run',
    );
  });

  test('the pass cost is named', () async {
    // The second half of this row's own acceptance. The number is the
    // software rasteriser's rather than a GPU's — `gfx-01n`'s profiler is
    // honest about which machine it is on — so what is asserted is that the
    // pass is measured and that turning it off costs nothing, which is the
    // part that is a property of the graph rather than of the backend.
    final on = await _corner(occlusion: true, antialias: true);
    final off = await _corner(occlusion: false, antialias: true);

    expect(on.ssaoMicros, greaterThan(0), reason: 'the pass was timed');
    expect(
      off.ssaoMicros,
      0,
      reason: 'an occlusion nobody asked for costs nothing',
    );
  });
}
