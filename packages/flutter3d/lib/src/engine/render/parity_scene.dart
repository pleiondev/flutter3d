/// One scene, defined once, so two backends can be asked to draw the same
/// thing.
///
/// Not engine functionality — a fixture. It lives in the engine because that is
/// the only place an application on one backend and a test on another can both reach, and
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

/// Builds the shared comparison scene on `device`.
///
/// Returns the scene and the camera to view it through; the caller supplies the
/// renderer, because that is the part that differs.
/// Which of the engine's features a comparison scene exercises.
///
/// One fixture per feature rather than one that does everything, because a
/// grid that disagrees tells you *that* the backends differ and a fixture tells
/// you *where*. Shadows and bloom in the same picture would have made "the
/// atlas is wrong" and "the glow is wrong" the same number.
enum ParityScene {
  /// Two lit spheres. Shading, geometry, uniforms — the smallest thing that can
  /// disagree.
  plain,

  /// The same, with a directional shadow onto a floor. The shadow pass, its
  /// map, and the lighting shader's lookup into it.
  directionalShadow,

  /// A point light with the cube atlas, which is six faces per light and the
  /// most machinery of anything here.
  pointShadow,

  /// A bright sphere and bloom on, which is the post chain: threshold,
  /// downsample, upsample, composite.
  bloom,

  /// The cube atlas itself, composited instead of the lit image.
  ///
  /// Splits the point-shadow question in two. If the atlas matches and the lit
  /// scene does not, the pass is right and the lookup is wrong; if the atlas
  /// does not match, the pass never got that far. One number cannot say which,
  /// and guessing between them is how an afternoon goes.
  pointShadowMap,

  /// The **static** half of the cube atlas, composited instead of the lit image.
  ///
  /// **The split above was one short, and that cost six attempts.** There are
  /// two cube atlases — the movers, redrawn every frame, and the things that
  /// never move, drawn once at load — and `PointShadowDistance` samples both and
  /// keeps the nearer occluder. `pointShadowMap` shows only the first. So a
  /// backend whose *static* atlas was empty passed the atlas fixture, failed the
  /// lit one, and every explanation offered for it was about the lookup, which
  /// was fine.
  ///
  /// That is exactly what was happening in WebGL, and the note on the skipped
  /// fixture said "the atlas is right" for six attempts on the strength of a
  /// number that was measuring the other atlas.
  pointShadowStaticMap,
}

({Scene scene, CameraNode camera}) buildParityScene(
  GraphicsDevice device, {
  ParityScene which = ParityScene.plain,
}) {
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
    )
      ..setPosition(1.1, 1.0, 0.4)
      // **One static caster, so that the second cube atlas is not empty.**
      // A point light has two — the movers, redrawn every frame, and the things
      // that never move, drawn once — and `PointShadowDistance` samples both.
      // Every fixture here left both spheres dynamic, so the static atlas was
      // white in every run on every backend, and the half of the lookup that
      // reads it was covered by nothing at all.
      //
      // The large sphere stays dynamic on purpose: a fixture where one atlas is
      // empty tests one atlas, whichever one it is.
      ..shadowIsStatic = which == ParityScene.pointShadow ||
          which == ParityScene.pointShadowMap ||
          which == ParityScene.pointShadowStaticMap,
  );

  // A floor for anything that casts, and only then: an unlit scene with a
  // floor compares differently for a reason that has nothing to do with the
  // feature under test.
  if (which == ParityScene.directionalShadow ||
      which == ParityScene.pointShadow ||
      which == ParityScene.pointShadowMap ||
      which == ParityScene.pointShadowStaticMap) {
    scene.root.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const PlaneShape(width: 8.0, depth: 8.0).build(),
        ),
        Material(
          name: 'floor',
          baseColor: Vector4(0.55, 0.55, 0.6, 1.0),
          lighting: LightingModel.lambert,
        ),
        name: 'floor',
      )..setPosition(0.0, -1.4, 0.0),
    );
  }

  switch (which) {
    case ParityScene.plain:
    case ParityScene.bloom:
      // Above and to the right, so the lit side of both spheres is up.
      scene.root.add(
        LightNode(name: 'key', type: LightType.directional)
          ..intensity = 3.5
          ..setPosition(1.5, 3.0, 2.0)
          ..lookAt(Vector3.zero()),
      );

    case ParityScene.directionalShadow:
      // Oblique rather than overhead. A sun straight above drops the shadow
      // under the sphere, where the sphere covers it — still cast, never seen,
      // and a comparison that cannot see it cannot disagree about it.
      scene.root.add(
        LightNode(name: 'sun', type: LightType.directional)
          ..intensity = 4.0
          ..castsShadow = true
          ..setPosition(2.5, 3.0, 1.5)
          ..lookAt(Vector3.zero()),
      );

    case ParityScene.pointShadow:
    case ParityScene.pointShadowMap:
    case ParityScene.pointShadowStaticMap:
      scene.root.add(
        LightNode(name: 'lamp', type: LightType.point)
          ..intensity = 12.0
          ..range = 12.0
          ..castsShadow = true
          ..setPosition(2.2, 2.6, 1.8),
      );
  }

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 0.4, 4.2)
    ..lookAt(Vector3(0.0, 0.2, 0.0));
  scene.root.add(camera);

  return (scene: scene, camera: camera);
}

/// The settings each fixture is drawn with.
///
/// Everything not under test is switched off, so a scene that disagrees says
/// which feature disagreed. A fixture with shadows *and* bloom would report one
/// number for two questions.
RenderSettings paritySettingsFor(ParityScene which) => switch (which) {
      ParityScene.plain => const RenderSettings(
          bloom: BloomSettings(enabled: false),
          shadows: ShadowSettings(enabled: false),
        ),
      ParityScene.directionalShadow || ParityScene.pointShadow =>
        const RenderSettings(bloom: BloomSettings(enabled: false)),
      ParityScene.bloom => const RenderSettings(
          shadows: ShadowSettings(enabled: false),
        ),
      // The atlas on screen instead of the picture. Exposure and tone mapping
      // are forced off by this path in the compositor, so the comparison is of
      // the stored distances themselves.
      ParityScene.pointShadowMap => const RenderSettings(
          bloom: BloomSettings(enabled: false),
          showShadowMap: true,
        ),
      // The other cube atlas, which nothing had ever looked at. See the note
      // on `ParityScene.pointShadowStaticMap`.
      ParityScene.pointShadowStaticMap => const RenderSettings(
          bloom: BloomSettings(enabled: false),
          showStaticShadowMap: true,
        ),
    };

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
