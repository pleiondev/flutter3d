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

  /// The procedural sky behind the spheres.
  ///
  /// Its own pass, its own stage pair, and the one place in this engine written
  /// against a target it did not match: the sky is fed through vertex
  /// attributes because its uniform blocks do not arrive on Impeller, and a
  /// stale translation once had the browser drawing a sky from the month
  /// before while nothing could see it.
  sky,

  /// Two physical spheres lit by a prefiltered environment and nothing else.
  ///
  /// The direct light is off, so what the picture is *made of* is the cube and
  /// the roughness chain — the whole of image-based lighting in one number. It
  /// exercises what a backend finds hardest to get right quietly: a cube
  /// sampler, a mip chain uploaded level by level, and a level count that is
  /// also the "is there one" flag.
  imageBasedLighting,

  /// A point light a hand's breadth off the wall it lights, in a room.
  ///
  /// **Every other point-shadow fixture here puts the lamp in open space**, a
  /// couple of metres from the two spheres and the floor, where one face of the
  /// cube map covers everything the light reaches and the static atlas holds a
  /// single small caster. A torch in a dungeon is the opposite of all three: it
  /// hangs 0.35 m off a wall, so the surface it lights leaves that face within a
  /// metre of the flame and continues into the four faces around it; the room
  /// around it — floor, ceiling, the wall behind the camera — is static geometry
  /// filling every one of those faces; and what the player is looking at is the
  /// wall the light is *attached to*, at a grazing angle, which is the hardest
  /// thing a shadow lookup is ever asked.
  ///
  /// This is the fixture the crypt needed and did not have. The software
  /// backend cannot stand in for it: point shadows there change nothing in a
  /// scene of this shape — a frame drawn with them and one drawn without come
  /// back pixel for pixel identical — so the only comparison that can see this
  /// is one GPU backend against the other.
  torchNearWall,

  /// The same room with more torches in it than the atlas has rows.
  ///
  /// **Four rows, six lights, and which four get them is decided per frame.**
  /// [torchNearWall] deliberately has one light so that its number answers one
  /// question; this one asks the other. A light that loses its row keeps
  /// lighting and stops casting, and the row it gives up is refilled by a
  /// neighbour — so the two backends have to agree not only about how a face is
  /// sampled but about *which* row each light is reading, on a frame where the
  /// answer has just changed.
  ///
  /// That is the arrangement the crypt is in every time the player walks down
  /// its hall, and no fixture had ever been in it: every other point-shadow
  /// scene here has one light and three spare rows.
  torchesRunningOut,

  /// The plain scene with the composite look turned all the way up.
  ///
  /// Grading, vignette, grain and chromatic aberration are the last thing that
  /// happens to a frame, they happen on every pixel, and they are the newest
  /// thing in the post chain. The grain is a hash of the pixel rather than of
  /// the clock, which is what makes this comparable at all.
  look,
}

({Scene scene, CameraNode camera}) buildParityScene(
  GraphicsDevice device, {
  ParityScene which = ParityScene.plain,
}) {
  // A room rather than two spheres, and so it is built somewhere else entirely
  // rather than by threading conditions through the code below.
  if (which == ParityScene.torchNearWall ||
      which == ParityScene.torchesRunningOut) {
    return _buildTorchNearWall(
      device,
      torches: which == ParityScene.torchesRunningOut ? 6 : 1,
    );
  }

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
        // Physical only where the fixture is about what a surface reflects:
        // Lambert has no response to an environment at all, so an IBL scene
        // shaded that way would compare two flat colours and pass whatever the
        // cube contained.
        lighting: which == ParityScene.imageBasedLighting
            ? LightingModel.pbr
            : LightingModel.lambert,
        metallic: 0.9,
        roughness: 0.25,
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
          lighting: which == ParityScene.imageBasedLighting
              ? LightingModel.pbr
              : LightingModel.lambert,
          // Rougher than the big one, so the two read different levels of the
          // chain. A fixture where every surface is a mirror tests level zero.
          metallic: 1.0,
          roughness: 0.55,
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
      ..shadowIsStatic =
          which == ParityScene.pointShadow ||
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
    // Built and returned at the top of this function, before any of the
    // spheres above exist. Named here rather than left to a default, so that
    // adding a fixture goes on failing to compile until somebody says where
    // its light comes from.
    case ParityScene.torchNearWall:
    case ParityScene.torchesRunningOut:
      break;

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

    case ParityScene.sky:
    case ParityScene.look:
      scene.root.add(
        LightNode(name: 'key', type: LightType.directional)
          ..intensity = 3.5
          ..setPosition(1.5, 3.0, 2.0)
          ..lookAt(Vector3.zero()),
      );

    case ParityScene.imageBasedLighting:
      // **No direct light at all.** Everything in this picture came out of the
      // cube, so a backend that binds no environment draws two silhouettes and
      // the number says so, rather than being carried by a key light.
      final environment = EnvironmentMap.fromSky(device, _paritySky);
      if (environment != null) {
        scene.environment = environment.texture;
        scene.environmentLevels = environment.levels;
      }
      scene.ambientIntensity = 1.0;
  }

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 0.4, 4.2)
    ..lookAt(Vector3(0.0, 0.2, 0.0));
  scene.root.add(camera);

  return (scene: scene, camera: camera);
}

