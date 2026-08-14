/// The behaviour `flutter3d_graphics` requires, as tests a backend runs against
/// itself.
///
/// The interface says what a backend must *have*. Half of what it must *do* is
/// not in any signature: that a clear covers the whole attachment whatever the
/// scissor says, that a rectangle is stated from the top left, that pixels come
/// back rows-from-the-top. Those were prose in `COMPATIBILITY.md`, which is to
/// say they were unenforced — and three of them were broken in the second
/// backend, each producing a correct-looking frame with the wrong content and
/// no error anywhere.
///
/// So they are executable now. A backend calls [runDeviceConformance] from its
/// own test suite and finds out.
///
/// Deliberately shader-free. Every check here works with clears, uploads and
/// readback alone, so a backend can run them before it has a single shader
/// compiled — which is when the answers are cheapest to act on. What needs a
/// shader (an unbound sampler, a uniform block's members) stays in
/// `COMPATIBILITY.md` for now, and is named there as such.
library;

import 'dart:typed_data';

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_test/flutter_test.dart' show test;

/// Builds a device to test. Called fresh for each check, because a backend that
/// leaves state behind should fail on its own account rather than on the
/// previous test's.
typedef DeviceFactory = GraphicsDevice Function({
  required int width,
  required int height,
});

/// Raised by a check the backend did not satisfy.
final class ConformanceFailure implements Exception {
  const ConformanceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fails the check unless [condition].
///
/// **Not `expect`.** `flutter_test`'s matchers throw `OutsideTestException`
/// when there is no test running, and one of the two backends here cannot run
/// tests at all — Flutter GPU needs Impeller, which a headless `flutter test`
/// does not enable, so its harness is an application. Written with `expect`,
/// three of these checks reported a failure that was the harness rather than
/// the backend, and reported it only on the backend that could not use the
/// harness in the first place.
void require(bool condition, String message) {
  if (!condition) throw ConformanceFailure(message);
}

/// One check: a name and something that throws if the backend is wrong.
typedef ConformanceCheck = ({
  String name,
  Future<void> Function(GraphicsDevice device) run,
});

/// Runs every check against [makeDevice] as ordinary tests.
///
/// [backend] names the implementation in the descriptions, so a suite running
/// two of them says which failed.
///
/// **Not available to every backend.** Flutter GPU needs Impeller enabled,
/// which a headless `flutter test` does not provide — the same reason the
/// golden suite drives an application. That backend runs [conformanceChecks]
/// from an app instead; the checks are the same list either way, which is the
/// point of it being a list.
void runDeviceConformance({
  required String backend,
  required DeviceFactory makeDevice,
}) {
  for (final check in conformanceChecks) {
    test('$backend: ${check.name}', () async {
      await check.run(makeDevice(width: 64, height: 64));
    });
  }
}

/// Every check, as plain functions, for a harness that is not a test runner.
List<ConformanceCheck> get conformanceChecks => <ConformanceCheck>[
      (name: 'answers every capability query', run: _capabilities),
      (name: 'the HDR format it names is renderable', run: _hdrRenderable),
      (name: 'a clear covers the whole attachment', run: _clearCoversAll),
      (name: 'uploaded pixels keep their row order', run: _rowOrder),
      (name: 'a buffer is uploaded for its declared use', run: _geometryUsage),
      (name: 'the bundle answers to every name the engine asks for',
          run: _shaderNames),
      (name: 'a stage pair the engine links does link', run: _linking),
      (name: 'an instanced draw draws every instance', run: _instancedDraw),
    ];

/// `draw(instanceCount: n)` puts the geometry down n times.
///
/// Additive and coincident, so the answer is one number: three instances of a
/// quarter-brightness triangle read back at three quarters, and one instance
/// reads back at a quarter. A backend that ignores the count fails on the first
/// number, and one that draws the wrong number of them fails on the ratio.
///
/// **Worth a conformance check rather than a golden**, because the three
/// backends reach instancing three different ways — Impeller passes the count
/// to `drawIndexed`, WebGL2 switches to `drawElementsInstanced` and has to
/// manage attribute divisors that are sticky per location, and the software
/// backend repeats the whole rasterisation. A golden would catch it on one
/// backend and only for scenes that happen to use it.
Future<void> _instancedDraw(GraphicsDevice device) async {
  const size = 16;

  Future<double> brightnessWith(int instances) async {
    final target = device.createTexture(const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ));
    final vertex = device.shaders['DebugLineVertex'];
    final fragment = device.shaders['DebugLine'];
    require(vertex != null && fragment != null,
        'the debug-line stages are missing, so this cannot draw anything');

    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ));
    pass
      ..bindPipeline(device.createPipeline(vertex!, fragment!))
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..setBlend(BlendState.additive)
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      });

    // One triangle covering the target at a quarter brightness. The same shape
    // the depth-write reproduction uses, for the same reason: the arithmetic is
    // checkable by eye.
    final one = Float32List.fromList(<double>[
      -1, -1, 0.5, 0.25, 0, 0, 1, //
      3, -1, 0.5, 0.25, 0, 0, 1,
      -1, 3, 0.5, 0.25, 0, 0, 1,
    ]);
    final indices = Uint16List.fromList(<int>[0, 1, 2]);
    pass
      ..bindVertexData(ByteData.sublistView(one), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw(instanceCount: instances)
      ..submit();

    final pixels = await device.readPixels(target);
    require(pixels != null, 'the target could not be read back');
    return pixels!.buffer.asUint8List()[0] / 255.0;
  }

  final once = await brightnessWith(1);
  require((once - 0.25).abs() < 0.02,
      'a single instance drew $once where a quarter was expected, so this '
      'check cannot say anything about three');

  final thrice = await brightnessWith(3);
  require((thrice - 0.75).abs() < 0.02,
      'three instances drew $thrice where three quarters was expected — the '
      'count was ignored, or applied the wrong number of times');
}


