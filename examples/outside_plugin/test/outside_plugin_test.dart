/// The plugin from outside, installed: its quantity on a body's material
/// state, the contacts it hears, the field it writes and the solver it
/// registers, on the loop and in a frame drawn on the software rasteriser.
///
///     flutter test test/outside_plugin_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_hardware/backend.dart' show wrapTexture;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outside_plugin/outside_plugin.dart';

import 'scene.dart';

EngineLoop _loop({
  SimulationProfile profile = warmingProfile,
  bool withPlugin = true,
}) {
  final loop = EngineLoop(
    input: InputState(),
    profile: profile,
    plugins: <Flutter3dPlugin>[if (withPlugin) OutsidePlugin()],
  );
  dropBall(loop);
  return loop;
}

double _warmth(EngineLoop loop) {
  final body = loop.world
      .query()
      .having<MaterialStateComponent>()
      .entities
      .single;
  return loop.world
          .get<MaterialStateComponent>(body)!
          .state[warmthId]
          ?.valueIn(Unit.kelvin) ??
      0.0;
}

/// A node that reads the field in the frame, as a volume would.
final class _Volume extends RenderNode {
  FieldStorage? seen;

  @override
  String get name => 'outside.volume';

  @override
  List<ResourceId> get reads => <ResourceId>[ResourceId(heatField.id)];

  @override
  List<ResourceId> get writes => const <ResourceId>[ResourceId('frame')];

  @override
  void execute(RenderFrame frame) =>
      seen = frame.resources.field(ResourceId(heatField.id));
}

final class _Source with FrameTextureSource {
  @override
  TextureHandle acquire(RenderTargetDescriptor spec) => wrapTexture(
    backend: 'frame',
    width: spec.width,
    height: spec.height,
    format: spec.format,
  );

  @override
  void release(TextureHandle texture) {}
}

final class _Services with RenderServices {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the field frame draws no scene');
}

/// Runs [upload] and a reader of its field in one frame on [device].
FieldStorage? _frame(FieldUpload upload, GraphicsDevice device) {
  final volume = _Volume();
  final graph =
      (FrameGraph()
            ..addNode(upload)
            ..addNode(volume))
          .compile(outputs: const <ResourceId>[ResourceId('frame')]);
  final resources = FrameResources(
    source: _Source(),
    graph: graph,
    frameWidth: 8,
    frameHeight: 8,
  );
  final frame = RenderFrame(
    device: device,
    resources: resources,
    services: _Services(),
    settings: const RenderSettings(),
    width: 8,
    height: 8,
  );
  for (var i = 0; i < graph.order.length; i++) {
    resources.beginNode(i);
    (graph.order[i] as RenderNode).execute(frame);
    resources.endNode(i);
  }
  return volume.seen;
}

CpuDevice _cpu() => CpuDevice(
  width: 8,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  group('under its own profile', () {
    test('contacts warm the field, and the body takes the warmth into its '
        'material state', () {
      final loop = _loop();
      expect(loop.systemsIn(LoopPhase.fields), <String>[Warming.id]);
      loop.runSteps(90);
      final heat = loop.fields.hostField(heatField.id)!;
      // Mutation: drop the contact listener. The ball rests on the floor
      // for a second and leaves no heat at all.
      expect(heat.values.reduce((a, b) => a > b ? a : b), greaterThan(0.1));
      // Mutation: write the field and not the material state.
      expect(_warmth(loop), greaterThan(0.0));
      expect(loop.simulationVersion.subsystems, <String, int>{Warming.id: 1});
      expect(loop.simulationVersion.profile, warmingProfile);
    });

    test('a rollback puts the heat and the heat still to come back', () {
      final loop = _loop()..runSteps(40);
      final saved = loop.capture();
      final digest = loop.digest();
      loop.runSteps(20);
      final ahead = loop.digest();
      loop.restore(saved);
      expect(loop.digest(), digest);
      loop.runSteps(20);
      // Mutation: leave the heat heard and not yet laid down out of the
      // snapshots. The replayed step lays down nothing, and the run forks.
      expect(loop.digest(), ahead);
    });

    test('its quantity crosses a save and the wire with the body', () {
      final loop = _loop()..runSteps(60);
      final body = loop.world
          .query()
          .having<MaterialStateComponent>()
          .entities
          .single;
      final component = loop.world.get<MaterialStateComponent>(body)!;
      final codec = MaterialStateComponent.codec;
      final back = codec.decode(
        ComponentDecodeContext(codec.encode(component), version: codec.version),
      )!;
      expect(back.state[warmthId], component.state[warmthId]);
    });
  });

  group('under the default profile', () {
    test('the solver is registered and runs nowhere, and the simulation is '
        'the one without the plugin', () {
      final plain = _loop(
        profile: SimulationProfile.deterministic,
        withPlugin: false,
      );
      final installed = _loop(profile: SimulationProfile.deterministic);
      expect(installed.subsystems.declared.single.id, Warming.id);
      expect(installed.subsystems.running, isEmpty);
      expect(installed.simulationVersion.subsystems, isEmpty);
      expect(installed.snapshots.parts, plain.snapshots.parts);
      for (var step = 0; step < 60; step++) {
        plain.runSteps(1);
        installed.runSteps(1);
        // Mutation: hear the contacts under every profile. The heat waiting
        // for a solver that never runs would be state, and digest.
        expect(installed.digest(), plain.digest(), reason: 'step $step');
      }
      expect(_warmth(installed), 0.0);
    });

    test('but the version names the plugin, as every simulating plugin\'s '
        'does', () {
      // What the library's comment says, held: the digests are the
      // default's, the version is not. A plugin that touches the
      // simulation is counted under every profile.
      final plain = _loop(
        profile: SimulationProfile.deterministic,
        withPlugin: false,
      );
      final installed = _loop(profile: SimulationProfile.deterministic);
      expect(plain.simulationVersion.plugins, isNot(contains('outside')));
      expect(installed.simulationVersion.plugins['outside'], 1);
      expect(
        installed.simulationVersion.refusalOn(plain.simulationVersion),
        isNotNull,
      );
    });
  });

  group('in the frame, on the software rasteriser', () {
    test('the published field reaches a reader as a 3D texture', () {
      final loop = _loop()..runSteps(60);
      final upload = OutsidePlugin.upload(loop.fields)!;
      final device = _cpu();
      expect(upload.place(ComputeExecutors(device: device)), isNull);
      final seen = _frame(upload, device);
      expect(seen, isA<Texture3DField>());
      expect(seen!.declaration.id, heatField.id);
    });

    test('and as a buffer on the CPU executor, bit for bit', () async {
      final loop = _loop()..runSteps(60);
      final published = loop.fields.published(heatField.id)!;
      final upload = FieldUpload(published, residence: FieldResidence.buffer);
      final device = _cpu();
      expect(upload.place(ComputeExecutors(device: device)), isNull);
      final seen = _frame(upload, device)! as BufferField;
      final read = Float32List.sublistView(
        await device.readBuffer(seen.buffer),
      );
      expect(read, published.values);
      expect(read.any((v) => v > 0), isTrue);
    });
  });
}
