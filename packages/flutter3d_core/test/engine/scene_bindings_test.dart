/// The renderer's half of a scene binding: a kind of node a plugin adds, a
/// component's fields driving a material's parameters between two steps,
/// and a data plugin's `bindings:` section installing into it (D37).
///
///     dart test test/engine/scene_bindings_test.dart
///
/// Mutation: have `SceneBindingContext.field` ignore [alpha] and the blend
/// test reads the step's value; drop `bindingsSection` from
/// `renderDataSections` and the section test finds it missing.
library;

import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show MaterialParameters;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

final class _Ember extends SceneNodeKind {
  const _Ember();

  @override
  String get name => 'acme_forge.ember';

  @override
  SceneNode create(SceneBindingContext context) =>
      SceneNode(name: 'ember ${context.entity}');
}

const SceneBindingSpec _heat = SceneBindingSpec(
  component: 'acme_forge.heat',
  nodeKind: 'acme_forge.ember',
  parameters: <String, String>{'temperature': 'glow'},
);

void main() {
  test('a binding resolves to its kind once the kind is added', () {
    final bindings = SceneBindings()..add(_heat);
    expect(bindings.resolve('acme_forge.heat'), isNull);
    bindings.addKind(const _Ember());
    final binding = bindings.resolve('acme_forge.heat')!;
    final node = binding.kind.create(
      SceneBindingContext(
        binding: binding,
        entity: 7,
        fields: const <String, Object?>{},
      ),
    );
    expect(node.name, 'ember 7');
    expect(() => bindings.add(_heat), throwsArgumentError);
  });

  test('a field drives a parameter, blended between two steps', () {
    final binding = SceneBinding(_heat, const _Ember());
    final context = SceneBindingContext(
      binding: binding,
      entity: 1,
      fields: const <String, Object?>{'temperature': 1000},
      previous: const <String, Object?>{'temperature': 600},
      alpha: 0.25,
    );
    expect(context.field('temperature'), 700.0);
    final parameters = MaterialParameters();
    binding.applyParameters(parameters, context);
    expect(parameters.uniforms['glow'], <double>[700.0]);
  });

  test('a data plugin\'s bindings install into the renderer\'s', () {
    expect(renderDataSections, contains(bindingsSection));
    final renderer = Renderer.create(device: FakeBackend());
    final context = const DataSectionContext(plugin: 'acme_forge');
    final read = bindingsSection.read(
      DataSectionRead(<Object?>[_heat.toJson()], context: context),
    );
    expect(bindingsSection.write(read), <Object?>[_heat.toJson()]);
    PluginManager(
      loop: _Loop(),
      events: _Events(),
      registries: <PluginRegistry>[renderer.renderSteps],
    ).installAll(<Flutter3dPlugin>[
      _Plugin('acme_forge', (host) {
        bindingsSection.install(
          DataSectionInstall(read, host: host, context: context),
        );
      }),
    ]);
    expect(renderer.sceneBindings.bindings.single.component, 'acme_forge.heat');
  });
}

final class _Plugin extends Flutter3dPlugin {
  _Plugin(this.id, this.body);

  final String id;
  final void Function(PluginHost host) body;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) => body(host);
}

final class _Loop extends LoopRegistry {
  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
    List<String> reads = const <String>[],
    List<String> writes = const <String>[],
  }) => Registration(() {});

  @override
  LoopRegistry forPlugin(PluginScope scope) => this;
}

final class _Events extends EventRegistry {
  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}
