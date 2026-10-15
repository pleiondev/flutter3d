/// A plugin's registrations with a renderer are in its namespace, and its
/// lighting models come in through the engine's own table (D23, D43).
///
///     dart test test/engine/plugin_namespace_test.dart
///
/// Mutation: take `_inNamespace` out of `addStep` and the first test
/// installs a step called `glow`; drop `companions` from `RendererSteps`
/// and the lighting test finds no `LightingModels`.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show TextureFormat;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

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

/// A plugin that does whatever it is handed in `install`.
final class _Plugin extends Flutter3dPlugin {
  _Plugin(this.id, this.body, {this.touches = PluginTouches.view});

  final String id;
  final void Function(PluginHost host) body;
  final PluginTouches touches;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: touches,
  );

  @override
  void install(PluginHost host) => body(host);
}

final class _Node extends RenderNode {
  _Node(this.name, {this.makes});

  @override
  final String name;

  final ResourceDesc? makes;

  @override
  void setup(FrameGraphBuilder builder) {
    builder.read(FrameResourceIds.hdrColor);
    if (makes case final desc?) builder.create(desc);
    builder.write(FrameResourceIds.hdrColor);
  }

  @override
  void execute(RenderFrame frame) {}
}

Renderer _renderer() => Renderer.create(device: FakeBackend());

void _install(Renderer renderer, Flutter3dPlugin plugin) => PluginManager(
  loop: _Loop(),
  events: _Events(),
  registries: <PluginRegistry>[renderer.renderSteps],
).installAll(<Flutter3dPlugin>[plugin]);

Matcher _refusedNaming(String name) => throwsA(
  isA<PluginException>().having(
    (PluginException e) => e.message,
    'message',
    allOf(contains('"$name"'), contains('acme_glow.<name>')),
  ),
);

