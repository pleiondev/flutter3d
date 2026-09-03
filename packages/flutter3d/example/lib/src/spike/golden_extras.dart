import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

/// The particles and the view model a golden draws, built to be repeatable.
///
/// Both plugins were moved out of the renderer onto the plugin seam and
/// neither was covered by a golden, which meant the suite could go green while
/// the two things the refactor touched were broken. These exist to close that,
/// and everything about them is fixed on purpose: a seeded generator, a whole
/// number of fixed steps, no wall clock anywhere.
abstract final class GoldenExtras {
  /// The seed. Any value works; what matters is that it never changes, because
  /// changing it invalidates every recorded reference.
  static const int seed = 20260809;

  /// The example's own loadable shader bundle, as an asset path.
  ///
  /// Written by `tool/build_shaders.sh` from `shaders/`, and loaded through
  /// `GraphicsDevice.loadShaders` by the scene that names it. On Impeller
  /// that is `impellerc` output reparsed from bytes, on WebGL the translated
  /// GLSL ES compiled by the browser, and on the software backend the names
  /// answered by [stripes]' Dart twin in `example_stripes_cpu.dart`.
  static const String exampleShaderBundle = 'assets/shaders/example.f3dshaders';

  /// The look the bundle carries: bands of two colours by normal height.
  ///
  /// Nothing about this is registered anywhere. The string is the whole
  /// binding, resolved against the library handed to the renderer, and the
  /// flags say the stage reads nothing the engine would bind — no FragInfo,
  /// no maps, no parameters — which is what keeps the renderer from binding a
  /// block the compiled stage has no slot for.
  static const LightingModel stripes = LightingModel(
    'Stripes',
    'ExampleStripes',
    usesFragInfo: false,
    usesAlbedoTexture: false,
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );

  /// Simulated seconds before the frame is drawn.
  ///
  /// Chosen so the burst is mid-flight: at zero every particle sits on the
  /// origin in one bright blob, and a golden of a blob would pass whether or
  /// not the affectors ran.
  static const double warmUp = 0.55;

  static const double stepSize = 1.0 / 60.0;

  /// A burst that exercises the parts a still frame can show: spread from the
  /// emitter, drag and gravity bending the paths, colour and size changing
  /// over life.
  static ParticleEffect get effect => ParticleEffect(
    count: 220,
    lifetime: const Range(0.7, 1.4),
    size: const Range(0.06, 0.16),
    color: Vector4(1.0, 0.72, 0.30, 1.0),
    emitter: const SphereEmitter(speed: Range(2.5, 6.0)),
    affectors: <ParticleAffector>[
      const ParticleGravity(-4.0),
      const ParticleDrag(1.2),
      ParticleColorOverLife(
        Vector4(1.0, 0.75, 0.35, 1.0),
        Vector4(0.9, 0.15, 0.05, 1.0),
      ),
      const ParticleFade(),
      const ParticleSizeOverLife(from: 1.0, to: 2.4),
    ],
  );

  /// A system holding one burst, already advanced to [warmUp].
  ///
  /// Stepped rather than solved: the golden has to show what the running
  /// simulation produces, and a closed form would be a second implementation
  /// that could agree with the reference while the real one drifted.
  static ParticleSystem burst() {
    final particles = ParticleSystem(capacity: 512, random: math.Random(seed));
    particles.burst(effect, Vector3(0.0, 0.6, 0.0));
    for (var t = 0.0; t < warmUp - 1e-9; t += stepSize) {
      particles.step(stepSize);
    }
    return particles;
  }

  /// A pool that has been round at least once: particles born, died and had
  /// their slots reused before the frame is drawn.
  ///
  /// **The gap this closes.** Every other particle fixture warms up for less
  /// than one lifetime, so nothing dies and every slot is still held by its
  /// first occupant. That made all of them blind to how the pool recycles —
  /// which went unnoticed until compaction landed and all twenty-seven goldens
  /// came back byte-identical, where the change was expected to reorder the
  /// quads and move the picture. It did not reorder anything, because there
  /// was nothing to reorder.
  ///
  /// Here the lifetime is a fifth of the warm-up, so the pool turns over about
  /// five times. Whatever order the live set ends up in, this is the fixture
  /// that has an opinion about it.
  static ParticleSystem recycled() {
    final particles = ParticleSystem(capacity: 128, random: math.Random(seed));
    final short = ParticleEffect(
      count: 40,
      lifetime: const Range(0.08, 0.12),
      size: const Range(0.06, 0.16),
      color: Vector4(1.0, 0.72, 0.30, 1.0),
      emitter: const SphereEmitter(speed: Range(2.5, 6.0)),
      affectors: <ParticleAffector>[
        const ParticleGravity(-4.0),
        const ParticleDrag(1.2),
        const ParticleFade(),
      ],
    );
    // A burst every few steps, so slots are freed and taken repeatedly rather
    // than once.
    var t = 0.0;
    var since = 0.0;
    while (t < warmUp - 1e-9) {
      if (since <= 0.0) {
        particles.burst(short, Vector3(0.0, 0.6, 0.0));
        since = 0.06;
      }
      particles.step(stepSize);
      since -= stepSize;
      t += stepSize;
    }
    return particles;
  }

