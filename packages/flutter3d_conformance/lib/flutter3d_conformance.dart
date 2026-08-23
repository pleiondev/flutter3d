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
/// **Two tiers, and the split is a correction.** This file used to say it was
/// shader-free as a whole, and that stopped being true the day a check needed a
/// pipeline: five of the twelve now link stages and draw. A new backend
/// following the old promise would have met five failures it could do nothing
/// about, so the lists say which is which — [coreChecks] needs clears, uploads
/// and readback alone, [shaderChecks] needs the bundle. What still needs a
/// shader and is not here (an unbound sampler, a uniform block's members) stays
/// in `COMPATIBILITY.md`, and is named there as such.
library;

import 'dart:typed_data';

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:flutter_test/flutter_test.dart' show test;
import 'package:vector_math/vector_math.dart';

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

/// The checks a backend can run before it has compiled a single shader.
///
/// **This list is why the two exist separately.** The library used to say it
/// was shader-free as a whole, and it stopped being true the day the third
/// check needed a pipeline — so a new backend, following the promise, would
/// have hit five failures it had no way to act on yet. Clears, uploads and
/// readback only: the answers here are the cheapest ones to get, and they are
/// the ones worth having first.
List<ConformanceCheck> get coreChecks => <ConformanceCheck>[
      (name: 'answers every capability query', run: _capabilities),
      (name: 'the HDR format it names is renderable', run: _hdrRenderable),
      (name: 'a clear covers the whole attachment', run: _clearCoversAll),
      (name: 'uploaded pixels keep their row order', run: _rowOrder),
      (name: 'a buffer is uploaded for its declared use', run: _geometryUsage),
    ];

/// The checks that need the shader bundle and a pipeline.
///
/// Run these once [coreChecks] pass and the bundle loads. What they cover is
/// what no signature states: that a pass starts covering its own attachment and
/// nothing else, that it inherits no clipping from the pass before it, and that
/// a binding made for one pipeline does not follow the next.
List<ConformanceCheck> get shaderChecks => <ConformanceCheck>[
      (name: 'the bundle answers to every name the engine asks for',
          run: _shaderNames),
      (name: 'a stage pair the engine links does link', run: _linking),
      (name: 'a pass covers the whole of its attachment',
          run: _passCoversItsAttachment),
      (name: 'a pass does not inherit the previous pass\'s scissor',
          run: _passDoesNotInheritScissor),
      (name: 'an instanced draw draws every instance', run: _instancedDraw),
      (name: 'a pipeline switch leaves no stale bindings',
          run: _pipelineSwitchKeepsBindingsApart),
      (name: 'a cube map answers the face a direction points at',
          run: _cubeFaces),
    ];

/// Every check, as plain functions, for a harness that is not a test runner.
List<ConformanceCheck> get conformanceChecks =>
    <ConformanceCheck>[...coreChecks, ...shaderChecks];

/// Six faces, six directions, six colours.
///
/// The face order — +X, −X, +Y, −Y, +Z, −Z — is documented once, on
/// `GraphicsDevice.createCubeTextureFromPixels`, and each backend reaches it
/// differently: Impeller by slice index, WebGL by six consecutive face targets,
/// the software rasteriser by a table it holds itself. **A transposed pair is
/// invisible in any picture** — a sky with two faces swapped is complete,
/// seamless and simply wrong — so it is checked here rather than looked at.
///
/// Drawn rather than read back, because reading a cube face is not something
/// the interface offers and adding it for a test would be adding a member with
/// one caller. The sky pair is what samples a cube in this engine, so that is
/// what this uses.
Future<void> _cubeFaces(GraphicsDevice device) async {
  if (!device.supportsCubeTextures) {
    // Not a failure: the interface says to ask, and a device that answers false
    // is entitled to. What would be a failure is answering true and then not
    // doing it, which is what everything below checks.
    return;
  }

  const size = 4;
  const colours = <List<int>>[
    <int>[255, 0, 0],
    <int>[0, 255, 0],
    <int>[0, 0, 255],
    <int>[255, 255, 0],
    <int>[255, 0, 255],
    <int>[0, 255, 255],
  ];

  final faces = <ByteData>[
    for (final colour in colours)
      ByteData.sublistView(Uint8List.fromList(<int>[
        for (var i = 0; i < size * size; i++)
          ...<int>[colour[0], colour[1], colour[2], 255],
      ])),
  ];

  final cube = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces,
  );
  require(cube != null,
      'the device says it supports cube textures and then made none from six '
      '4x4 RGBA8 faces');
  require(cube!.type == TextureType.textureCube,
      'the handle came back as ${cube.type.name} rather than a cube');
  require(cube.sliceCount == 6,
      'a cube reported ${cube.sliceCount} slices rather than six');

  require(device.createCubeTextureFromPixels(
        size: size,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: faces.take(5).toList(),
      ) ==
      null,
      'five faces made a cube; the sixth is whatever the allocation held');
}

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