void main() {
  test('a step outside the plugin\'s namespace is refused at install', () {
    final renderer = _renderer();
    expect(
      () => _install(
        renderer,
        _Plugin(
          'acme_glow.glow',
          (host) =>
              host.registry<RendererSteps>().addStep(const RenderStep('glow')),
        ),
      ),
      _refusedNaming('glow'),
    );
    expect(renderer.renderSteps.named('glow'), isNull);

    final ok = _renderer();
    _install(
      ok,
      _Plugin(
        'acme_glow.glow',
        (host) => host.registry<RendererSteps>().addStep(
          const RenderStep('acme_glow.glow'),
        ),
      ),
    );
    expect(ok.renderSteps.named('acme_glow.glow'), isNotNull);
  });

  test('a node, and a resource it makes, are held to the namespace', () {
    expect(
      () => _install(
        _renderer(),
        _Plugin(
          'acme_glow.glow',
          (host) => host.registry<RendererSteps>().addNode(_Node('blur')),
        ),
      ),
      _refusedNaming('blur'),
    );
    expect(
      () => _install(
        _renderer(),
        _Plugin(
          'acme_glow.glow',
          (host) => host.registry<RendererSteps>().addNode(
            _Node(
              'acme_glow.blur',
              makes: const ResourceDesc(
                id: ResourceId('scratch'),
                format: TextureFormat.r16g16b16a16Float,
              ),
            ),
          ),
        ),
      ),
      _refusedNaming('scratch'),
    );
  });

  test('an anchor and a settings slot of the plugin\'s own likewise', () {
    expect(
      () => _install(
        _renderer(),
        _Plugin(
          'acme_glow.glow',
          (host) => host.registry<RendererSteps>().addAnchor(
            const RenderAnchor.after(RenderAnchor.afterBloom, 'after glow'),
          ),
        ),
      ),
      _refusedNaming('after glow'),
    );
    // The engine's own slots are what an addon provides; they need none.
    final renderer = _renderer();
    _install(
      renderer,
      _Plugin(
        'acme_glow.glow',
        (host) =>
            host.registry<RendererSteps>().addSettings(SettingsSlot.bloom),
      ),
    );
    expect(
      renderer.renderSteps.settingsNamed(SettingsSlot.bloom.id),
      isNotNull,
    );
  });

  test('a plugin that touches only tooling adds no step, node or stage', () {
    // Mutation: hold a tooling plugin to the view's rules alone. An editor
    // plugin could add to the frame a game draws without it, and the game
    // would draw differently in the editor than on its own.
    for (final (what, add) in <(String, void Function(RendererSteps))>[
      (
        'the render step',
        (steps) => steps.addStep(const RenderStep('acme_glow.glow')),
      ),
      ('the node', (steps) => steps.addNode(_Node('acme_glow.blur'))),
      ('stages', (steps) => steps.addMaterials(FakeBackend().shaders)),
    ]) {
      final renderer = _renderer();
      expect(
        () => _install(
          renderer,
          _Plugin(
            'acme_glow.editor',
            (host) => add(host.registry<RendererSteps>()),
            touches: PluginTouches.tooling,
          ),
        ),
        throwsA(
          isA<PluginException>().having(
            (PluginException e) => e.message,
            'message',
            allOf(contains('"acme_glow.editor"'), contains(what)),
          ),
        ),
        reason: what,
      );
      expect(renderer.renderSteps.added, isEmpty);
    }
  });

  test('the application names what it likes', () {
    final renderer = _renderer();
    renderer.renderSteps.addStep(const RenderStep('glow'));
    expect(renderer.renderSteps.named('glow'), isNotNull);
  });

  test('a lighting model comes in through the engine\'s own table', () {
    const ink = LightingModel('Ink', 'acme_glow__Ink');
    final renderer = _renderer();
    _install(
      renderer,
      _Plugin(
        'acme_glow.glow',
        (host) => host.registry<LightingModels>().register(ink),
      ),
    );
    expect(renderer.lightingModels.named('acme_glow.Ink'), same(ink));
    expect(_renderer().lightingModels.named('acme_glow.Ink'), isNull);

    expect(
      () => _install(
        _renderer(),
        _Plugin(
          'acme_glow.glow',
          (host) => host.registry<LightingModels>().register(
            const LightingModel('Ink', 'Ink'),
          ),
        ),
      ),
      throwsA(isA<PluginException>()),
    );
  });

  test(
    'a plugin\'s model is <namespace>.<Name>, its stage the dot made __',
    () {
      // Mutation: drop the `__` test from `LightingModels.register`, and
      // `acme_glow.in__k` comes in under a stage another plugin could spell.
      expect(
        const LightingModel('Ink', 'acme_glow__Ink').name,
        'acme_glow.Ink',
      );
      expect(LightingModel.shaderNameOf('acme_glow.Ink'), 'acme_glow__Ink');
      expect(LightingModel.pbr.name, 'Pbr');
      for (final stage in <String>[
        // The stage name a plugin's model had before the dot.
        'acme_glow_Ink',
        // Another plugin's namespace.
        'acme__Ink',
        // `__` inside the model's own name.
        'acme_glow__In__k',
        // A model name starting with `_`, which `__` would swallow.
        'acme_glow___Ink',
      ]) {
        expect(
          () => _install(
            _renderer(),
            _Plugin(
              'acme_glow.glow',
              (host) => host.registry<LightingModels>().register(
                LightingModel('Ink', stage),
              ),
            ),
          ),
          throwsA(isA<PluginException>()),
          reason: stage,
        );
      }
    },
  );

  test('a file\'s word from before the dot finds the plugin\'s model', () {
    const ink = LightingModel('Ink', 'acme_glow__Ink');
    final renderer = _renderer();
    _install(
      renderer,
      _Plugin(
        'acme_glow.glow',
        (host) => host.registry<LightingModels>().register(ink),
      ),
    );
    // Mutation: drop the alias loop from `LightingModels.named`, and a
    // `.fmat` written before the dot opens with the scene's model.
    expect(renderer.lightingModels.named('acme_glow_Ink'), same(ink));
    expect(renderer.lightingModels.named('acme_glow__Ink'), same(ink));
    expect(renderer.lightingModels.named('acme_glow_ink'), isNull);
  });
}
