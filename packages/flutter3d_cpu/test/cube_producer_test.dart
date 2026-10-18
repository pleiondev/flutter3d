/// A shadow technique's own producer draws the cube atlas of point and spot
/// lights in place of the engine's moving casters (D22), into the rows the
/// engine laid out and with the faces it fitted, and the engine draws its
/// own again once the producer is gone.
///
///     dart test test/cube_producer_test.dart
///
/// Drawn on the software rasteriser, the twin of `shadow_producer_test.dart`
/// for the sun. Mutation: skip `_produceCubeShadow` in the `point shadows`
/// node and the producer never runs, so the box keeps its shadow; leave the
/// face scheduler's memory standing when the producer draws and the frame
/// after it keeps the empty atlas, so the box casts no shadow.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// An atlas with nothing in it: every tile cleared to the far plane, which
/// is one in a cube atlas whatever the depth convention.
final class _EmptyAtlas extends RenderNode {
  _EmptyAtlas(this.atlas);

  final ShadowCubeAtlas atlas;

  @override
  String get name => 'test.empty atlas';

  @override
  List<ResourceId> get keeps => const <ResourceId>[FrameResourceIds.cubeShadow];

  @override
  void execute(RenderFrame frame) {
    frame.device
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: atlas.atlas,
                clearValue: ClearColor(1.0, 1.0, 1.0, 1.0),
              ),
            ],
            depth: DepthTarget(texture: atlas.depth),
          ),
        )
        .submit();
  }
}

/// The engine's 3×3 lookup for the sun, and the cube atlas drawn by
/// [_EmptyAtlas]; records what it was handed.
final class _Producing extends ShadowTechnique {
  _Producing();

  final List<ShadowCubeAtlas> handed = <ShadowCubeAtlas>[];

  @override
  String get name => 'producing';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;

  @override
  RenderNode? cubeAtlasProducer(ShadowProducerContext context) {
    final atlas = context.cubeAtlas!;
    handed.add(atlas);
    return _EmptyAtlas(atlas);
  }
}

/// A technique of one's own with no producer: it looks at the lights it is
/// handed, when [reads] says so, and answers null, so the engine draws.
final class _Declining extends ShadowTechnique {
  _Declining({required this.reads});

  final bool reads;
  final List<List<ShadowCubeLight>> seen = <List<ShadowCubeLight>>[];

  @override
  String get name => 'declining';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;

  @override
  RenderNode? cubeAtlasProducer(ShadowProducerContext context) {
    if (reads) seen.add(List<ShadowCubeLight>.of(context.cubeAtlas!.lights));
    return null;
  }
}

Scene _floorBoxAndLamp(GraphicsDevice device) => Scene()
  ..add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(10.0, 0.2, 10.0)).build(),
      ),
      RenderMaterial(name: 'floor'),
    )..setPosition(0.0, -0.1, 0.0),
  )
  ..add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.8)).build()),
      RenderMaterial(name: 'box'),
    )..setPosition(0.0, 0.8, 0.0),
  )
  ..add(
    LightNode(
      type: LightType.point,
      intensity: 20.0 * LightNode.defaultIntensity,
      range: 8.0,
      castsShadow: true,
    )..setPosition(0.0, 2.5, 0.0),
  );

void main() {
  test(
    'a producer draws the cube atlas, and the engine draws it again',
    () async {
      final device = CpuDevice(
        width: _width,
        height: _height,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final renderer = Renderer.create(device: device);
      final scene = _floorBoxAndLamp(device);
      final camera = CameraNode()
        ..setPosition(0.0, 9.0, 0.01)
        ..lookAt(Vector3.zero());
      final technique = _Producing();

      Future<Uint8List> draw(ShadowFilter filter) async {
        final frame = renderer.render(
          width: _width,
          height: _height,
          scene: scene,
          views: <CameraView>[CameraView(camera: camera)],
          settings: RenderSettings(
            shadows: ShadowSettings(
              cubeResolution: ShadowSettings.minCubeTile,
              filter: filter,
            ),
          ),
        );
        return (await device.readback(frame.frame)).buffer.asUint8List();
      }

      int sum(Uint8List pixels) => pixels.fold(0, (a, b) => a + b);

      final engine = await draw(ShadowFilter.pcf);
      final produced = await draw(
        ShadowFilter.custom(
          'producing',
          base: ShadowFilter.pcf,
          technique: technique,
        ),
      );
      final again = await draw(ShadowFilter.pcf);

      expect(technique.handed, hasLength(1));
      final atlas = technique.handed.single;
      expect(atlas.tile, ShadowSettings.minCubeTile);
      expect(atlas.atlas.width, atlas.tile * 6);
      final lamp = atlas.lights.single;
      expect(lamp.isSpot, isFalse);
      expect(lamp.viewProjections, hasLength(6));
      expect(lamp.range, 8.0);
      expect(lamp.position, Vector3(0.0, 2.5, 0.0));
      expect(atlas.tileOf(lamp.row, 2).x, atlas.tile * 2);
      expect(atlas.tileOf(lamp.row, 2).y, lamp.row * atlas.tile);

      // No caster in the producer's atlas, so the box's shadow is gone.
      expect(sum(produced), greaterThan(sum(engine)));
      expect(again, engine);
    },
  );

  test('a technique with no producer is asked, and the engine draws', () async {
    // Mutation: let `_produceCubeShadow` report a technique's null as
    // produced, and the engine draws nothing: the box loses its shadow. The
    // lights a technique reads are fitted then, and the tile loop draws
    // from the same fit.
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final scene = _floorBoxAndLamp(device);
    final camera = CameraNode()
      ..setPosition(0.0, 9.0, 0.01)
      ..lookAt(Vector3.zero());

    Future<Uint8List> draw(ShadowFilter filter) async {
      final frame = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <CameraView>[CameraView(camera: camera)],
        settings: RenderSettings(
          shadows: ShadowSettings(
            cubeResolution: ShadowSettings.minCubeTile,
            filter: filter,
          ),
        ),
      );
      return (await device.readback(frame.frame)).buffer.asUint8List();
    }

    final engine = await draw(ShadowFilter.pcf);
    final silent = _Declining(reads: false);
    final looking = _Declining(reads: true);
    expect(
      await draw(
        ShadowFilter.custom(
          'silent',
          base: ShadowFilter.pcf,
          technique: silent,
        ),
      ),
      engine,
    );
    expect(
      await draw(
        ShadowFilter.custom(
          'looking',
          base: ShadowFilter.pcf,
          technique: looking,
        ),
      ),
      engine,
    );
    final lamp = looking.seen.single.single;
    expect(lamp.position, Vector3(0.0, 2.5, 0.0));
    expect(lamp.range, 8.0);
    expect(lamp.viewProjections, hasLength(6));
  });
}
