/// A render step from data driven by a program — what a Wasm render module
/// is to the renderer — and the data sections that declare light types,
/// vertex layouts and level-of-detail tables.
///
///     dart test test/data_plugin/render_program_test.dart
///
/// The program here is written in Dart against `RenderProgram`, the plugin
/// API's half of the render ABI; the runtime's Wasm node is held in
/// `flutter3d_plugin_runtime`'s suite and its sample. Each test names the
/// mutation that would defeat it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const String _pulse = '''
f3dmat 2
fullscreen Pulse {
  uniform vec3 tint = vec3(1.0);
  uniform float strength = 0.0;
  fragment {
    let base = sample(scene, uv);
    return vec4(mix(base.rgb, base.rgb * tint, strength), base.a);
  }
}
''';

/// A program that sets what it is told and draws on the frames it is told.
final class _Program extends RenderProgram {
  _Program(this.parameters);

  @override
  final List<String> parameters;

  /// The runs it draws on: the first.
  static const Set<int> drawOn = <int>{0};
  final List<int> frames = <int>[];
  int runs = 0;

  @override
  void run(RenderProgramFrame frame) {
    frames.add(frame.frame);
    if (parameters.contains('strength')) {
      frame.setParameter(parameters.indexOf('strength'), 0, 0.5);
    }
    if (parameters.contains('tint')) {
      frame.setParameterFloats(
        parameters.indexOf('tint'),
        Float32List.fromList(<double>[1.0, 0.5, 0.25]),
      );
    }
    if (drawOn.contains(runs++)) frame.draw();
  }
}

/// A renderer on the hardware layer's fake, and the run-time shaders that
/// compile for the software backend into it.
({Renderer renderer, FakeBackend device, RuntimeShaders shaders}) _engine() {
  final device = FakeBackend();
  final renderer = Renderer.create(device: device);
  return (
    renderer: renderer,
    device: device,
    shaders: RuntimeShaders(
      backend: RuntimeBackends.cpu,
      loadShaders: device.loadShaders,
      addMaterials: renderer.renderSteps.addMaterials,
    ),
  );
}

FrameResult _frame(Renderer renderer) {
  final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
  camera.lookAt(Vector3.zero());
  return renderer.render(
    width: 16,
    height: 16,
    scene: Scene()..add(camera),
    views: <CameraView>[CameraView(camera: camera)],
  );
}

RuntimeRenderStep _step(RenderProgram? program, {String? stage}) =>
    RuntimeRenderStep(
      name: 'acme.beat',
      anchor: RenderAnchor.afterBloom,
      shaders: <String, String>{
        if (stage == null)
          RuntimeRenderStep.materialStage: _pulse
        else
          'webgl': stage,
      },
      program: program,
    );

void main() {
  group('a step a program drives', () {
    test('runs the program each frame and draws only when it says', () async {
      // Mutation: draw the effect whether or not the program called draw.
      // A module that skips a frame would still change the picture.
      final engine = _engine();
      final program = _Program(const <String>['tint', 'strength']);
      engine.shaders.addRenderStep(_step(program), engine.renderer.renderSteps);
      await engine.shaders.settled;
      expect(engine.shaders.statuses['acme.beat'], isNull);
      final drawn = _frame(engine.renderer);
      final skipped = _frame(engine.renderer);
      expect(program.frames, hasLength(2));
      expect(drawn.drawCalls, skipped.drawCalls + 1);
      expect(
        engine.device.linkedPipelines.where((p) => p.contains('Pulse')),
        isNotEmpty,
      );
    });

    test('a parameter its stage has no uniform of switches the step off, '
        'naming both', () async {
      // Mutation: skip the check. The module's numbers would be written to
      // nothing, and the step drawn with its defaults as if it were driven.
      final engine = _engine();
      engine.shaders.addRenderStep(
        _step(_Program(const <String>['glow'])),
        engine.renderer.renderSteps,
      );
      await engine.shaders.settled;
      expect(
        engine.shaders.statuses['acme.beat'],
        allOf(contains('glow'), contains('tint, strength')),
      );
    });

    test('a raw stage cannot be driven', () {
      // Mutation: drive a raw WebGL stage. Its uniforms are unknown to the
      // engine, so a program's parameter indices would name nothing.
      final engine = _engine();
      engine.shaders.addRenderStep(
        _step(_Program(const <String>[]), stage: 'void main() {}'),
        engine.renderer.renderSteps,
      );
      expect(
        engine.shaders.statuses['acme.beat'],
        contains('material language'),
      );
    });

    test('a program that throws switches its node off with the plugin '
        'named, and the rest of the frame draws', () async {
      // Mutation: let the throw out of the frame. One plugin's render module
      // would lose every frame of the game.
      final engine = _engine();
      engine.shaders.addRenderStep(
        _step(_Throwing()),
        engine.renderer.renderSteps,
      );
      await engine.shaders.settled;
      final result = _frame(engine.renderer);
      expect(result.nodeFailures.single.node, 'acme.beat');
    });
  });

  group('the declared tables', () {
    const context = DataSectionContext(plugin: 'acme');
    Object read(DataSection section, Object? written) =>
        section.read(DataSectionRead(written, context: context));

    test('a light type reads its base and at most four numbers', () {
      // Mutation: accept a fifth number. It would be written past the row
      // into the next light's.
      final types =
          read(lightTypesSection, <Object?>[
                <String, Object?>{
                  'name': 'tube',
                  'base': 'spot',
                  'params': <Object?>[1, 2],
                },
              ])
              as List<DataLightType>;
      expect(types.single.base, LightType.spot);
      expect(types.single.params, <double>[1, 2]);
      expect(
        () => read(lightTypesSection, <Object?>[
          <String, Object?>{
            'name': 'tube',
            'params': <Object?>[1, 2, 3, 4, 5],
          },
        ]),
        throwsA(isA<DocumentFormatException>()),
      );
      expect(
        () => read(lightTypesSection, <Object?>[
          <String, Object?>{'name': 'acme.tube'},
        ]),
        throwsA(isA<DocumentFormatException>()),
        reason: 'the name is the plugin\'s own, and the id goes before it',
      );
    });

    test('a vertex layout is held to the engine\'s attributes', () {
      // Mutation: accept any attribute name. A stage reading `sway` would
      // be bound to nothing on every backend.
      final layouts =
          read(vertexLayoutsSection, <Object?>[
                <String, Object?>{
                  'name': 'ribbon',
                  'attributes': <Object?>['position', 'color'],
                },
              ])
              as List<DataVertexLayout>;
      expect(layouts.single.layout.floatsPerVertex, 7);
      expect(
        () => read(vertexLayoutsSection, <Object?>[
          <String, Object?>{
            'name': 'grass',
            'attributes': <Object?>['position', 'sway'],
          },
        ]),
        throwsA(
          isA<DocumentFormatException>().having(
            (e) => e.message,
            'message',
            contains('"sway"'),
          ),
        ),
      );
    });

    test('a level-of-detail table climbs', () {
      // Mutation: accept distances out of order. The policy would never
      // reach a level past the first one it skipped.
      final tables =
          read(lodTablesSection, <Object?>[
                <String, Object?>{
                  'name': 'trees',
                  'distances': <Object?>[10, 30],
                },
              ])
              as List<DataLodTable>;
      expect(tables.single.distances, <double>[10, 30]);
      expect(
        () => read(lodTablesSection, <Object?>[
          <String, Object?>{
            'name': 'trees',
            'distances': <Object?>[30, 10],
          },
        ]),
        throwsA(isA<DocumentFormatException>()),
      );
      expect(
        renderDataSections.map((s) => s.name),
        containsAll(<String>['lightTypes', 'vertexLayouts', 'lodTables']),
      );
    });
  });
}

final class _Throwing extends RenderProgram {
  @override
  List<String> get parameters => const <String>[];

  @override
  void run(RenderProgramFrame frame) =>
      throw const PluginException('the module trapped');
}
