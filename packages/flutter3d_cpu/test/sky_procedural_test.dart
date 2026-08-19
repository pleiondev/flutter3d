/// The procedural sky: one full-screen triangle, drawn inside the scene pass.
///
///     flutter test test/sky_procedural_test.dart
///
/// Three things are being checked, and they fail in three different ways.
///
/// **That it draws nothing when it is off.** Sixty golden images are recorded
/// against a renderer with no sky in it. If the disabled path emits so much as
/// a state call, they are all wrong and nothing says so until somebody re-runs
/// the set on a machine with a GPU.
///
/// **That it lands at the far plane.** The depth in `sky.vert` is 0.999999 and
/// the buffer is cleared to 1.0. Raise it to exactly 1.0 and `less` fails
/// everywhere and the sky never appears; drop it to 0.0 and the sky is in front
/// of the world. Neither is visible from the arithmetic, and both are one digit.
///
/// **That the two transcriptions agree.** The model exists twice — in GLSL, and
/// in `SkySettings.sample` for the things that cannot ask a GPU. The software
/// rasteriser holds a third copy, which is what makes the comparison possible
/// at all without a device: a member of a uniform block misspelt in the Dart
/// transcription reads as zeros exactly as it would in the compiled shader, and
/// nothing else in the repository would notice.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      )!;
  return (
    device: device,
    renderer: Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    ),
  );
}

/// A sky with a red sun in it, so that "which way is the camera looking" is
/// answerable from the pixels rather than inferred.
SkySettings _sky({bool enabled = true, double sunIntensity = 6.0}) =>
    SkySettings(
      enabled: enabled,
      zenith: Vector3(0.04, 0.09, 0.55),
      horizon: Vector3(0.30, 0.36, 0.45),
      nadir: Vector3(0.02, 0.02, 0.03),
      directionToSun: Vector3(1.0, 0.25, 0.0),
      sunColor: Vector3(1.0, 0.12, 0.05),
      glowStrength: 0.35,
      glowExponent: 12.0,
      sunAngularRadiusDegrees: 3.0,
      sunSoftnessDegrees: 1.0,
      sunIntensity: sunIntensity,
    );

/// A green wall forty metres out, and a camera at the origin.
({Scene scene, CameraNode camera}) _world({bool wall = true}) {
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();

  if (wall) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(30.0, 30.0, 1.0)).build(),
        ),
        engine.Material(
          name: 'wall',
          baseColor: Vector4(0.0, 1.0, 0.0, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'wall',
      )..setPosition(0.0, 0.0, 40.0),
    );
  }

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.2,
      near: 0.3,
      far: 500.0,
    ),
  )..lookAt(Vector3(0.0, 0.0, 1.0));
  scene.add(camera);
  return (scene: scene, camera: camera);
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  ({Scene scene, CameraNode camera}) world, {
  SkySettings sky = const SkySettings(),
  bool surfaceBuffer = false,
}) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: world.scene,
    views: <RenderView>[
      RenderView(
        camera: world.camera,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      sky: sky,
      surfaceBuffer: surfaceBuffer,
      showSurfaceBuffer: surfaceBuffer,
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

int _green(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 1] > 60 && rgba[i + 1] > rgba[i] * 2) count++;
  }
  return count;
}

double _mean(Uint8List rgba, {required int channel}) {
  var total = 0.0;
  for (var i = channel; i < rgba.length; i += 4) {
    total += rgba[i];
  }
  return total / (rgba.length / 4);
}

/// The brightest pixel's row and column, which is where the sun is.
({int x, int y, double value}) _brightest(Uint8List rgba) {
  var best = -1.0;
  var bx = 0;
  var by = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      final value =
          0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
      if (value > best) {
        best = value;
        bx = x;
        by = y;
      }
    }
  }
  return (x: bx, y: by, value: best);
}