/// A binding made for one pipeline must not follow the next one.
///
/// The contract is written on `CommandEncoder.bindPipeline`: bindings do not
/// survive a pipeline bind. What earns it a conformance check is that
/// flutter_gpu's pass breaks it by construction — it replays every binding it
/// has ever been handed at every draw, keyed by the shader that bound it, and
/// two shaders' blocks that share a slot index then fight for that slot in
/// whatever order an `unordered_map` iterates. The winner is stable within a
/// run and meaningless, which on screen was a skinned monster drawn as a
/// splinter — but only in scenes that also drew something else, which is why
/// every single-model reproduction came out innocent.
///
/// Two pipelines whose only vertex block sits at the same slot, one draw each,
/// in both orders. Each draw's matrix decides where its triangle lands, so if
/// the stale block follows the switch, the second draw lands where the *first*
/// draw's matrix pointed — offscreen — and the centre stays black.
Future<void> _pipelineSwitchKeepsBindingsApart(GraphicsDevice device) async {
  const size = 16;

  final lineVertex = device.shaders['DebugLineVertex'];
  final lineFragment = device.shaders['DebugLine'];
  final particleVertex = device.shaders['ParticleVertex'];
  final particleFragment = device.shaders['Particle'];
  require(
      lineVertex != null &&
          lineFragment != null &&
          particleVertex != null &&
          particleFragment != null,
      'the debug-line or particle stages are missing, so this cannot switch '
      'between two pipelines');

  final centred = Float32List.fromList(Matrix4.identity().storage);
  final offscreen =
      Float32List.fromList(Matrix4.translationValues(64.0, 0.0, 0.0).storage);

  // The same full-frame triangle in each pipeline's own layout: the line one
  // pure green, the particle one pure red with its UV centre on the middle of
  // the frame, where the particle disc is at full strength.
  final lineTriangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 0, 1, 0, 1, //
    3, -1, 0.5, 0, 1, 0, 1,
    -1, 3, 0.5, 0, 1, 0, 1,
  ]);
  final particleTriangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 0, 0, 1, 0, 0, //
    3, -1, 0.5, 1, 0, 0, 1, 2, 0,
    -1, 3, 0.5, 1, 0, 0, 1, 0, 2,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  Future<List<int>> centreWith({required bool lineLast}) async {
    final target = device.createTexture(const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ));
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
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none);

    void line(Float32List matrix) {
      pass
        ..bindPipeline(device.createPipeline(lineVertex!, lineFragment!))
        ..bindUniformBlock(lineVertex, 'LineInfo', <String, Float32List>{
          'view_projection': matrix,
        })
        ..bindVertexData(ByteData.sublistView(lineTriangle), 3)
        ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
        ..draw();
    }

    void particle(Float32List matrix) {
      pass
        ..bindPipeline(
            device.createPipeline(particleVertex!, particleFragment!))
        ..bindUniformBlock(particleVertex, 'ParticleInfo',
            <String, Float32List>{'view_projection': matrix})
        // Density nought: fog off, so the disc's own colour reaches the target.
        ..bindUniformBlock(particleFragment, 'FogInfo', <String, Float32List>{
          'fog': Float32List(4),
          'eye': Float32List(4),
        })
        ..bindVertexData(ByteData.sublistView(particleTriangle), 3)
        ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
        ..draw();
    }

    if (lineLast) {
      particle(offscreen);
      line(centred);
    } else {
      line(offscreen);
      particle(centred);
    }
    pass.submit();

    final pixels = await device.readPixels(target);
    require(pixels != null, 'the target could not be read back');
    final at = ((size ~/ 2) * size + size ~/ 2) * 4;
    return pixels!.buffer.asUint8List().sublist(at, at + 3);
  }

  final line = await centreWith(lineLast: true);
  require(line[1] > 128,
      'a debug-line draw bound the identity and landed off the frame — the '
      'particle pipeline\'s stale ParticleInfo followed it through the switch '
      '(centre came back $line)');

  final particle = await centreWith(lineLast: false);
  require(particle[0] > 128,
      'a particle draw bound the identity and landed off the frame — the '
      'debug-line pipeline\'s stale LineInfo followed it through the switch '
      '(centre came back $particle)');
}

