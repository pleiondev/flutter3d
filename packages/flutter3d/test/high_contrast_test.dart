/// `N9`: the high-contrast look, and the colours a game rings its nodes in.
///
///     flutter test test/high_contrast_test.dart
///
/// **Off is the claim that matters first.** The look is an accommodation, so a
/// game leaves its marks on its monsters for the player who turns the look on
/// — and every other player has to get the frame they always got, bytes and
/// passes alike. Then each of the look's parts is held to the one thing that
/// separates it from a filter over the picture: the flattening removes detail
/// *within* a surface and stops at its edges, the outline appears where
/// geometry steps, the ring is drawn round a marked node and not round one
/// hidden behind something, and the pass that costs draws runs only when
/// there is something for it to draw.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// Orange, Okabe and Ito's — what a game might ring its monsters in.
final Vector3 _orange = Vector3(0.902, 0.624, 0.0);

/// Every part of the look switched off but the one a test is about: tone
/// left alone, colour kept, no flattening, no lines, no rings.
const HighContrastSettings _neutral = HighContrastSettings(
  enabled: true,
  flatten: 0.0,
  contrast: 1.0,
  saturation: 1.0,
  outlineWidth: 0.0,
  roleWidth: 0.0,
  roleFill: 0.0,
);

/// A floor painted in stripes, a box standing on it and a ball beside it,
/// under a sun. The stripes are the texture detail the flattening is for, and
/// they run across a surface with no geometry in them at all.
({Scene scene, MeshNode box, MeshNode ball}) _stage(GraphicsDevice device) {
  const size = 32;
  final stripes = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final light = x.isEven ? 220 : 40;
      final at = (y * size + x) * 4;
      stripes
        ..[at] = light
        ..[at + 1] = light
        ..[at + 2] = light
        ..[at + 3] = 255;
    }
  }
  final texture = device.createTextureFromPixels(
    width: size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(stripes),
  )!;
  final floor = MeshNode(
    DeviceMesh.upload(device, const PlaneShape(width: 6.0, depth: 6.0).build()),
    Material(
      name: 'floor',
      lighting: LightingModel.lambert,
      albedo: texture,
      albedoSampler: SamplerOptions.nearestClamp,
    ),
    name: 'floor',
  );
  final box = MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.8)).build()),
    Material(name: 'box', baseColor: Vector4(0.8, 0.15, 0.1, 1.0)),
    name: 'box',
  )..setPosition(-0.6, 0.4, 0.0);
  final ball = MeshNode(
    DeviceMesh.upload(device, SphereShape(radius: 0.4).build()),
    Material(name: 'ball', baseColor: Vector4(0.15, 0.3, 0.85, 1.0)),
    name: 'ball',
  )..setPosition(0.7, 0.4, 0.2);
  final scene = Scene()
    ..ambientIntensity = 0.3
    ..add(floor)
    ..add(box)
    ..add(ball)
    ..add(
      LightNode(intensity: 3.0)
        ..setLocalForward(Vector3(-0.5, -1.0, -0.4).normalized()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 2.2, 3.4)
        ..lookAt(Vector3(0.0, 0.3, 0.0)),
    );
  return (scene: scene, box: box, ball: ball);
}

/// The frame [settings] draws of the stage, after [arrange] has had its way
/// with the box and the ball, and what the renderer said about it.
Future<({Uint8List pixels, List<String> passes})> _frame(
  HighContrastSettings settings, {
  void Function(MeshNode box, MeshNode ball)? arrange,
  int maxColorAttachments = 3,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    maxColorAttachments: maxColorAttachments,
  );
  final renderer = Renderer.create(device: device);
  final stage = _stage(device);
  arrange?.call(stage.box, stage.ball);
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: stage.scene,
    views: <RenderView>[
      RenderView(
        camera: stage.scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      highContrast: settings,
      // Off, so what the look does is what comes out: a glow taken from the
      // picture before the look would be a halo round nothing it drew.
      bloom: const BloomSettings(enabled: false),
    ),
  );
  final bytes = await device.readPixels(result.frame);
  return (
    pixels: Uint8List.fromList(<int>[
      for (var i = 0; i < _width * _height * 4; i++) bytes!.getUint8(i),
    ]),
    passes: <String>[for (final pass in result.passes) pass.name],
  );
}

/// How many pixels of [pixels] are [colour] to within a step or two of
/// rounding.
int _countOf(Uint8List pixels, Vector3 colour) {
  final r = (colour.x * 255).round();
  final g = (colour.y * 255).round();
  final b = (colour.z * 255).round();
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if ((pixels[i] - r).abs() <= 2 &&
        (pixels[i + 1] - g).abs() <= 2 &&
        (pixels[i + 2] - b).abs() <= 2) {
      count++;
    }
  }
  return count;
}

