/// What a lit draw binds is decided by what the compiled stage kept —
/// `gfx-92n`.
///
///     flutter test test/liveness_test.dart
///
/// The flags on `LightingModel` used to be the whole answer, kept in step
/// with the shaders by hand, and 0.7.1 is what one out of step cost: an unlit
/// draw handed a light list its compiled Metal function had no slot for,
/// which crashed inside the driver. Every backend now hands its engine stages
/// the bundle's own table as `ShaderHandle.kept`, the renderer asks that
/// before the model's flags, and an encoder refuses a bind the table names
/// as dropped before anything reaches a driver.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every bind of a lighting model's fragment stage the renderer asked for,
/// as `stage/slot`, that the stage's compiled function does not keep.
List<String> _askedForDropped(RecordingDevice device) {
  final lit = <String>{
    for (final model in LightingModel.builtIn) model.shaderName,
    LightingModel.xray.shaderName,
  };
  return <String>{
    for (final event in device.events)
      if (event case TraceBindTexture(:final shader, :final slot)
          when lit.contains(shader) &&
              !stageBindings[shader]!.samplers.contains(slot))
        '$shader/$slot'
      else if (event case TraceBindUniformBlock(:final shader, :final block)
          when lit.contains(shader) &&
              !stageBindings[shader]!.blocks.contains(block))
        '$shader/$block',
  }.toList()..sort();
}

void main() {
  for (final which in ParityScene.values) {
    test('the ${which.name} fixture asks no lit stage for what it dropped', () {
      // The built-in models' flags agree with the table today, so this holds
      // with or without it; it is what says so the day they stop agreeing.
      final device = RecordingDevice(FakeBackend(stageBindings: stageBindings));
      final renderer = Renderer.create(device: device);
      final built = buildParityScene(device, which: which);
      renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(which),
      );
      expect(_askedForDropped(device), isEmpty);
    });
  }

  test('a model whose flags claim too much is still bound by the table', () {
    // A model pointing at the Unlit stage while declaring every map, the
    // metallic-roughness map and the light list: exactly the mismatch 0.7.1
    // shipped. The table says what Unlit kept, and nothing else is asked.
    //
    // Mutation: gate `_keepsBlock` and `_keepsSampler` on `declared` alone.
    // Unlit is then asked for eleven things it dropped, the light list and
    // the point-shadow block among them.
    const liar = LightingModel(
      'Liar',
      'Unlit',
      usesMaterialMaps: true,
      usesMetallicRoughnessMap: true,
      usesMaterialParameters: true,
    );
    final device = RecordingDevice(FakeBackend(stageBindings: stageBindings));
    final renderer = Renderer.create(device: device);
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(device, SphereShape(radius: 0.5).build()),
          Material(name: 'liar', lighting: liar),
        ),
      )
      ..add(
        LightNode(type: LightType.point, name: 'lamp')..setPosition(0, 2, 2),
      );
    final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
    renderer.render(
      width: 32,
      height: 32,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );
    expect(_askedForDropped(device), isEmpty);
  });

  test('an encoder refuses what the stage dropped, before the driver', () {
    // The other half, and the one that holds for a caller that is not the
    // renderer: a stage that kept no point-shadow block answers false to
    // being handed one, on the software rasteriser as on Metal.
    final device = CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final unlit = device.shaders['Unlit']!;
    expect(unlit.kept, isNotNull);
    expect(unlit.mayBindBlock('PointShadow'), isFalse);
    final target = device.createTexture(
      const RenderTargetSpec(
        width: 4,
        height: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    final pass = device.beginRenderPass(
      RenderPassDescriptor(colors: <ColorTarget>[ColorTarget(texture: target)]),
    );
    expect(
      pass.bindUniformBlock(unlit, 'PointShadow', <String, Float32List>{
        'params': Float32List(4),
      }),
      isFalse,
    );
    pass.submit();
  });
}