  /// One particle, at rest, at a stated place and size.
  ///
  /// The burst has 220 quads overlapping in a field dense enough that "the
  /// nearest bright pixel in the other image is six away" finds a neighbour
  /// rather than the same particle — which is how three attempts to say
  /// whether the two backends draw the same particles produced three numbers
  /// and no answer. One particle has no neighbour to be confused with.
  ///
  /// No affectors, no warm-up and no randomness that matters: whatever the two
  /// backends do with a single camera-facing quad, they do it here where the
  /// difference can only be its position, its size or its brightness.
  static ParticleSystem oneParticle({int count = 1}) {
    final particles = ParticleSystem(capacity: 8, random: math.Random(seed));
    particles.burst(
      ParticleEffect(
        count: count,
        lifetime: const Range(10.0, 10.0),
        size: const Range(0.8, 0.8),
        color: Vector4(1.0, 0.72, 0.30, 1.0),
        emitter: const SphereEmitter(speed: Range(0.0, 0.0)),
      ),
      Vector3(0.0, 0.6, 1.6),
    );
    return particles;
  }

  /// Particles carrying a sprite with a mip chain.
  ///
  /// Spread in depth on purpose. A mip chain only shows itself where the same
  /// texture is seen at different scales, so a row of particles all at one
  /// distance would exercise the chain and prove nothing about it: every one of
  /// them would land on the same level.
  static ParticleSystem texturedParticles() {
    final particles = ParticleSystem(capacity: 16, seed: seed);
    for (var i = 0; i < 4; i++) {
      particles.burst(
        ParticleEffect(
          count: 1,
          lifetime: const Range.exact(10.0),
          size: const Range.exact(0.34),
          color: Vector4(1.0, 0.9, 0.75, 1.0),
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
        ),
        // Receding: each is further away and therefore smaller on screen, so
        // the four between them read four different levels of the chain.
        Vector3(-0.5 + i * 0.36, 0.0, 1.7 - i * 0.55),
      );
    }
    return particles;
  }