/// A room with a torch on one wall, as [ParityScene.torchNearWall] describes.
///
/// Everything here is chosen against the crypt rather than for a pretty
/// picture: the standoff is the crypt's 0.35 m, the range is its 13 m, the room
/// is the width of its hall, and every surface is a static caster because a
/// dungeon's walls do not move. The one thing deliberately unlike it is that
/// there is a single light — a fixture that also ran out of atlas rows would be
/// asking two questions and reporting one number.
({Scene scene, CameraNode camera}) _buildTorchNearWall(
  GraphicsDevice device, {
  required int torches,
}) {
  final scene = Scene(name: 'parity');
  final stone = Material(
    name: 'stone',
    baseColor: Vector4(0.72, 0.70, 0.66, 1.0),
    lighting: LightingModel.lambert,
    roughness: 0.9,
  );

  void slab(Vector3 size, Vector3 at, String name) {
    scene.root.add(
      MeshNode(
          DeviceMesh.upload(device, CuboidShape(size: size).build()),
          stone,
          name: name,
        )
        ..setPositionFrom(at)
        // Static, like a wall. This is also what puts the room in the *static*
        // atlas, which is the half `pointShadowStaticMap` covers as a picture
        // and nothing covers as a shadow anybody stands in.
        ..shadowIsStatic = true,
    );
  }

  // The lit wall, at z = 0, with the room in front of it.
  slab(Vector3(8.0, 4.0, 0.4), Vector3(0.0, 0.0, -0.2), 'wall');
  slab(Vector3(8.0, 0.4, 10.0), Vector3(0.0, -2.2, 5.0), 'floor');
  slab(Vector3(8.0, 0.4, 10.0), Vector3(0.0, 2.2, 5.0), 'ceiling');
  slab(Vector3(0.4, 4.0, 10.0), Vector3(-4.2, 0.0, 5.0), 'left');
  slab(Vector3(0.4, 4.0, 10.0), Vector3(4.2, 0.0, 5.0), 'right');

  // A pillar off to one side, so the fixture has one shadow whose shape is
  // unmistakable — a comparison of two evenly lit walls agrees about a great
  // deal it cannot see.
  scene.root.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(0.5, 4.0, 0.5)).build(),
        ),
        stone,
        name: 'pillar',
      )
      ..setPosition(-1.6, 0.0, 1.2)
      ..shadowIsStatic = true,
  );

  // The first one is the fixture's subject: on the wall the camera is looking
  // at, at the crypt's own standoff. The rest are down the room, and exist only
  // to ask for rows — which is why they are dimmer and further away, so that
  // what they change is the *allocation* rather than the exposure.
  for (var i = 0; i < torches; i++) {
    scene.root.add(
      LightNode(name: 'torch$i', type: LightType.point)
        ..intensity = i == 0 ? 8.0 : 4.0
        ..range = 13.0
        ..castsShadow = true
        ..setPosition(
          i == 0 ? 0.0 : (i.isEven ? -3.6 : 3.6),
          i == 0 ? 0.6 : 1.2,
          i == 0 ? 0.35 : 1.0 + i.toDouble(),
        ),
    );
  }

  // Looking at the lit wall from inside the room, the way a player walks up to
  // a torch — not at the torch itself, which is the one part of the wall that
  // is bright whatever the shadow lookup does.
  final camera = CameraNode(name: 'eye')
    ..setPosition(0.9, 0.4, 4.0)
    ..lookAt(Vector3(0.0, 0.4, 0.0));
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
  ParityScene.directionalShadow ||
  ParityScene.pointShadow ||
  ParityScene.torchNearWall ||
  ParityScene.torchesRunningOut => const RenderSettings(
    bloom: BloomSettings(enabled: false),
  ),
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
  ParityScene.sky => RenderSettings(
    bloom: const BloomSettings(enabled: false),
    shadows: const ShadowSettings(enabled: false),
    sky: _paritySky,
  ),
  ParityScene.imageBasedLighting => const RenderSettings(
    bloom: BloomSettings(enabled: false),
    shadows: ShadowSettings(enabled: false),
  ),
  // Turned up far past taste: a fixture that applied a look nobody could
  // see would compare two pictures of the same thing and agree.
  ParityScene.look => const RenderSettings(
    bloom: BloomSettings(enabled: false),
    shadows: ShadowSettings(enabled: false),
    look: LookSettings(
      contrast: 1.35,
      saturation: 1.4,
      temperature: 0.25,
      vignette: 0.6,
      grain: 0.08,
      chromaticAberration: 0.004,
    ),
  ),
};

/// The sky both sky fixtures use, and the one the environment is baked from.
///
/// One constant rather than two, because the point of the image-based fixture is
/// that the cube is the sky: two sets of numbers would make a difference between
/// them a difference about the fixtures.
const SkySettings _paritySky = SkySettings(
  enabled: true,
  glowStrength: 0.35,
  sunIntensity: 2.0,
);
