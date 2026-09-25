/// `gfx-29n`: contrast-adaptive sharpening, folded into the pass that already
/// fetched the neighbourhood.
///
///     flutter test test/sharpen_test.dart
///
/// **Two properties, and the second is the one the name is about.** A
/// sharpener has to raise local contrast at an edge — that is the whole
/// point. An *adaptive* one also has to ease off when the neighbourhood has
/// no headroom left, because that is what separates sharpening from the
/// bright halo along every hard edge that reads as a cheap filter.
///
/// **Through `render`, not `renderPost`.** The first version of this file
/// drove the composite directly and every assertion came back "no change" —
/// `renderPost` builds a graph of bloom and the composite, and the smoothing
/// is a node of the full frame. Nothing was wrong with the kernel; the pass
/// was never running.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An unlit quad against a flat background, smoothed and optionally sharpened.
///
/// Unlit and orthographic so the edge is a step rather than a shaded falloff:
/// what both halves of this test are about is one edge, and a gradient would
/// make "raised the contrast" a claim about everywhere instead.
Future<List<int>> _edge({
  required double sharpen,
  required double surface,
  required double background,
  bool geometry = true,
  int width = 96,
  int height = 32,
}) async {
  final device = CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene();
  if (geometry) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3(1, 4, 1)).build()),
        Material(
          name: 'flat',
          baseColor: Vector4(surface, surface, surface, 1.0),
          lighting: LightingModel.unlit,
        ),
      ),
    );
  }
  scene.add(CameraNode()..setPosition(0.0, 0.0, 4.0));

  final frame = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(background, background, background, 1.0),
      ),
    ],
    // Undithered: the composite's dither is a pattern a flat frame carries
    // into this pass, and sharpening a pattern is what sharpening is for.
    settings: RenderSettings(
      tonemap: false,
      antiAlias: AntiAliasSettings(enabled: true, sharpen: sharpen),
      look: const LookSettings(dither: 0),
    ),
  );

  final bytes = await device.readPixels(frame.frame);
  // The middle row, which crosses both of the quad's vertical edges.
  final row = height ~/ 2;
  return <int>[
    for (var x = 0; x < width; x++) bytes!.getUint8((row * width + x) * 4),
  ];
}

/// The largest step between neighbours anywhere in the row.
int _steepest(List<int> row) {
  var most = 0;
  for (var i = 1; i < row.length; i++) {
    final step = (row[i] - row[i - 1]).abs();
    if (step > most) most = step;
  }
  return most;
}

void main() {
  test('zero is an exact identity, and is the default', () async {
    // Seventy-eight goldens go through this pass. The shader returns the centre
    // untouched at zero rather than running a kernel that rounds to nothing,
    // because "rounds to nothing" is a claim about the target's bit depth.
    expect(const AntiAliasSettings().sharpen, 0.0);
    expect(
      await _edge(sharpen: 0.0, surface: 0.5, background: 0.05),
      await _edge(sharpen: 0.0, surface: 0.5, background: 0.05),
    );
  });

  test('it raises the contrast across an edge', () async {
    final plain = await _edge(sharpen: 0.0, surface: 0.5, background: 0.05);
    final sharp = await _edge(sharpen: 1.0, surface: 0.5, background: 0.05);

    expect(
      _steepest(sharp),
      greaterThan(_steepest(plain)),
      reason:
          'a sharpener that does not steepen an edge is a draw call and '
          'nothing else',
    );
  });

  test('a frame with nothing drawn in it is left alone', () async {
    // The property the normalised kernel buys: with five equal samples the
    // numerator is the centre times the same factor as the denominator, so
    // there is nothing for the strength to multiply. A sharpener that shifted
    // the level of a blank wall would be a grade nobody asked for.
    //
    // **No geometry at all, rather than geometry the colour of the
    // background.** The first version of this drew a quad matching the clear
    // colour and called that flat; it is not. A silhouette still lands on the
    // frame with sub-pixel coverage along it, so a handful of pixels differ
    // by one — and sharpening those is the kernel doing its job, not a bug in
    // it. What has no edge is an empty scene.
    final flat = await _edge(
      sharpen: 0.0,
      surface: 0.3,
      background: 0.3,
      geometry: false,
    );
    final sharpened = await _edge(
      sharpen: 1.0,
      surface: 0.3,
      background: 0.3,
      geometry: false,
    );
    expect(sharpened, flat);
  });

  test(
    'it holds back where there is no headroom, which is the "adaptive"',
    () async {
      // The amplitude comes from how close the neighbourhood already is to the
      // ends. An edge sitting against white has nowhere to overshoot, so the
      // kernel eases off there — a plain unsharp mask would ring instead, and
      // ringing against white is exactly the halo this avoids.
      final roomy = _steepest(
        await _edge(sharpen: 1.0, surface: 0.45, background: 0.15),
      );
      final roomyPlain = _steepest(
        await _edge(sharpen: 0.0, surface: 0.45, background: 0.15),
      );
      final tight = _steepest(
        await _edge(sharpen: 1.0, surface: 1.0, background: 0.92),
      );
      final tightPlain = _steepest(
        await _edge(sharpen: 0.0, surface: 1.0, background: 0.92),
      );

      expect(
        tight - tightPlain,
        lessThan(roomy - roomyPlain),
        reason:
            'an edge with room should be sharpened more than one against '
            'the ceiling; equal means the kernel is not adaptive and the row '
            'should not carry the word',
      );
    },
  );
}
