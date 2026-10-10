/// A box projects a picture onto the geometry inside it, and the picture is
/// lit as the surface was — `P3`.
///
///     dart test test/decal_test.dart
///
/// Most of these read the lit scene before the post chain — the target the
/// decals are painted into — through a node registered behind them, and set
/// it against the same frame with the decal hidden. Where a decal is opaque
/// the two differ by the change of albedo alone, so the ratio of the two is
/// a number the test can state rather than a picture it has to look at.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

/// Reads the scene target as the decals and the glass left it.
final class _SceneProbe extends RenderNode {
  _SceneProbe(this._device);

  final CpuDevice _device;
  Float32List? last;

  @override
  String get name => 'scene probe';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {
    final scene = frame.resources.texture(FrameResourceIds.hdrColor);
    last = _device.readHdrPixels(scene);
    frame.resources.provide(FrameResourceIds.hdrColor, scene);
  }
}

typedef _Stage = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
  LightNode sun,
  _SceneProbe probe,
});

/// sRGB 0.5, which the lit models take as a linear albedo of 0.214.
final Vector4 _grey = Vector4(0.5, 0.5, 0.5, 1.0);

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// A floor eight metres square with its top at y = 0, a sun, and a camera
/// [from] somewhere above it looking at the middle.
_Stage _stage({RenderMaterial? floor, Vector3? from, Vector3? up}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPositionFrom(from ?? Vector3(0.0, 6.0, 0.0))
    ..lookAt(Vector3.zero(), up: up ?? Vector3(0.0, 0.0, -1.0));
  final sun = LightNode(intensity: 2.0 * Photometric.legacyUnit)
    ..setPosition(0.4, 5.0, 0.3)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(8.0, 0.2, 8.0)).build(),
        ),
        floor ??
            RenderMaterial(
              name: 'floor',
              lighting: LightingModel.lambert,
              baseColor: _fromSrgb(_grey),
            ),
      )..setPosition(0.0, -0.1, 0.0),
    )
    ..add(sun)
    ..add(camera);
  scene.ambientIntensity = 0.3 * Photometric.legacyUnit;
  final probe = _SceneProbe(device);
  final renderer = Renderer.create(device: device)..renderSteps.addNode(probe);
  return (
    device: device,
    renderer: renderer,
    scene: scene,
    camera: camera,
    sun: sun,
    probe: probe,
  );
}

const RenderSettings _on = RenderSettings(
  bloom: BloomSettings(enabled: false),
  decals: DecalSettings(enabled: true),
);

/// A decal three metres square on the floor, painted [color], which is sRGB
/// as the floor's [_grey] is.
///
/// Mutation: `color.toLinearColor()`, which takes the sRGB channels as linear,
/// and the unlit and emissive tests read 0.2 where `_linear(0.2)` is due.
DecalNode _decal(Vector4 color, {int order = 0}) => DecalNode(
  color: LinearColor.fromSrgb(color.x, color.y, color.z, color.w),
  order: order,
)..setScale(3.0, 1.0, 3.0);

FrameResult _render(_Stage it, [RenderSettings settings = _on]) =>
    it.renderer.render(
      width: _size,
      height: _size,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: settings,
    );

Float32List _scene(_Stage it, [RenderSettings settings = _on]) {
  _render(it, settings);
  return Float32List.fromList(it.probe.last!);
}

/// The texel at [x], [y] of a frame read back as floats.
Vector4 _at(Float32List frame, int x, int y) {
  final i = (y * _size + x) * 4;
  return Vector4(frame[i], frame[i + 1], frame[i + 2], frame[i + 3]);
}

/// Every pixel whose colour [a] and [b] disagree on.
List<int> _changed(Float32List a, Float32List b) => <int>[
  for (var p = 0; p < _size * _size; p++)
    if (<int>[0, 1, 2].any((c) => (a[p * 4 + c] - b[p * 4 + c]).abs() > 1e-4))
      p,
];