/// The spread of the red channel over the bottom eight rows, which are floor
/// and nothing else: how much stripe there is left.
double _floorSpread(Uint8List pixels) {
  final values = <int>[
    for (var y = _height - 8; y < _height; y++)
      for (var x = 0; x < _width; x++) pixels[(y * _width + x) * 4],
  ];
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      values.length;
  return math.sqrt(variance);
}

/// Whether the pixel at [i] is the box's: red well above both others.
bool _isBox(Uint8List pixels, int i) =>
    pixels[i] > 90 &&
    pixels[i] > pixels[i + 1] * 2 &&
    pixels[i] > pixels[i + 2] * 2;

void main() {
  group('off', () {
    test('is the default, on the settings and on the frame', () {
      expect(const HighContrastSettings().enabled, isFalse);
      expect(const RenderSettings().highContrast.enabled, isFalse);
      // A copy that changes something else keeps it off.
      expect(
        const HighContrastSettings().copyWith(contrast: 3.0).enabled,
        isFalse,
      );
    });

    test('a marked node draws the frame it always drew, through the passes it '
        'always ran', () async {
      // **The promise that lets a game leave its marks set.** The look off,
      // nothing reads a node's colour: not one pass more, not one byte
      // different. Mutation: make the look's node active whatever the
      // setting, and the pass list grows and the picture moves. (The mask
      // node asks for the look too, but that check only spares a walk of the
      // meshes: a mask nobody reads is culled by the graph either way, which
      // a mutation of it showed.)
      final plain = await _frame(const HighContrastSettings());
      final marked = await _frame(
        const HighContrastSettings(),
        arrange: (box, ball) => box.outlineColor = _orange,
      );

      expect(marked.pixels, plain.pixels);
      expect(marked.passes, plain.passes);
      expect(marked.passes, isNot(contains('high contrast')));
      expect(marked.passes, isNot(contains('outline mask')));
    });
  });

  group('the passes run when there is something to do', () {
    test('the look alone, with nothing marked', () async {
      // Mutation: drop the scan for a marked mesh from the mask node's
      // `isActive`, and the mask is drawn — a target and a pass — for a frame
      // with nothing in it to ring.
      final frame = await _frame(const HighContrastSettings(enabled: true));
      expect(frame.passes, contains('high contrast'));
      expect(frame.passes, isNot(contains('outline mask')));
    });

    test('and the mask too, once something is marked', () async {
      final frame = await _frame(
        const HighContrastSettings(enabled: true),
        arrange: (box, ball) => ball.outlineColor = _orange,
      );
      expect(
        frame.passes.indexOf('outline mask'),
        lessThan(frame.passes.indexOf('high contrast')),
      );
    });

    test('on a device with one attachment the look still runs', () async {
      // `gfx-50n`: no surface buffer, so no mask — a hard reader of the
      // buffer is culled — and no edges; but the look reads both optionally,
      // so it runs and still drains the colour, which needs neither.
      final frame = await _frame(
        _neutral.copyWith(saturation: 0.0),
        arrange: (box, ball) => box.outlineColor = _orange,
        maxColorAttachments: 1,
      );
      expect(frame.passes, contains('high contrast'));
      expect(frame.passes, isNot(contains('outline mask')));
      for (var i = 0; i < frame.pixels.length; i += 4) {
        expect(
          (frame.pixels[i] - frame.pixels[i + 1]).abs(),
          lessThanOrEqualTo(1),
        );
      }
    });
  });

  group('the look', () {
    test('drained of colour, the world is grey', () async {
      // Mutation: skip the mix toward the luma in the CPU shader, and the red
      // box and the blue ball keep their colours.
      final plain = await _frame(_neutral);
      final grey = await _frame(_neutral.copyWith(saturation: 0.0));

      var coloured = 0;
      for (var i = 0; i < plain.pixels.length; i += 4) {
        if ((plain.pixels[i] - plain.pixels[i + 2]).abs() > 20) coloured++;
        expect(
          (grey.pixels[i] - grey.pixels[i + 1]).abs(),
          lessThanOrEqualTo(1),
        );
        expect(
          (grey.pixels[i] - grey.pixels[i + 2]).abs(),
          lessThanOrEqualTo(1),
        );
      }
      expect(coloured, greaterThan(100), reason: 'there was colour to drain');
    });

    test('the flattening takes the stripes off the floor', () async {
      // Mutation: never count a tap as the same surface, and the mean is the
      // centre alone — the stripes come back whole.
      final striped = await _frame(_neutral);
      final flat = await _frame(_neutral.copyWith(flatten: 1.0));
      expect(
        _floorSpread(flat.pixels),
        lessThan(_floorSpread(striped.pixels) * 0.7),
      );
    });

    test('and stops at the edges of a surface', () async {
      // **What the geometric guide is for.** The box's three faces are each
      // lit evenly, so averaging within a face leaves it as it was; averaging
      // across a face's edge mixes in the next face, the floor's stripes or
      // the background, and moves the box's pixels nearest its outline.
      // Mutation: count every drawn tap as the same surface, ignoring depth
      // and normal, and this fails by tens of steps along every edge.
      final plain = await _frame(_neutral);
      final flat = await _frame(_neutral.copyWith(flatten: 1.0));
      var box = 0;
      for (var i = 0; i < plain.pixels.length; i += 4) {
        if (!_isBox(plain.pixels, i)) continue;
        box++;
        for (var c = 0; c < 3; c++) {
          expect(
            (flat.pixels[i + c] - plain.pixels[i + c]).abs(),
            lessThanOrEqualTo(6),
            reason: 'pixel ${i ~/ 4} of the box took colour from elsewhere',
          );
        }
      }
      expect(box, greaterThan(100), reason: 'the box is in the frame');
    });

    test('the outline is drawn where the geometry steps', () async {
      // Magenta, a colour nothing in the stage is, so every pixel of it is a
      // line. Mutation: never call an edge in the CPU shader and there are
      // none; take the reach to nought and there are none either, which is
      // what keeps the first half of this from passing on anything magenta.
      final magenta = Vector3(1.0, 0.0, 1.0);
      final lined = await _frame(
        _neutral.copyWith(outlineWidth: 1.0, outlineColor: magenta),
      );
      final none = await _frame(_neutral.copyWith(outlineColor: magenta));
      expect(_countOf(lined.pixels, magenta), greaterThan(40));
      expect(_countOf(none.pixels, magenta), 0);
    });

    test('a receding floor is not an edge, however its depth steps', () async {
      // **Why the depth test is a bend and not a step.** Seen at a slant, the
      // floor's depth moves by a couple of percent between neighbouring
      // pixels here, and by more the flatter the view — so at a threshold of
      // one percent a test of the step calls the whole floor an edge, while
      // a plane's second difference stays near nought. Mutation: threshold
      // the larger step instead of the bend, and the bottom rows fill with
      // line. Mutation: keep the vertical pair on the frame's last row, where
      // its lower tap is clamped back onto the centre, and that row is one
      // line — which this test found before the shaders knew about it.
      final magenta = Vector3(1.0, 0.0, 1.0);
      final lined = await _frame(
        _neutral.copyWith(
          outlineWidth: 1.0,
          outlineColor: magenta,
          depthEdge: 0.01,
        ),
      );
      final floor = Uint8List.sublistView(
        lined.pixels,
        (_height - 8) * _width * 4,
      );
      expect(_countOf(lined.pixels, magenta), greaterThan(40));
      expect(_countOf(floor, magenta), 0, reason: 'a plane bends nowhere');
    });
  });

  group('the rings', () {
    test('a marked node is ringed in its colour, outside it', () async {
      final ringed = await _frame(
        _neutral.copyWith(roleWidth: 2.0),
        arrange: (box, ball) => box.outlineColor = _orange,
      );
      final unmarked = await _frame(_neutral.copyWith(roleWidth: 2.0));
      expect(_countOf(ringed.pixels, _orange), greaterThan(40));
      expect(_countOf(unmarked.pixels, _orange), 0);
    });

    test('and filled with a share of it, which can be nought', () async {
      // Mutation: lay the fill on at full regardless of `roleFill`, and the
      // box turns orange at nought.
      final bare = await _frame(
        _neutral,
        arrange: (box, ball) => box.outlineColor = _orange,
      );
      final plain = await _frame(_neutral);
      expect(bare.pixels, plain.pixels);

      final filled = await _frame(
        _neutral.copyWith(roleFill: 1.0),
        arrange: (box, ball) => box.outlineColor = _orange,
      );
      expect(_countOf(filled.pixels, _orange), greaterThan(100));
    });

    test('a marked node the scene hides gets no ring', () async {
      // **A ring through a wall is a sensor, not an accommodation.** The ball
      // is put under the floor, where the floor hides all of it: the mask
      // pass runs, draws it, and the surface buffer drops every fragment.
      // Mutation: take the depth test out of the CPU mask stage and the ring
      // is drawn on the floor round where the ball is.
      final hidden = await _frame(
        _neutral.copyWith(roleWidth: 2.0, roleFill: 1.0),
        arrange: (box, ball) => ball
          ..outlineColor = _orange
          ..setPosition(0.7, -1.0, 0.2),
      );
      expect(hidden.passes, contains('outline mask'));
      expect(_countOf(hidden.pixels, _orange), 0);
    });
  });
}