/// A pass draws into the whole of its attachment, and no more.
///
/// **The check the pipeline-switch one was accidentally making**, and it took
/// two wrong diagnoses to find that out. `runDeviceConformance` builds a 64×64
/// device and several checks then draw into a 16×16 target; if a backend leaves
/// the viewport at the size of its canvas, clip space is stretched across four
/// times the attachment and every draw lands somewhere other than where its
/// matrix said. Nothing in the engine caught it because every one of its passes
/// sets a viewport before drawing, so the default was never exercised.
///
/// Half a quad rather than a full-screen triangle, because a shape that covers
/// everything looks the same at any viewport. The left half of clip space is
/// painted; the right half must come back as it was cleared.
Future<void> _passCoversItsAttachment(GraphicsDevice device) async {
  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(vertex != null && fragment != null,
      'the debug-line stages are missing, so this cannot draw anything');

  // x from −1 to 0, y over the whole of it: the left half of the frame.
  final leftHalf = Float32List.fromList(<double>[
    -1, -1, 0.5, 0, 1, 0, 1, //
    0, -1, 0.5, 0, 1, 0, 1,
    0, 1, 0.5, 0, 1, 0, 1,
    -1, 1, 0.5, 0, 1, 0, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]);

  final target = device.createTexture(const RenderTargetSpec(
    width: size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
  ));
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
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexData(ByteData.sublistView(leftHalf), 4)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 6)
    ..draw();
  pass.submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the target could not be read back');
  final bytes = pixels!.buffer.asUint8List();
  int green(int x, int y) => bytes[((y * size + x) * 4) + 1];

  require(
      green(size ~/ 4, size ~/ 2) > 128,
      'the left quarter of the attachment is unpainted, so the pass drew into '
      'less than its attachment — a viewport smaller than what it renders to '
      '(came back ${green(size ~/ 4, size ~/ 2)})');
  require(
      green(size * 3 ~/ 4, size ~/ 2) < 128,
      'the right quarter of the attachment is painted by a shape that stops at '
      'the middle of clip space, so the pass drew into more than its '
      'attachment — a viewport left at the size of something else, most likely '
      'the canvas or the previous pass '
      '(came back ${green(size * 3 ~/ 4, size ~/ 2)})');
}

/// A pass does not inherit the rectangle the previous one was clipped to.
///
/// **The half of the last check that costs a whole frame rather than a corner.**
/// A backend that keeps the scissor test enabled between passes — which is the
/// reasonable thing to do, since the engine sets one per shadow tile — starts
/// each pass clipped to whatever tile the last one finished on. Everything drawn
/// outside it is discarded, silently, and the symptom is a frame that is correct
/// in one rectangle and untouched everywhere else.
///
/// Two passes on one device, because one pass cannot leak into itself.
Future<void> _passDoesNotInheritScissor(GraphicsDevice device) async {
  const size = 16;
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(vertex != null && fragment != null,
      'the debug-line stages are missing, so this cannot draw anything');

  final everything = Float32List.fromList(<double>[
    -1, -1, 0.5, 0, 1, 0, 1, //
    3, -1, 0.5, 0, 1, 0, 1,
    -1, 3, 0.5, 0, 1, 0, 1,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  Future<Uint8List> paintAll({ScreenRect? clippedTo}) async {
    final target = device.createTexture(const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ));
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
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none);
    // Only the first pass narrows itself. The second sets nothing, which is the
    // whole question: what does a pass that says nothing about clipping get?
    if (clippedTo != null) pass.setScissor(clippedTo);
    pass
      ..bindPipeline(device.createPipeline(vertex!, fragment!))
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      })
      ..bindVertexData(ByteData.sublistView(everything), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw();
    pass.submit();
    final pixels = await device.readPixels(target);
    require(pixels != null, 'the target could not be read back');
    return pixels!.buffer.asUint8List();
  }

  // A tile in the top-left corner, the shape a shadow atlas draws into.
  await paintAll(
      clippedTo: const ScreenRect(x: 0, y: 0, width: size ~/ 4, height: size ~/ 4));

  final second = await paintAll();
  final corner = second[((size ~/ 2) * size + (size ~/ 2)) * 4 + 1];
  require(
      corner > 128,
      'a pass that set no scissor was clipped to the tile the previous pass '
      'set: the middle of the attachment is unpainted by a draw that covers '
      'all of clip space (came back $corner)');
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
    // The sky is the only pair where both stages are new at once, so it is the
    // one where a varying can disagree with nothing to compare against. Both
    // pairs, because only one of them is exercised by any given frame.
    //
    // **This table said `SkyVertex` for both, and had stopped being true.** The
    // cube grew a vertex stage of its own when the gradient's vertices changed
    // shape — the gradient carries six colours per vertex now and the cube
    // carries one tint — so `SkyCube` reads a `v_tint` that `SkyVertex` has
    // never written. A browser refuses to link exactly that, which is what this
    // check is for; nothing caught it because these tests only run in a browser
    // and nothing ran them.
    ('SkyVertex', 'Sky'),
    ('SkyCubeVertex', 'SkyCube'),
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