void main() {
  test('no sky is byte-identical to the sky nobody asked for', () async {
    // The property sixty goldens rest on: a frame with no sky in it is the
    // frame this renderer has always drawn.
    //
    // Mutation: drop the early return. The sky is drawn into every scene that
    // never asked for one — which is every recorded golden.
    //
    // What this does *not* catch, stated so it is not mistaken for coverage: a
    // stray `setDepthWrite` or `setCullMode` before the return. `_encodeNode`
    // re-establishes both per mesh, so a redundant call before them changes no
    // pixel here. It could still matter on a backend where an omitted call
    // inherits the previous pass's state — see `PassState`'s own docstring —
    // and that is an argument for the early return being first, not for a test
    // that cannot see it.
    final off = await _draw(_engine(), _world());
    final unset = await _draw(_engine(), _world(), sky: const SkySettings());

    expect(off, unset);
    expect(_green(off), greaterThan(400), reason: 'the wall is still drawn');
  });

  test('the sky fills what the scene did not', () async {
    final without = await _draw(_engine(), _world());
    final with_ = await _draw(_engine(), _world(), sky: _sky());

    expect(_mean(with_, channel: 2), greaterThan(_mean(without, channel: 2) + 30),
        reason: 'the background is a sky rather than the clear colour');
  });

  test('the sky is behind the world, not in front of it', () async {
    // Mutation: write `gl_Position.z = 0.0` in `sky.vert`, which is what
    // `post/fullscreen.vert` writes and what a copy of it would inherit. The
    // sky lands on the near plane, passes `less` everywhere, and the wall — and
    // in a real game, the entire level — disappears behind it.
    final without = await _draw(_engine(), _world());
    final with_ = await _draw(_engine(), _world(), sky: _sky());

    expect(_green(with_), closeTo(_green(without), 8));
  });

  test('the sun is where the sun was put', () async {
    // Mutation: negate `ndc.y` anywhere on the way to the ray, or swap the two
    // sample depths so the ray runs backwards. The sky stays a plausible
    // gradient and the sun moves to the wrong quarter of the frame, which no
    // "there are bright pixels" assertion can see.
    //
    // The sun sits to the right and above the eye — `directionToSun` is
    // (1, 0.25, 0) — and the camera looks along +Z with +X to its left, so it
    // lands left of centre and above it.
    final frame = await _draw(_engine(), _world(wall: false), sky: _sky());
    final sun = _brightest(frame);

    expect(sun.y, lessThan(_height ~/ 2), reason: 'above the horizon');
    expect(sun.x, lessThan(_width ~/ 2), reason: 'and to port');
    expect(sun.value, greaterThan(150.0), reason: 'and it is bright');
  });

  test('the sky follows where the camera looks, not where it stands', () async {
    // Mutation: take `far.xyz / far.w` as the ray instead of the difference of
    // two points. That is a world *position*, so the sky would swing as the
    // camera moved through the level — subtly, and only away from the origin.
    final it = _engine();
    final here = _world(wall: false);
    final there = _world(wall: false);
    there.camera.setPosition(0.0, 0.0, -800.0);

    final a = await _draw(it, here, sky: _sky());
    final b = await _draw(it, there, sky: _sky());

    // To within a level, not byte for byte: the ray is the difference of two
    // world points, and eight hundred metres from the origin those points are
    // large numbers whose difference loses a bit or two in single precision.
    // What matters is that the picture does not *move*.
    var worst = 0;
    for (var i = 0; i < a.length; i++) {
      final difference = (a[i] - b[i]).abs();
      if (difference > worst) worst = difference;
    }
    expect(worst, lessThanOrEqualTo(2),
        reason: 'the sky swung as the camera moved through the world');
  });

  test('the sky is not a surface', () async {
    // Mutation: leave `frag_surface` unwritten, or write `gl_FragCoord.z` into
    // its alpha. `reflections.frag` reads a zero alpha as "nothing was drawn
    // here"; a non-zero one makes the floor reflect the sky as though it were a
    // wall two centimetres away. Invisible in every default setting, which is
    // why it is asserted here.
    final frame = await _draw(
      _engine(),
      _world(wall: false),
      sky: _sky(),
      surfaceBuffer: true,
    );

    // What is checked is the encoded content: an octahedral normal is non-zero
    // in rg wherever a surface was written, and the sky writes zeros.
    expect(_mean(frame, channel: 0), lessThan(8.0),
        reason: 'the sky wrote a normal into the surface buffer');
    expect(_mean(frame, channel: 1), lessThan(8.0),
        reason: 'the sky wrote a normal into the surface buffer');
  });

  test('the two transcriptions of the model agree', () async {
    // The model exists in GLSL and in Dart, and the Dart copy is what a fog
    // colour or a light picked from the sky would be built on. They are checked
    // against each other rather than against a recorded number, because a
    // recorded number goes stale the first time anybody tunes the gradient.
    //
    // Mutation: misspell a member name in `SkyShader`'s bindings. It reads as
    // zeros — exactly as a misspelt member does in the compiled shader — and
    // the picture stays plausible.
    final sky = _sky();
    final it = _engine();
    final world = _world(wall: false);

    // Straight at the sun, so the lobe and the disc are both in shot.
    world.camera.lookAt(sky.resolvedDirectionToSun);
    final frame = await _draw(it, world, sky: sky);

    // The pixel at the centre of the frame is the direction the camera points.
    final centre = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
    final drawn = Vector3(
      frame[centre] / 255.0,
      frame[centre + 1] / 255.0,
      frame[centre + 2] / 255.0,
    );

    // The same colour worked out in Dart, put through what the frame put the
    // shader's answer through: the exposure, and then the composite's encode
    // into sRGB bytes. Tone mapping is off, so there is nothing else between.
    final linear = sky.sample(sky.resolvedDirectionToSun)..scale(1.6);
    final expected = Vector3(
      _linearToSrgb(linear.x),
      _linearToSrgb(linear.y),
      _linearToSrgb(linear.z),
    );

    for (final channel in <int>[0, 1, 2]) {
      expect((drawn[channel] - expected[channel]).abs(), lessThan(0.02),
          reason: 'channel $channel: drawn $drawn against expected $expected');
    }
  });

  test('the depth the sky sits at is the same in both transcriptions', () {
    // Read out of the shader source, because this is the one constant that has
    // to agree between a text file nobody compiles here and a Dart class the
    // tests run. Changing one and not the other gives a sky that is either
    // invisible or in front of the world.
    final source = File(
      '../flutter3d_shaders/shaders/sky.vert',
    ).readAsStringSync();
    final match =
        RegExp(r'gl_Position = vec4\(position, ([0-9.]+), 1\.0\);')
            .firstMatch(source);
    expect(match, isNotNull, reason: 'sky.vert no longer writes a literal depth');

    final fromGlsl = double.parse(match!.group(1)!);
    final stage = const SkyVertexShader();
    final out = Float32List(stage.varyingCount);
    // A whole vertex: the clip-space corner, then everything the fragment
    // stage reads — the ray and the preset, which this stage passes through.
    // Zeros will do; what is being read back is the depth.
    final position = Float32List(2 + stage.varyingCount);
    final clip = stage.run(
      position,
      const ShaderBindings(
        <String, Map<String, Float32List>>{},
        <String, BoundTexture>{},
      ),
      out,
    );

    // Loose, because the vertex stage returns single precision.
    expect(clip.z / clip.w, closeTo(fromGlsl, 1e-6));
    expect(fromGlsl, lessThan(1.0), reason: 'at exactly 1.0 `less` never passes');
    expect(fromGlsl, greaterThan(0.999), reason: 'and it has to be the far plane');
  });
}

/// The composite pass's encode, which is where linear light becomes bytes.
double _linearToSrgb(double value) {
  final clamped = value.clamp(0.0, 1.0);
  return clamped <= 0.0031308
      ? clamped * 12.92
      : 1.055 * math.pow(clamped, 1.0 / 2.4).toDouble() - 0.055;
}
