/// One scene, defined once, so two backends can be asked to draw the same
/// thing.
///
/// Not engine functionality — a fixture. It lives in the engine because that is
/// the only place both an Impeller application and a WebGL test can reach, and
/// because the alternative is writing the scene twice. Written twice, any
/// difference in the pictures is as likely to be a difference in the two
/// transcriptions as a difference in the backends, and the comparison stops
/// meaning anything.
///
/// Everything here is fixed on purpose. No bounds-based framing, no asset
/// loading, no time: the camera sits where it is told, the sphere is tessellated
/// to a stated count, and the light has a stated direction. A scene that
/// computes any of that from its contents would drift between the two runs for
/// reasons neither backend is responsible for.
///
/// **Deliberately asymmetric.** The small sphere sits up and to the right of the
/// large one, and the light comes from above. A symmetric scene compares equal
/// to its own mirror image, which is exactly the bug that got past three pixel
/// assertions and needed a person to notice — the frame was upside down and
/// every number agreed with it.
library;

import 'package:vector_math/vector_math.dart';

import '../../../flutter3d.dart';

/// Builds the shared comparison scene on [device].
///
/// Returns the scene and the camera to view it through; the caller supplies the
/// renderer, because that is the part that differs.
({Scene scene, CameraNode camera}) buildParityScene(GraphicsDevice device) {
  final scene = Scene(name: 'parity');

  final big = DeviceMesh.upload(
    device,
    const SphereShape(radius: 1.0, segments: 32, rings: 16).build(),
  );
  scene.root.add(
    MeshNode(
      big,
      Material(
        name: 'big',
        baseColor: Vector4(0.85, 0.25, 0.15, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'big',
    ),
  );

  // Up and to the right, and small enough that its silhouette is unmistakable.
  // This is the asymmetry: a mirrored frame puts it down and to the left, and a
  // comparison that only looked at brightness would not care.
  final small = DeviceMesh.upload(
    device,
    const SphereShape(radius: 0.35, segments: 16, rings: 8).build(),
  );
  scene.root.add(
    MeshNode(
      small,
      Material(
        name: 'small',
        baseColor: Vector4(0.2, 0.5, 0.9, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'small',
    )..setPosition(1.1, 1.0, 0.4),
  );

  // Above and slightly to the right, so the lit side of both spheres is up.
  scene.root.add(
    LightNode(name: 'key', type: LightType.directional)
      ..intensity = 3.5
      ..setPosition(1.5, 3.0, 2.0)
      ..lookAt(Vector3.zero()),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 0.4, 4.2)
    ..lookAt(Vector3(0.0, 0.2, 0.0));
  scene.root.add(camera);

  return (scene: scene, camera: camera);
}

/// The settings both runs use. Bloom off, so the comparison is of shading
/// rather than of a post chain the two backends implement with different
/// numbers of passes.
const RenderSettings kParitySettings =
    RenderSettings(bloom: BloomSettings(enabled: false), shadows: ShadowSettings(enabled: false));

/// Width and height both runs render at.
const int kParityWidth = 256;
const int kParityHeight = 192;

/// Cells across and down in the comparison grid.
const int kParityGrid = 16;

/// Average luminance per cell, 0..255, row-major from the top.
///
/// A grid rather than the pixels themselves, because the question is whether
/// the two backends draw the *same picture*, not whether they produce identical
/// bytes — they will not, and demanding it would mean choosing a tolerance for
/// every pixel instead of one for the comparison. Two different GPUs, two
/// shader compilers and two rounding regimes disagree in the last bits
/// everywhere and agree completely about where the spheres are.
///
/// Averaging is what makes that distinction: it survives a fraction of a bit
/// per pixel and does not survive a shape in the wrong place, a light from the
/// wrong side, or a mirrored frame.
List<int> parityGrid(List<int> rgba, int width, int height) {
  final cells = List<int>.filled(kParityGrid * kParityGrid, 0);
  final cellW = width / kParityGrid;
  final cellH = height / kParityGrid;
  for (var cy = 0; cy < kParityGrid; cy++) {
    for (var cx = 0; cx < kParityGrid; cx++) {
      final x0 = (cx * cellW).floor();
      final x1 = ((cx + 1) * cellW).ceil().clamp(0, width);
      final y0 = (cy * cellH).floor();
      final y1 = ((cy + 1) * cellH).ceil().clamp(0, height);
      var total = 0;
      var count = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final i = (y * width + x) * 4;
          // Rec. 601 luma, integer weights. The exact coefficients matter less
          // than both sides using the same ones, which is why this is here and
          // not written out twice.
          total += (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
          count++;
        }
      }
      cells[cy * kParityGrid + cx] = count == 0 ? 0 : total ~/ count;
    }
  }
  return cells;
}
