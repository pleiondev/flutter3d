/// A planar reflector shows the world mirrored in its plane, and a camera
/// into a texture shows what it sees in the same frame — `P4`.
///
///     dart test test/planar_reflection_test.dart
///
/// The reflection claims read the lit scene before the post chain, through a
/// node registered behind it, and set it against a second scene built to be
/// what the mirror should show: the same world with every mesh mirrored in
/// the plane and the mirror taken away. Unlit materials and no sky, so a
/// mesh's colour does not depend on which way it faces the light, and the
/// two pictures can be compared pixel for pixel.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// Reads the scene target as the opaque half, the reflections and the glass
/// left it.
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
  _SceneProbe probe,
});

_Stage _stage({Vector3? from}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPositionFrom(from ?? Vector3(0.0, 3.0, 5.0))
    ..lookAt(Vector3.zero());
  final scene = Scene()..add(camera);
  final probe = _SceneProbe(device);
  final renderer = Renderer.create(device: device)..renderSteps.addNode(probe);
  return (
    device: device,
    renderer: renderer,
    scene: scene,
    camera: camera,
    probe: probe,
  );
}

RenderMaterial _unlit(double r, double g, double b) => RenderMaterial(
  lighting: LightingModel.unlit,
  baseColor: LinearColor.fromSrgb(r, g, b, 1.0),
);

MeshNode _cube(
  _Stage it,
  RenderMaterial material,
  Vector3 at, {
  double size = 1,
}) => it.scene.add(
  MeshNode(
    DeviceMesh.upload(it.device, CuboidShape(size: Vector3.all(size)).build()),
    material,
  )..setPositionFrom(at),
);

/// A black floor eight metres square at y = 0, which shows nothing of its
/// own: under a reflector of F0 one, every pixel of it is the reflection.
MeshNode _floor(_Stage it, {RenderMaterial? material}) => it.scene.add(
  MeshNode(
    DeviceMesh.upload(
      it.device,
      const PlaneShape(width: 8.0, depth: 8.0).build(),
    ),
    material ?? _unlit(0.0, 0.0, 0.0),
  ),
);

const RenderSettings _on = RenderSettings(
  bloom: BloomSettings(enabled: false),
  planarReflections: PlanarReflectionSettings(enabled: true),
);

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

/// Every pixel whose colour [a] and [b] disagree on by more than [by].
List<int> _changed(Float32List a, Float32List b, {double by = 1e-4}) => <int>[
  for (var p = 0; p < _size * _size; p++)
    if (<int>[0, 1, 2].any((c) => (a[p * 4 + c] - b[p * 4 + c]).abs() > by)) p,
];

/// How many pixels are mostly [channel] and nothing else.
int _count(Float32List frame, int channel) => <int>[
  for (var p = 0; p < _size * _size; p++)
    if (frame[p * 4 + channel] > 0.3 &&
        <int>[
          0,
          1,
          2,
        ].where((c) => c != channel).every((c) => frame[p * 4 + c] < 0.1))
      p,
].length;

