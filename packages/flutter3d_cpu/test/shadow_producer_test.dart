/// A shadow technique's own producer draws the directional map in place of
/// the engine's casters (D22), into the atlas the engine laid out and with
/// the matrices it fitted, and the engine draws its own again once the
/// producer is gone.
///
///     dart test test/shadow_producer_test.dart
///
/// Drawn on the software rasteriser. Mutation: skip the producer branch in
/// `_renderShadowMap` and the producer never runs; leave the engine's tiles
/// baked when the producer draws and the frame after it keeps the empty
/// map, so the box casts no shadow.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

/// A map with nothing in it: every tile cleared to the far plane.
final class _EmptyMap extends RenderNode {
  _EmptyMap(this.cascades);

  final ShadowCascades cascades;

  @override
  String get name => 'test.empty map';

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.shadowMap];

  @override
  void execute(RenderFrame frame) {
    final far = cascades.reversed ? 0.0 : 1.0;
    frame.device
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: cascades.atlas,
                clearValue: Vector4(far, 1.0, 1.0, 1.0),
              ),
            ],
            depth: DepthTarget(texture: cascades.depth, clearValue: far),
          ),
        )
        .submit();
  }
}

/// The 3×3 lookup, with the map drawn by [_EmptyMap]; records what it was
/// handed.
final class _Producing extends ShadowTechnique {
  _Producing();

  final List<ShadowCascades> handed = <ShadowCascades>[];

  @override
  String get name => 'producing';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;

  @override
  RenderNode? shadowMapProducer(ShadowProducerContext context) {
    final cascades = context.cascades!;
    handed.add(cascades);
    return _EmptyMap(cascades);
  }
}

Scene _floorAndBox(GraphicsDevice device) {
  final sun = LightNode(
    name: 'sun',
    intensity: 3.0 * LightNode.defaultIntensity,
  )..castsShadow = true;
  sun.lookAt(Vector3(-0.85, -1.0, -0.2));
  return Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(14.0, 0.2, 14.0)).build(),
        ),
        RenderMaterial(name: 'floor'),
      )..setPosition(0.0, -0.1, 0.0),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(1.6, 0.2, 1.6)).build(),
        ),
        RenderMaterial(name: 'box'),
      )..setPosition(0.0, 0.6, 0.0),
    )
    ..add(sun);
}

void main() {
  test(
    'a producer draws the map, and the engine draws it again after',
    () async {
      final device = CpuDevice(
        width: _width,
        height: _height,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final renderer = Renderer.create(device: device);
      final scene = _floorAndBox(device);
      final camera = CameraNode()
        ..setPosition(0.0, 12.0, 0.01)
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
              cascades: 2,
              viewDistance: 20.0,
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
      final cascades = technique.handed.single;
      expect(cascades.count, 2);
      expect(cascades.resolution, const ShadowSettings().resolution);
      expect(cascades.atlas.width, cascades.resolution * 2);
      expect(cascades.tileOf(1).x, cascades.resolution);
      expect(cascades.lightDirection.length, closeTo(1.0, 1e-6));

      // No caster in the producer's map, so the box's shadow is gone.
      expect(sum(produced), greaterThan(sum(engine)));
      expect(again, engine);
    },
  );
}