Future<void> _capabilities(GraphicsDevice device) async {
  // Not assertions about the values — a backend is entitled to any of them.
  // Assertions that asking works at all, because the engine branches on these
  // and a throw here is a frame that never starts.
  // Reading them is the assertion: the engine branches on each, and a throw
  // here is a frame that never starts. The values themselves are the backend's
  // business.
  device.depthRange;
  device.framebufferOrigin;
  device.supportsWireframe;
  device.supportsOffscreenMsaa;
  require(device.preferredSampleCount >= 1,
      'preferredSampleCount is ${device.preferredSampleCount}; one means no '
      'multisampling and less than one means nothing');
  require(device.defaultColorFormat != TextureFormat.unknown,
      'defaultColorFormat is unknown, so the frame has nowhere to go');
}

Future<void> _hdrRenderable(GraphicsDevice device) async {
  // The engine renders linear HDR and tone maps at the end, so it opens a pass
  // against whatever this getter names. A format that is samplable but not
  // renderable — RGBA16F on WebGL2 before EXT_color_buffer_float is asked for —
  // makes every framebuffer incomplete, every draw silently discarded, and a
  // frame of transparent black with every counter reporting success.
  final target = device.createTexture(RenderTargetSpec(
    width: 32,
    height: 32,
    format: device.hdrColorFormat,
  ));
  device
      .beginRenderPass(RenderPassDescriptor(colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4(1.0, 1.0, 1.0, 1.0),
        ),
      ]))
      .submit();
}

Future<void> _clearCoversAll(GraphicsDevice device) async {
  // The rule the point-light atlas depends on: it clears once and then draws
  // tile by tile, so a clear bounded by the scissor would leave most of it as
  // allocated. GL does not give this for free — clearBufferfv honours
  // SCISSOR_TEST — and the symptom was one cleared row out of four and shadows
  // that read as absent.
  const size = 64;
  final target = device.createTexture(const RenderTargetSpec(
    width: size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
  ));

  device
      .beginRenderPass(RenderPassDescriptor(colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
        ),
      ]))
    // A scissor over one corner, set before submitting. A backend that clears
    // through it fails here and only here.
    ..setScissor(const ScreenRect(x: 0, y: 0, width: 8, height: 8))
    ..submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the cleared target could not be read back');
  final bytes = pixels!.buffer.asUint8List();

  // Every pixel, not a sample: a partial clear leaves a rectangle, and a spot
  // check placed inside it would pass.
  var wrong = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    if (bytes[i + 1] < 200) wrong++;
  }
  require(
      wrong == 0,
      '$wrong of ${bytes.length ~/ 4} pixels are not the clear colour — the '
      'clear was bounded by something, and the contract says it covers the '
      'whole attachment');
}