void main() {
  group('planar reflections', () {
    test('off by default: the pass does not run and the frame is the same', () {
      final it = _stage();
      final floor = _floor(it);
      _cube(it, _unlit(1.0, 0.1, 0.1), Vector3(0.0, 1.0, 0.0));
      final without = _scene(it, const RenderSettings());
      it.scene.add(PlanarReflectorNode(surfaces: <MeshNode>[floor]));
      final result = _render(it, const RenderSettings());
      // Mutation: an `isActive` that forgets the setting draws the scene a
      // second time on every frame with a reflector in it.
      expect(
        result.passes.map((p) => p.name),
        isNot(contains('planar reflections')),
      );
      expect(_changed(it.probe.last!, without), isEmpty);
    });

    test(
      'on, with the reflector hidden, nothing is drawn and nothing moves',
      () {
        final it = _stage();
        final floor = _floor(it);
        _cube(it, _unlit(1.0, 0.1, 0.1), Vector3(0.0, 1.0, 0.0));
        final without = _scene(it);
        it.scene.add(
          PlanarReflectorNode(surfaces: <MeshNode>[floor])..isVisible = false,
        );
        final result = _render(it);
        // Mutation: asking whether the scene holds a reflector rather than
        // whether one is visible draws a picture nobody is shown.
        expect(
          result.passes.map((p) => p.name),
          isNot(contains('planar reflections')),
        );
        expect(_changed(it.probe.last!, without), isEmpty);
      },
    );

    test('a mirror shows the world mirrored in its plane', () {
      final it = _stage();
      final floor = _floor(it);
      _cube(it, _unlit(1.0, 0.1, 0.1), Vector3(0.0, 1.0, 0.0));
      _cube(it, _unlit(0.1, 0.2, 1.0), Vector3(1.4, 0.4, -0.8), size: 0.8);
      it.scene.add(
        PlanarReflectorNode(surfaces: <MeshNode>[floor], resolution: 1.0),
      );
      final mirrored = _scene(it);

      // The same world with every mesh mirrored in y = 0 and no floor: what
      // the mirror ought to show, seen directly.
      final reference = _stage();
      _cube(reference, _unlit(1.0, 0.1, 0.1), Vector3(0.0, 1.0, 0.0));
      _cube(reference, _unlit(1.0, 0.1, 0.1), Vector3(0.0, -1.0, 0.0));
      _cube(
        reference,
        _unlit(0.1, 0.2, 1.0),
        Vector3(1.4, 0.4, -0.8),
        size: 0.8,
      );
      _cube(
        reference,
        _unlit(0.1, 0.2, 1.0),
        Vector3(1.4, -0.4, -0.8),
        size: 0.8,
      );
      final seen = _scene(reference);

      // The reflection is there at all: twice the red the cube alone has.
      expect(_count(mirrored, 0), greaterThan(_count(seen, 0) ~/ 2 + 20));
      // And it is where the mirrored world is, texel for pixel: what differs
      // is a pixel or two along the edges, where a triangle drawn through
      // the mirror and the same triangle mirrored in its vertices round
      // their edges apart.
      //
      // Mutation: a mirror built from the camera's own view (no reflection)
      // shows the cubes from above on the floor and moves hundreds of
      // pixels; a picture read with its rows the wrong way up moves them too.
      expect(_changed(mirrored, seen, by: 0.05).length, lessThan(12));
    });

    test('what is below the plane is not reflected up through it', () {
      final it = _stage();
      final floor = _floor(it);
      // Under the floor, on the line from the mirrored camera to the middle
      // of the mirror, where it would cover the whole reflection.
      _cube(it, _unlit(0.1, 1.0, 0.1), Vector3(0.0, -1.5, 1.8));
      _cube(it, _unlit(1.0, 0.1, 0.1), Vector3(0.0, 1.0, 0.0));
      it.scene.add(
        PlanarReflectorNode(surfaces: <MeshNode>[floor], resolution: 1.0),
      );
      final frame = _scene(it);
      // Mutation: drawing the mirrored camera with its ordinary projection
      // rather than `obliqueNearPlane` covers the mirror in green.
      expect(_count(frame, 1), 0);
      expect(_count(frame, 0), greaterThan(40));
    });

    test('water reflects more at a grazing angle than looking down', () {
      final it = _stage(from: Vector3(0.0, 1.2, 6.0));
      // A tall wall behind the pool, so its reflection runs from the far
      // edge, seen at a grazing angle, to near the camera, seen steeply.
      _cube(it, _unlit(1.0, 1.0, 1.0), Vector3(0.0, 3.0, -4.2), size: 6.0);
      final floor = _floor(it, material: _unlit(0.0, 0.0, 0.0));
      final reflector = it.scene.add(
        PlanarReflectorNode(
          surfaces: <MeshNode>[floor],
          reflectance: 0.02,
          resolution: 1.0,
        ),
      );
      final water = _scene(it);
      reflector.reflectance = 1.0;
      final mirror = _scene(it);

      // Under the mirror a floor pixel is the reflection; under the water it
      // is the reflection times the Fresnel term over black, so the ratio of
      // the two is the term.
      final terms = <(int, double)>[
        for (var y = 0; y < _size; y++)
          if (mirror[(y * _size + _size ~/ 2) * 4] > 0.5)
            (
              y,
              water[(y * _size + _size ~/ 2) * 4] /
                  mirror[(y * _size + _size ~/ 2) * 4],
            ),
      ];
      final floorRows = terms.where((t) => t.$1 > _size ~/ 2).toList();
      expect(floorRows.length, greaterThan(4));
      // Mutation: a term without the angle — F0 alone — is 0.02 on every row.
      expect(floorRows.first.$2, greaterThan(floorRows.last.$2 * 2));
      for (final (_, term) in floorRows) {
        expect(term, inInclusiveRange(0.02 - 1e-3, 1.0));
      }
    });

    test('a camera behind the plane sees no reflection', () {
      final it = _stage(from: Vector3(0.0, -3.0, 5.0));
      final floor = _floor(
        it,
        material: _unlit(0.3, 0.3, 0.3)..doubleSided = true,
      );
      _cube(it, _unlit(1.0, 0.1, 0.1), Vector3(0.0, 1.0, 0.0));
      final without = _scene(it);
      it.scene.add(
        PlanarReflectorNode(surfaces: <MeshNode>[floor], resolution: 1.0),
      );
      // Mutation: without the check, the near plane gives up on the eye's
      // side and the mirrored camera draws through the plane anyway.
      expect(_changed(_scene(it), without), isEmpty);
    });
  });

  group('render textures', () {
    test('a scene without one does not run the pass', () {
      final it = _stage();
      _cube(it, _unlit(1.0, 0.1, 0.1), Vector3.zero());
      final result = _render(it, const RenderSettings());
      expect(
        result.passes.map((p) => p.name),
        isNot(contains('render textures')),
      );
    });

    test('holds the camera\'s picture as the sRGB a picture is painted in', () {
      final it = _stage(from: Vector3(0.0, 0.0, 3.0));
      // An unlit cube emits its base colour as linear light, so a picture
      // encoded right hands the sRGB it was painted with back, unchanged.
      _cube(it, _unlit(0.9, 0.3, 0.1), Vector3.zero(), size: 1.0);
      final texture = RenderView.texture(
        it.device,
        camera: it.camera,
        width: _size,
        height: _size,
        clearColorSrgb: Vector4(0.2, 0.4, 0.6, 1.0),
      );
      it.scene.addTextureView(texture);
      _render(it);
      final picture = it.device.readHdrPixels(texture.texture!);
      expect(texture.isDrawn, isTrue);
      final center = (_size ~/ 2 * _size + _size ~/ 2) * 4;
      // Mutation: leaving the light linear turns 0.3 into 0.07 and 0.1 into
      // 0.01; an exposure applied twice, or a tone curve, moves all three.
      expect(picture[center], closeTo(0.9, 1e-3));
      expect(picture[center + 1], closeTo(0.3, 1e-3));
      expect(picture[center + 2], closeTo(0.1, 1e-3));
      // And where nothing was drawn, the clear colour as it was given.
      expect(picture[0], closeTo(0.2, 1e-3));
      expect(picture[1], closeTo(0.4, 1e-3));
      expect(picture[2], closeTo(0.6, 1e-3));
    });

    test('a material shows the picture in the frame it was taken', () {
      final it = _stage(from: Vector3(0.0, 0.0, 3.0));
      // The camera into the texture looks at a red cube far off to the side.
      final watcher = CameraNode()
        ..setPosition(20.0, 0.0, 3.0)
        ..lookAt(Vector3(20.0, 0.0, 0.0));
      it.scene.add(watcher);
      _cube(it, _unlit(1.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0), size: 3.0);
      final texture = RenderView.texture(
        it.device,
        camera: watcher,
        width: 16,
        height: 16,
      );
      it.scene.addTextureView(texture);
      // A screen filling the view, showing it unlit.
      _cube(
        it,
        RenderMaterial(lighting: LightingModel.unlit, albedo: texture.texture),
        Vector3.zero(),
        size: 2.0,
      );
      final frame = _scene(it);
      final middle = (_size ~/ 2 * _size + _size ~/ 2) * 4;
      // Mutation: drawing the textures after the scene shows whatever the
      // allocation held on the first frame, which here is black.
      expect(frame[middle], closeTo(1.0, 0.02));
      expect(frame[middle + 1], lessThan(0.02));
    });

    test('one that does not refresh is drawn once, and again on asking', () {
      final it = _stage();
      _cube(it, _unlit(0.5, 0.5, 0.5), Vector3.zero());
      final texture = RenderView.texture(
        it.device,
        camera: it.camera,
        width: 8,
        height: 8,
        options: RenderViewSettings(refreshEveryFrame: false),
      );
      it.scene.addTextureView(texture);
      int drawn() => _render(
        it,
      ).passes.firstWhere((p) => p.name == 'render textures').drawCalls;
      // Mutation: ignoring `refreshEveryFrame` draws the picture every frame.
      expect(drawn(), greaterThan(0));
      expect(drawn(), 0);
      texture.invalidate();
      expect(drawn(), greaterThan(0));
      expect(drawn(), 0);
    });
  });
}