  /// The sprite they carry: a fine checkerboard inside a soft disc.
  ///
  /// Two properties, and both are the point. **Checkerboard**, because it is
  /// the pattern a missing mip chain destroys most visibly — sampled below its
  /// Nyquist limit it turns into moire rather than into grey, and moire is
  /// something a reference image can catch. **Soft disc in the alpha**, because
  /// a square sprite would put a hard edge on every particle and the edge, not
  /// the filtering, would then be what the picture is about.
  static TextureHandle particleSprite(GraphicsDevice device) {
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final at = (y * size + x) * 4;
        final on = ((x >> 2) + (y >> 2)).isEven;
        final value = on ? 255 : 60;
        // Distance from the middle, where the corners sit past one.
        final dx = (x + 0.5) / size * 2.0 - 1.0;
        final dy = (y + 0.5) / size * 2.0 - 1.0;
        final radius = math.sqrt(dx * dx + dy * dy);
        final falloff = (1.0 - radius).clamp(0.0, 1.0);
        pixels[at] = value;
        pixels[at + 1] = value;
        pixels[at + 2] = value;
        pixels[at + 3] = (falloff * falloff * 255).round();
      }
    }
    final bytes = ByteData.sublistView(pixels);
    return device.createTextureFromPixels(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: bytes,
      // Asked for, not assumed: a device that answers false samples a
      // hand-built chain as black on some hardware, and a fixture that ignored
      // the answer would record that black.
      mipLevels: device.supportsMipmaps
          ? MipChain.build(bytes, size, size)
          : null,
    )!;
  }

  /// A handful of particles drawn as meshes rather than as billboards.
  ///
  /// Deliberately few, at fixed places, with a lifetime far longer than the
  /// warm-up: what this fixture is for is the *instanced draw*, and a hundred
  /// tumbling embers would put the picture at the mercy of the simulation as
  /// well. Five spheres in a row disagree between backends only if the
  /// instancing does.
  ///
  /// The one scene where Impeller's instanced path is exercised at all — its
  /// conformance suite runs from an application rather than a test, so until
  /// this fixture existed, `drawIndexed(count, instanceCount:)` was a line
  /// nothing had run.
  static ParticleSystem meshParticles() {
    // Calibrated by experiment, and both halves of it were needed.
    //
    // **Size.** `particle-one` puts a quad of size 0.8 at (0, 0.6, 1.6) and it
    // covers a quarter of the frame; the same number given to a sphere covers
    // all of it, because a quad's size is its extent and a mesh particle's is
    // its scale — the sphere has radius one, so the scale *is* the radius. The
    // first attempt at this fixture read as one saturated mass across three
    // screens.
    //
    // **Height.** The second attempt was small enough and drew 382 pixels in
    // the top right corner. Not occlusion, which was the first guess: y = 0.6
    // is already at the top edge of this camera's frame, and `particle-one`
    // only shows there because its quad is large enough to hang down into
    // view. Small spheres at the same height are simply above it.
    //
    // Five spheres, clear of the cube, sizes ascending so a backend that drew
    // instance zero five times over is caught by more than their places.
    final particles = ParticleSystem(capacity: 16, seed: seed);
    for (var i = 0; i < 5; i++) {
      particles.burst(
        ParticleEffect(
          count: 1,
          lifetime: const Range.exact(10.0),
          // Ascending, so the instances are told apart by size as well as by
          // place: a backend that drew instance zero five times over would
          // match on position and still be caught here.
          size: Range.exact(0.06 + i * 0.012),
          color: Vector4(1.0, 0.45 + i * 0.12, 0.20, 1.0),
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
        ),
        Vector3(-0.44 + i * 0.22, 0.0, 1.6),
      );
    }
    return particles;
  }

  /// The shape those particles are copies of.
  ///
  /// A low sphere on purpose. The facing term in `particle_mesh.frag` is what
  /// gives an additive mesh its form, and a coarse sphere shows it: sixteen
  /// segments have visibly different brightnesses where a smooth one would look
  /// like a flat disc and prove nothing.
  static DrawableGeometry meshParticleShape(GraphicsDevice device) =>
      DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 12, rings: 6).build(),
      );

  /// Eight particles in exactly the same place, which is the only thing
  /// `particle-one` leaves untested.
  ///
  /// One quad matches Impeller everywhere. Two hundred and twenty overlapping
  /// ones are five percent apart. Between those two facts sits addition — the
  /// same fragment written eight times into an HDR target, which is half-float
  /// on the hardware backends and float32 here. Stacked at one point with no
  /// spread, nothing else can differ.
  static ParticleSystem stackedParticles() => oneParticle(count: 8);

  /// A floor and a wall whose only light is a lightmap.
  ///
  /// The atlas is arithmetic rather than a bake — a warm pool on the floor's
  /// half, a cool fall-off up the wall's — so the picture depends on nothing
  /// but the lightmapped vertex stage reading the colour as a coordinate,
  /// the sampler decoding RGBM, and the lit model adding the result. The
  /// baker is proved elsewhere, level by level against arithmetic; this is
  /// the shader path, on every backend.
  ///
  /// Drawn with no lights at all, so what is in the frame is the map and the
  /// flat ambient and nothing that could stand in for either.
  static MeshNode lightmappedRoom(GraphicsDevice device) {
    const width = 32;
    const height = 16;
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final at = (y * width + x) * 4;
        final (r, g, b) = x < width ~/ 2
            ? _pool(x, y)
            : _fall(x - width ~/ 2, y);
        _rgbm(pixels, at, r, g, b);
      }
    }
    final atlas = device.createTextureFromPixels(
      width: width,
      height: height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(pixels),
    )!;

    // Two quads in the standard layout, the colour attribute carrying each
    // corner's place in the atlas: the floor on the left half, the wall on
    // the right.
    const half = 1.2;
    const tall = 1.6;
    final vertices = Float32List.fromList(<double>[
      // Floor, wound to face up.
      ..._vertex(-half, 0.0, half, 0.0, 1.0, 0.0, 0.0, 1.0),
      ..._vertex(half, 0.0, half, 0.0, 1.0, 0.0, 0.5, 1.0),
      ..._vertex(half, 0.0, -half, 0.0, 1.0, 0.0, 0.5, 0.0),
      ..._vertex(-half, 0.0, -half, 0.0, 1.0, 0.0, 0.0, 0.0),
      // Wall at the back, wound to face the camera.
      ..._vertex(-half, 0.0, -half, 0.0, 0.0, 1.0, 0.5, 1.0),
      ..._vertex(half, 0.0, -half, 0.0, 0.0, 1.0, 1.0, 1.0),
      ..._vertex(half, tall, -half, 0.0, 0.0, 1.0, 1.0, 0.0),
      ..._vertex(-half, tall, -half, 0.0, 0.0, 1.0, 0.5, 0.0),
    ]);
    final indices = Uint32List.fromList(<int>[
      0,
      1,
      2,
      0,
      2,
      3,
      4,
      5,
      6,
      4,
      6,
      7,
    ]);
    final mesh = DeviceMesh.upload(
      device,
      MeshData(
        layout: VertexLayout.standard,
        vertices: vertices,
        indices: indices,
      ),
    );
    return MeshNode(
      mesh,
      Material(
        name: 'lightmapped room',
        baseColor: Vector4(0.82, 0.80, 0.76, 1.0),
        roughness: 0.9,
      )..lightmap = atlas,
      name: 'lightmapped room',
    )..lightmapped = true;
  }

  /// A checkerboard with its mip chain, sampled with the taps the device
  /// allows up to eight, for the demo's ground plane.
  ///
  /// Sixty-four checks across five hundred and twelve texels, so the base
  /// level has eight texels to a check and the fourth level one — the
  /// chain a trilinear sampler blurs the far checks into and an anisotropic
  /// one does not have to. Sixty-four rather than thirty-two because the
  /// plane it tiles reaches twelve radii from the cube (see
  /// `GoldenScene.groundScale`): a third of a unit to a check puts the
  /// middle distance at a few pixels tall and tens wide, the footprint the
  /// filter is for. Built here rather than loaded, for the reason every
  /// fixture in this file is: a picture that depends on a PNG depends on a
  /// decoder, and the bytes of a checkerboard are arithmetic.
  ///
  /// The sampler is what the bridge hands a level's brushes — trilinear and
  /// repeating, with `min(8, maxAnisotropy)` taps — so the scene pins the
  /// path a corridor floor takes and not a path built for the picture.
  static Material checkerFloor(GraphicsDevice device) {
    const size = 512;
    const checks = 64;
    const texelsPerCheck = size ~/ checks;
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dark = ((x ~/ texelsPerCheck) + (y ~/ texelsPerCheck)).isOdd;
        final at = (y * size + x) * 4;
        // Two greys with a little warmth apart, so a blurred check is a
        // visibly different colour from either rather than a mid grey that
        // could pass for one of them.
        pixels[at] = dark ? 64 : 224;
        pixels[at + 1] = dark ? 60 : 216;
        pixels[at + 2] = dark ? 56 : 200;
        pixels[at + 3] = 255;
      }
    }
    final base = ByteData.sublistView(pixels);
    final texture = device.createTextureFromPixels(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: base,
      mipLevels: MipChain.build(base, size, size),
    )!;
    return Material(name: 'checker floor', roughness: 0.9)
      ..albedo = texture
      ..albedoSampler = SamplerOptions.trilinearRepeat.withAnisotropy(
        math.min(8, device.maxAnisotropy),
      );
  }

  /// A warm pool of light centred on the floor's half of the atlas, three
  /// units of irradiance at the middle and nothing at the rim.
  static (double, double, double) _pool(int x, int y) {
    final dx = (x + 0.5) / 8.0 - 1.0;
    final dy = (y + 0.5) / 8.0 - 1.0;
    final falloff = (1.0 - math.sqrt(dx * dx + dy * dy)).clamp(0.0, 1.0);
    // Under one, so the pool reads as a pool after exposure and the tone
    // curve rather than as a white square: the first recording of this scene
    // at three was a room with no shading in it, which proves nothing.
    final e = 0.9 * falloff * falloff;
    return (e, e * 0.85, e * 0.6);
  }

  /// A cool glow along the bottom of the wall's half, fading up it.
  static (double, double, double) _fall(int x, int y) {
    final e = 0.7 * (1.0 - y / 15.0);
    return (e * 0.6, e * 0.75, e);
  }

  /// RGBM at eight: the multiplier rounds up so the colour rounds down and
  /// nothing clips, the same arithmetic `Lightmap.setIrradiance` uses.
  static void _rgbm(Uint8List out, int at, double r, double g, double b) {
    final brightest = math.max(r, math.max(g, b));
    if (brightest <= 0.0) return;
    final quantised = ((brightest / 8.0).clamp(0.0, 1.0) * 255.0).ceil();
    final m = quantised / 255.0 * 8.0;
    out[at] = (r / m * 255.0).round().clamp(0, 255);
    out[at + 1] = (g / m * 255.0).round().clamp(0, 255);
    out[at + 2] = (b / m * 255.0).round().clamp(0, 255);
    out[at + 3] = quantised;
  }

  /// One standard-layout vertex: position, normal, a texture coordinate
  /// nothing samples, a tangent, and the lightmap coordinate in the colour.
  static List<double> _vertex(
    double x,
    double y,
    double z,
    double nx,
    double ny,
    double nz,
    double lu,
    double lv,
  ) => <double>[
    x,
    y,
    z,
    nx,
    ny,
    nz,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    -1.0,
    lu,
    lv,
    1.0,
    1.0,
  ];

  /// The layer the x-ray scene's cubes are on, beside the default one.
  static const int xrayLayer = 1 << 4;

  /// A wall with a cube behind it and a cube in front, the cubes on
  /// [xrayLayer].
  ///
  /// Placed for a camera looking straight down −Z: the wall stands across
  /// the view, the far cube is behind it with a sliver showing above its
  /// top, and the near cube stands to the left, in front of the wall and —
  /// on screen — over the lower left of the far cube's hidden part. Three
  /// things in one frame: the far cube's silhouette through the wall, its
  /// visible sliver lit rather than flat, and the silhouette notched where
  /// the near cube's lit face is. The third is the stencil's; a depth test
  /// alone paints the far cube's silhouette over the near cube.
  ///
  /// **The overlap is the fixture, not decoration, and it is measured.** In
  /// the recorded 480x360 frame the silhouette occupies roughly x 217..262
  /// and the near cube's face reaches up into it, so the silhouette's rows
  /// below the near cube's top edge are the narrower part of an L. A change
  /// to either position that pulls the two apart leaves the picture agreeing
  /// with every reference while the property it was recorded for is gone —
  /// which is why `xray_frame_test.dart` asserts the same thing in pixels
  /// rather than leaving it to this frame alone.
  static List<MeshNode> xrayRoom(GraphicsDevice device) {
    final wall = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(3.0, 1.2, 0.16)).build(),
      ),
      Material(
        name: 'wall',
        baseColor: Vector4(0.72, 0.70, 0.66, 1.0),
        roughness: 0.85,
      ),
      name: 'wall',
    )..setPosition(0.0, 0.6, 0.0);

    final cube = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
    );
    final behind =
        MeshNode(
            cube,
            Material(
              name: 'far cube',
              baseColor: Vector4(0.30, 0.55, 0.85, 1.0),
              roughness: 0.4,
            ),
            name: 'far cube',
          )
          ..layerMask = 1 | xrayLayer
          ..setPosition(0.0, 0.9, -1.2);
    final inFront =
        MeshNode(
            cube,
            Material(
              name: 'near cube',
              baseColor: Vector4(0.35, 0.75, 0.40, 1.0),
              roughness: 0.4,
            ),
            name: 'near cube',
          )
          ..layerMask = 1 | xrayLayer
          // High enough that its top edge cuts into the far cube's hidden
          // part rather than clearing it below: at 0.4 the two footprints
          // missed each other by two pixels and the frame proved two of the
          // three things it is described as proving.
          ..setPosition(-0.32, 0.7, 0.9);
    return <MeshNode>[wall, behind, inFront];
  }

  /// A stand-in for something held in the player's hands.
  ///
  /// A plain box rather than a weapon, because what is being tested is that
  /// the overlay stage draws at all and is not clipped by the world — and a
  /// box placed deliberately inside the model proves the second half.
  static ViewModelNode viewModel(GraphicsDevice device) {
    final scene = Scene();
    final camera = CameraNode(
      // Narrower than the world camera, the way a real view model is.
      projection: const PerspectiveProjection(fovYRadians: 0.95),
    );
    scene.add(camera);
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(0.34, 0.2, 0.7)).build(),
        ),
        Material(
          name: 'view model',
          baseColor: Vector4(0.85, 0.30, 0.22, 1.0),
          roughness: 0.35,
        ),
        name: 'held',
      )..setPosition(0.32, -0.26, -0.9),
    );
    return ViewModelNode(scene: scene, camera: camera);
  }
}