Future<void> _rowOrder(GraphicsDevice device) async {
  // Row zero is the top. A backend measuring from the bottom has to flip on the
  // way in, the way out, or both — and a caller cannot tell which way round it
  // was handed pixels, so a golden compared against a mirrored frame fails as
  // though rendering broke.
  const width = 4;
  const height = 4;
  final source = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      // Red increases downwards, so a mirrored readback is unmistakable.
      source[i] = y * 60;
      source[i + 3] = 255;
    }
  }

  final texture = device.createTextureFromPixels(
    width: width,
    height: height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(source),
  );
  require(texture != null, 'the device made no texture from four by four '
      'RGBA8 pixels');

  final read = await device.readPixels(texture!);
  require(read != null, 'the uploaded texture could not be read back');
  final bytes = read!.buffer.asUint8List();

  require(
      bytes[0] == source[0],
      'row zero came back as ${bytes[0]} where ${source[0]} was written: the '
      'image is upside down');
  final last = (height - 1) * width * 4;
  require(bytes[last] == source[last],
      'the last row disagrees, which a flip would also cause');
}

Future<void> _geometryUsage(GraphicsDevice device) async {
  // Not a hint. WebGL binds a buffer to its target for life, so one uploaded as
  // vertices can never be bound as indices — the attempt is an
  // INVALID_OPERATION, the draw is dropped, and the frame comes back the clear
  // colour with nothing logged.
  final bytes = ByteData(64);
  device.uploadGeometry(bytes, GeometryUsage.vertices);
  device.uploadGeometry(bytes, GeometryUsage.indices);
}

Future<void> _shaderNames(GraphicsDevice device) async {
  // The one requirement GraphicsDevice cannot express. The engine asks a
  // library for entry points by name, so a backend written from the interface
  // alone compiles, runs, and draws nothing — and the frame that comes back is
  // empty for a reason nothing reports.
  //
  // Named individually rather than counted: "seventeen of twenty-three" sends
  // somebody to diff two lists by hand.
  final missing = <String>[];
  for (final shader in kRequiredShaders) {
    if (device.shaders[shader.name] == null) missing.add(shader.name);
  }
  require(
      missing.isEmpty,
      'the bundle has no ${missing.join(', ')}. Every backend ships its own '
      'bundle and every bundle answers to the same names; see '
      'package:flutter3d_shaders.');
}

Future<void> _linking(GraphicsDevice device) async {
  // Compiling is not linking. A stage pair can hold two shaders that each
  // compile and refuse to link together, and the one that fails is not the one
  // that looks wrong.
  //
  // Measured rather than assumed, because the obvious version of this claim is
  // false: a fragment input that is *declared and never read* links fine even
  // with no matching vertex output — the compiler drops it. What does fail is
  // an input the fragment stage actually reads and the vertex stage never
  // writes. Checked by making exactly that mutation and watching this fail.
  //
  // The pairs the engine actually builds, not every combination: a bundle is
  // allowed to hold stages that are never linked together.
  const pairs = <(String, String)>[
    ('MeshVertex', 'Pbr'),
    ('MeshVertex', 'ShadowDepth'),
    ('MeshVertex', 'ShadowDistance'),
    ('MeshSkinnedVertex', 'Pbr'),
    ('ShadowTileResetVertex', 'ShadowTileReset'),
    ('FullscreenVertex', 'Composite'),
    ('DebugLineVertex', 'DebugLine'),
    ('ParticleVertex', 'Particle'),
  ];

  for (final (vertexName, fragmentName) in pairs) {
    final vertex = device.shaders[vertexName];
    final fragment = device.shaders[fragmentName];
    require(vertex != null && fragment != null,
        '$vertexName + $fragmentName: one of the stages is missing');
    try {
      device.createPipeline(vertex!, fragment!);
    } catch (error) {
      throw ConformanceFailure('$vertexName + $fragmentName does not link: '
          '$error');
    }
  }
}
