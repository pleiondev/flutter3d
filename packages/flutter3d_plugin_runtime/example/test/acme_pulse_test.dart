/// The Wasm render sample: `plugin/acme_pulse.f3dplugin`, whose render step
/// is driven frame by frame by `plugin/pulse.wasm`, a render module of ABI 3
/// built from `plugin/pulse.wat` by wabt's `wat2wasm`, with a light type, a
/// vertex layout and a level-of-detail table of its own.
///
///     dart test test/acme_pulse_test.dart
///
/// The module's bytes are the committed ones, made by an outside toolchain
/// rather than by the test assembler, so what is held here is that a module
/// such a toolchain writes is one the host reads.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// A frame that writes down what the module asks of it.
final class _Frame extends RenderProgramFrame {
  _Frame(this.time);

  final List<String> said = <String>[];

  @override
  final double time;

  @override
  int get frame => 0;

  @override
  int get view => 0;

  @override
  int get width => 32;

  @override
  int get height => 32;

  /// A write of one component reads as `param`, a write of several as
  /// `floats`: the two imports, as the module made them.
  @override
  void setParameter(RenderParameterWrite write) {
    final RenderParameterWrite(:parameter, :component, :values) = write;
    said.add(
      values.length == 1
          ? 'param $parameter $component ${values.single}'
          : 'floats $parameter ${values.map((v) => v.toStringAsFixed(2))}',
    );
  }

  @override
  void draw() => said.add('draw');
}

Uint8List _file(String name) => File('plugin/$name').readAsBytesSync();

/// The sample loaded, with [document] in place of its document when given.
Future<DataPlugin> _load({String? document}) =>
    DataPluginLoader(sections: DataSections(renderDataSections)).load(
      document ?? File('plugin/acme_pulse.f3dplugin').readAsStringSync(),
      MemoryPluginSource(<String, Uint8List>{
        'pulse.wasm': _file('pulse.wasm'),
        'pulse.f3dmat': _file('pulse.f3dmat'),
      }),
    );

({Renderer renderer, EngineLoop loop, RuntimeShaders shaders}) _engine(
  DataPlugin plugin,
) {
  final device = FakeBackend();
  final renderer = Renderer.create(device: device);
  final shaders = RuntimeShaders(
    backend: RuntimeBackends.cpu,
    loadShaders: device.loadShaders,
    addMaterials: renderer.renderSteps.addMaterials,
  );
  return (
    renderer: renderer,
    shaders: shaders,
    loop: EngineLoop(
      input: InputState(),
      backend: RuntimeBackends.cpu,
      registries: <PluginRegistry>[renderer.renderSteps, shaders],
      plugins: <Flutter3dPlugin>[plugin],
    ),
  );
}

FrameResult _frame(Renderer renderer) {
  final camera = CameraNode()..setPosition(0.0, 3.0, 3.0);
  camera.lookAt(Vector3.zero());
  return renderer.render(
    width: 32,
    height: 32,
    scene: Scene()..add(camera),
    views: <CameraView>[CameraView(camera: camera)],
  );
}

void main() {
  test('the committed module is a render module of ABI 3, and not a step '
      'module', () {
    // Mutation: build the module from an older `pulse.wat` that says ABI 2,
    // or let the decoder read f32 in a step module.
    final bytes = _file('pulse.wasm');
    final module = WasmModule.decode(bytes, kind: WasmModuleKind.render);
    expect(module.kind, WasmModuleKind.render);
    expect(
      () => WasmModule.decode(bytes),
      throwsA(
        isA<WasmException>().having(
          (e) => e.message,
          'message',
          contains('uses an f32'),
        ),
      ),
    );
    final node = WasmRenderNode(
      const WasmRenderSpec(
        module: 'pulse.wasm',
        step: 'beat',
        parameters: <String>['tint', 'strength'],
      ),
      module,
      plugin: 'acme_sample.pulse',
    );
    final frame = _Frame(1.25);
    node.run(frame);
    // A quarter into a second, the triangle wave is at a half.
    expect(frame.said, <String>[
      'param 1 0 0.5',
      'floats 0 (1.00, 0.60, 0.20)',
      'draw',
    ]);
  });

  test('its step is drawn, driven, and taken back', () async {
    // Mutation: install the step without the module's program. The pass
    // would draw with its defaults, and the module never run.
    final plugin = await _load();
    final engine = _engine(plugin);
    await engine.shaders.settled;
    expect(engine.shaders.statuses['acme_sample.pulse.beat'], isNull);
    final result = _frame(engine.renderer);
    expect(
      result.passes.map((p) => p.name),
      contains('acme_sample.pulse.beat'),
    );
    expect(result.nodeFailures, isEmpty);
    expect(plugin.renderNodes['beat']!.fuelUsed, greaterThan(0));
    // Nothing of the module is in the run's state.
    expect(plugin.save(), isEmpty);

    engine.loop.plugins.disable('acme_sample.pulse');
    engine.loop.runSteps(1);
    expect(engine.renderer.renderSteps.named('acme_sample.pulse.beat'), isNull);
  });

  test('a module that spends its frame is switched off, the plugin named, '
      'and the frame drawn', () async {
    // Mutation: let the trap out of the node. The game would lose every
    // frame to one plugin's render module.
    final plugin = await _load(
      document: File('plugin/acme_pulse.f3dplugin')
          .readAsStringSync()
          .replaceFirst('"fuelPerFrame": 1000', '"fuelPerFrame": 5'),
    );
    final engine = _engine(plugin);
    await engine.shaders.settled;
    final failed = _frame(engine.renderer).nodeFailures.single;
    expect(failed.node, 'acme_sample.pulse.beat');
    expect(failed.plugin, 'acme_sample.pulse');
    expect(plugin.renderNodes['beat']!.trapped, contains('per frame'));
    expect(_frame(engine.renderer).nodeFailures, isEmpty);
  });

  test('its light type, vertex layout and level-of-detail table are the '
      'renderer\'s while it is on', () async {
    // Mutation: register the light type under its bare name. Two plugins'
    // `glowtube` would take one code.
    final plugin = await _load();
    final engine = _engine(plugin);
    final lights = engine.renderer.lightTypes;
    expect(
      lights.codeNamed('acme_sample.pulse.glowtube'),
      greaterThanOrEqualTo(LightTypes.firstPluginCode),
    );
    expect(engine.renderer.hooks.lodPolicies, hasLength(1));
    final layouts =
        plugin.document.sections['vertexLayouts']!.section
            as List<DataVertexLayout>;
    expect(layouts.single.attributes, <String>[
      'position',
      'color',
      'texcoord',
    ]);

    engine.loop.plugins.disable('acme_sample.pulse');
    engine.loop.runSteps(1);
    expect(lights.codeNamed('acme_sample.pulse.glowtube'), isNull);
    expect(engine.renderer.hooks.lodPolicy, isNull);
  });
}