void main() {
  test('off by default: the pass does not run and the frame is the same', () {
    final it = _stage();
    final without = _scene(it, const RenderSettings());
    it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0)));
    final result = _render(it, const RenderSettings());
    // Mutation: an `isActive` that forgets the setting runs the pass on every
    // frame with a decal in it.
    expect(result.passes.map((p) => p.name), isNot(contains('decals')));
    expect(_changed(it.probe.last!, without), isEmpty);
  });

  test('on, with every decal hidden, nothing splits and nothing moves', () {
    final it = _stage();
    final without = _scene(it);
    it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0))..isVisible = false);
    final result = _render(it);
    final ran = result.passes.map((p) => p.name);
    // Mutation: asking `decals.isNotEmpty` instead of whether any is visible
    // splits the scene and gives up multisampling for a decal nobody sees.
    expect(ran, isNot(contains('decals')));
    expect(ran, isNot(contains('transparent')));
    expect(_changed(it.probe.last!, without), isEmpty);
  });

  test('the colour is swapped under the light the surface was lit by', () {
    final it = _stage();
    // A blocker over the middle of the decal, high enough to stay out of the
    // box, under a sun low enough that its shadow falls clear of it: part of
    // the painted floor the camera sees is in that shadow.
    it.sun.setPosition(3.0, 4.0, 0.0);
    it.sun.lookAt(Vector3.zero());
    it.scene.add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3(1.5, 0.2, 4.0)).build(),
        ),
        RenderMaterial(
          lighting: LightingModel.lambert,
          baseColor: _fromSrgb(_grey),
        ),
      )..setPosition(0.0, 1.2, 0.0),
    );
    final decal = it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0)));
    decal.isVisible = false;
    final reference = _scene(it);
    decal.isVisible = true;
    final painted = _scene(it);

    final inside = _changed(painted, reference);
    expect(inside.length, greaterThan(40));
    final albedo = _linear(0.5);
    final lights = <double>[];
    for (final p in inside) {
      final was = reference[p * 4];
      lights.add(was);
      // Red is a whole albedo over the floor's 0.214: the light that reached
      // the point, times the new colour. Green and blue are nought.
      //
      // Mutation: laying the decal's colour over the lit picture rather than
      // swapping it under the light makes the ratio a function of how lit the
      // point is, and the shadowed half fails.
      expect(painted[p * 4] / was, closeTo(1.0 / albedo, 0.02 / albedo));
      expect(painted[p * 4 + 1], closeTo(0.0, 1e-3));
      expect(painted[p * 4 + 2], closeTo(0.0, 1e-3));
    }
    // And the region really did hold two lights, so the line above was asked
    // of both of them.
    expect(lights.reduce(math.max) / lights.reduce(math.min), greaterThan(2.0));
  });

  test('a surface turned away from the box is left alone', () {
    // A blue wall standing inside the box; the camera sees its side.
    final it = _stage(from: Vector3(5.0, 4.0, 3.0), up: Vector3(0.0, 1.0, 0.0));
    it.scene.add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3(0.2, 2.0, 2.0)).build(),
        ),
        RenderMaterial(
          lighting: LightingModel.lambert,
          baseColor: LinearColor.fromSrgb(0.1, 0.2, 0.9, 1.0),
        ),
      )..setPosition(0.5, 1.0, 0.0),
    );
    final decal = it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0)));
    decal.isVisible = false;
    final reference = _scene(it);
    decal.isVisible = true;

    bool onWall(int p) => reference[p * 4 + 2] > reference[p * 4] * 2.0;
    final defaultLimit = _changed(_scene(it), reference);
    expect(defaultLimit, isNotEmpty);
    // Mutation: dropping the angle test paints the wall's side, which faces
    // across the box rather than up it.
    expect(defaultLimit.where(onWall), isEmpty);

    decal.angleLimit = math.pi;
    final anyAngle = _changed(_scene(it), reference);
    expect(anyAngle.where(onWall), isNotEmpty);
  });

  test('higher order is painted over lower, then attachment order', () {
    final it = _stage();
    final red = it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0), order: 1));
    final green = it.scene.add(_decal(Vector4(0.0, 1.0, 0.0, 1.0)));
    Vector4 center() => _at(_scene(it), _size ~/ 2, _size ~/ 2);

    // Mutation: drawing in attachment order ignores `order`, and green, the
    // later, wins.
    expect(center().x, greaterThan(0.1));
    expect(center().y, closeTo(0.0, 1e-3));

    red.order = 0;
    // Equal now, so the later attached is on top.
    expect(center().y, greaterThan(0.1));
    expect(center().x, closeTo(0.0, 1e-3));

    green.order = -1;
    expect(center().x, greaterThan(0.1));
  });

  test('more decals and pictures than one draw holds are all painted', () {
    final it = _stage();
    const colors = <LinearColor>[
      LinearColor(1.0, 0.0, 0.0),
      LinearColor(0.0, 1.0, 0.0),
      LinearColor(0.0, 0.0, 1.0),
      LinearColor(1.0, 1.0, 0.0),
      LinearColor(0.0, 1.0, 1.0),
    ];
    final pictures = <TextureHandle>[
      for (final color in colors) SolidColorTexture(color).upload(it.device),
    ];
    // Twenty-five, a metre apart: two draws' worth of decals, and five
    // pictures where a draw binds four.
    final decals = <DecalNode>[
      for (var row = 0; row < 5; row++)
        for (var column = 0; column < 5; column++)
          it.scene.add(
            DecalNode(texture: pictures[(row + column) % 5])
              ..setScale(0.6, 1.0, 0.6)
              ..setPosition(column - 2.0, 0.0, row - 2.0),
          ),
    ];
    final painted = _scene(it);
    for (final decal in decals) {
      decal.isVisible = false;
    }
    final reference = _scene(it);

    final project = it.camera.viewProjection(1.0);
    for (var i = 0; i < decals.length; i++) {
      final at = decals[i].readWorldPosition();
      final clip = project.transform(Vector4(at.x, at.y, at.z, 1.0));
      final x = ((clip.x / clip.w * 0.5 + 0.5) * _size).floor();
      final y = ((0.5 - clip.y / clip.w * 0.5) * _size).floor();
      final color = colors[(i ~/ 5 + i % 5) % 5];
      final got = _at(painted, x, y);
      final was = _at(reference, x, y);
      // The picture's channels that are off are off; the ones that are on
      // are the floor's light over its albedo.
      //
      // Mutation: a batch that stops at sixteen without starting another, or
      // a fifth picture read through a slot holding the fourth, leaves a
      // decal here the floor's colour or another's.
      for (final (channel, on) in <(double, double)>[
        (got.x, color.r),
        (got.y, color.g),
        (got.z, color.b),
      ]) {
        expect(
          channel,
          on > 0.0 ? greaterThan(was.x * 2.0) : closeTo(0.0, 1e-3),
          reason: 'decal $i at ($x, $y)',
        );
      }
    }
  });

  test('the picture faces up its box, unmirrored', () {
    final it = _stage();
    // Red, green / blue, white, from the top left of the picture.
    final picture = it.device.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: Uint8List.fromList(<int>[
        255, 0, 0, 255, 0, 255, 0, 255, //
        0, 0, 255, 255, 255, 255, 255, 255,
      ]).buffer.asByteData(),
    );
    it.scene.add(_decal(Vector4(1.0, 1.0, 1.0, 1.0))..texture = picture);
    final painted = _scene(it);
    // The camera looks straight down with the box's -z at the top of the
    // screen, so the picture reads as it was drawn. A quarter in from each
    // edge of the box is a texel centre, where bilinear is the texel.
    final project = it.camera.viewProjection(1.0);
    Vector4 quarter(double x, double z) {
      final clip = project.transform(Vector4(x, 0.0, z, 1.0));
      return _at(
        painted,
        ((clip.x / clip.w * 0.5 + 0.5) * _size).floor(),
        ((0.5 - clip.y / clip.w * 0.5) * _size).floor(),
      );
    }

    // Mutation: taking v from -z, or u from -x, mirrors the picture, and the
    // red corner moves.
    final topLeft = quarter(-0.75, -0.75);
    final topRight = quarter(0.75, -0.75);
    final bottomLeft = quarter(-0.75, 0.75);
    expect(topLeft.x, greaterThan(topLeft.y * 4.0));
    expect(topRight.y, greaterThan(topRight.x * 4.0));
    expect(bottomLeft.z, greaterThan(bottomLeft.x * 4.0));
  });

  test(
    'an unlit surface has no light to lend, so the decal is its own colour',
    () {
      final it = _stage(
        floor: RenderMaterial(
          lighting: LightingModel.unlit,
          baseColor: _fromSrgb(_grey),
        ),
      );
      it.scene.add(_decal(Vector4(0.2, 0.6, 1.0, 1.0)));
      final center = _at(_scene(it), _size ~/ 2, _size ~/ 2);
      // Mutation: dividing by the albedo buffer's nought with no floor under
      // it paints the unlit floor white, or infinite.
      expect(center.x, closeTo(_linear(0.2), 2e-3));
      expect(center.y, closeTo(_linear(0.6), 2e-3));
      expect(center.z, closeTo(1.0, 2e-3));
    },
  );

  test('an emissive decal adds its glow over the light it borrowed', () {
    final it = _stage();
    final decal = it.scene.add(_decal(Vector4(1.0, 0.5, 0.0, 1.0)));
    final lit = _at(_scene(it), _size ~/ 2, _size ~/ 2);
    decal.emissive = LinearColor(3.0, 3.0, 3.0);
    final glowing = _at(_scene(it), _size ~/ 2, _size ~/ 2);
    // Mutation: an emission multiplied in with the factor rather than added
    // with the term scales with the light and is nought in the dark.
    expect(glowing.x - lit.x, closeTo(3.0, 0.01));
    expect(glowing.y - lit.y, closeTo(3.0 * _linear(0.5), 0.01));
    expect(glowing.z - lit.z, closeTo(0.0, 1e-3));
  });

  test('glass above a decal is drawn over it, not painted', () {
    final it = _stage();
    // A pane a metre over the box's top, so its own points are outside it.
    it.scene.add(
      MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3(5.0, 0.05, 5.0)).build(),
        ),
        RenderMaterial(
          lighting: LightingModel.unlit,
          baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, 0.3),
          alphaMode: MaterialAlphaMode.blend,
        ),
      )..setPosition(0.0, 1.5, 0.0),
    );
    final decal = it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0)));
    decal.isVisible = false;
    final reference = _scene(it);
    decal.isVisible = true;
    final result = _render(it);
    final painted = it.probe.last!;
    expect(result.passes.map((p) => p.name), contains('transparent'));
    final center = _at(painted, _size ~/ 2, _size ~/ 2);
    final was = _at(reference, _size ~/ 2, _size ~/ 2);
    // Mutation: painting after the glass reads the pane's depth out of the
    // surface buffer, finds it outside the box, and the decal is gone.
    expect(center.x, greaterThan(was.x + 0.1));
    expect(center.y, lessThan(was.y));
  });

  test('a decal near the top of the frame is painted to its edges', () {
    // The pass cuts each draw to the screen rectangle its boxes cover, counted
    // from the top left as every rectangle the engine hands a backend is. A
    // decal in the top rows of the picture, with nothing in the bottom ones,
    // is the arrangement where a rectangle counted from the wrong edge cuts
    // away all of it.
    final it = _stage();
    final decal = it.scene.add(
      DecalNode(color: LinearColor.fromSrgb(1.0, 0.0, 0.0, 1.0))
        ..setScale(2.0, 1.0, 1.0)
        ..setPosition(0.0, 0.0, -1.5),
    );
    decal.isVisible = false;
    final reference = _scene(it);
    decal.isVisible = true;
    final painted = _scene(it);

    // Where the box's footprint on the floor lands, row by row.
    final project = it.camera.viewProjection(1.0);
    int row(double z) {
      final clip = project.transform(Vector4(0.0, 0.0, z, 1.0));
      return ((0.5 - clip.y / clip.w * 0.5) * _size).floor();
    }

    final top = row(-2.0);
    final bottom = row(-1.0);
    expect(bottom, lessThan(_size ~/ 2), reason: 'the box is in the top half');
    final rows = _changed(painted, reference).map((p) => p ~/ _size).toSet();
    // Mutation: a scissor whose y is measured from the bottom, or flipped
    // again for a backend whose rows run upward, leaves none of these rows
    // painted.
    for (var y = top + 1; y < bottom; y++) {
      expect(rows, contains(y), reason: 'row $y of $top..$bottom');
    }
    expect(rows.every((y) => y >= top && y <= bottom), isTrue);
  });

  test('switched off as a step like any other pass', () {
    final it = _stage();
    final without = _scene(it);
    it.scene.add(_decal(Vector4(1.0, 0.0, 0.0, 1.0)));
    final result = _render(
      it,
      _on.without(const <RenderStep>{RenderStep.decals}),
    );
    expect(result.passes.map((p) => p.name), isNot(contains('decals')));
    expect(_changed(it.probe.last!, without), isEmpty);
  });
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
