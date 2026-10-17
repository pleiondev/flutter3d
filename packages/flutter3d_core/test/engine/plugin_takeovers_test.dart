/// What a plugin from outside the engine may take from it, and how the
/// policies several plugins register compose: a built-in step or an engine
/// stage only through a `RenderStepAddon` that declares it, a contributor
/// only its own, a frame resource only in its namespace; the pacing,
/// quality, level-of-detail and shadow policies as registrations, chained
/// in dependency order with null passing to the next.
///
///     dart test test/engine/plugin_takeovers_test.dart
///
/// Mutation: drop the `_outside` check from `RendererSteps.provide` and the
/// first test takes bloom over; answer every name in `_ConfinedLibrary`
/// and the stage test draws `Pbr` with the plugin's; sort `_Hooks` by when
/// a hook was added alone and the chain test hears the plugin first.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show TextureFormat;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

import '../support/install_refusal.dart';

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
  _Plugin(
    this.id,
    this.body, {
    this.touches = PluginTouches.view,
    this.dependsOn = const <String>[],
  });

  final String id;
  final void Function(PluginHost host) body;
  final PluginTouches touches;
  final List<String> dependsOn;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: touches,
    dependsOn: dependsOn,
  );

  @override
  void install(PluginHost host) => body(host);
}

/// An outside addon that takes bloom and the `Pbr` stage over.
final class _Bloomier extends RenderStepAddon {
  const _Bloomier()
    : super(
        id: 'acme_glow.bloom',
        provides: const <RenderStep>[],
        replaces: const <RenderStep>[RenderStep.bloom],
        replacesStages: const <String>['Pbr'],
      );
}

/// [_Bloomier] with a manifest of its own that forgot the permission.
final class _Forgetful extends RenderStepAddon {
  const _Forgetful()
    : super(
        id: 'acme_glow.forgetful',
        provides: const <RenderStep>[],
        replaces: const <RenderStep>[RenderStep.bloom],
      );

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'acme_glow.forgetful',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
  );
}

final class _Draws extends PassContributor {
  @override
  void encode(ContributorFrame frame) {}
}

/// A node that declares [id] while it runs.
final class _Declares extends RenderNode {
  _Declares(this.name, this.id);

  @override
  final String name;

  final String id;

  @override
  void setup(FrameGraphBuilder builder) => builder
    ..read(FrameResourceIds.hdrColor)
    ..write(FrameResourceIds.hdrColor);

  @override
  void execute(RenderFrame frame) {
    frame.resources.declare(
      ResourceDesc(id: ResourceId(id), format: TextureFormat.r8g8b8a8UNormInt),
    );
    frame.resources.provide(
      FrameResourceIds.hdrColor,
      frame.resources.texture(FrameResourceIds.hdrColor),
    );
  }
}

final class _Answers extends LodPolicy {
  const _Answers(this.level);

  final int? level;

  @override
  int? select(LodContext context) => level;
}

final class _Holds extends PacingPolicy {
  const _Holds(this.held);

  final bool? held;

  @override
  bool? hold(PacingContext context) => held;
}

final class _Row extends QualityPolicy {
  const _Row(this.row);

  final int? row;

  @override
  int? choose(QualityContext context) => row;
}

final class _Soft extends ShadowTechnique {
  const _Soft(this.name);

  @override
  final String name;

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;
}

Renderer _renderer() => Renderer.create(device: FakeBackend());

PluginManager _install(Renderer renderer, List<Flutter3dPlugin> plugins) =>
    PluginManager(
      loop: _Loop(),
      events: _Events(),
      registries: <PluginRegistry>[renderer.renderSteps],
    )..installAll(plugins);

Matcher _refused(List<String> saying) => isA<PluginException>().having(
  (PluginException e) => e.message,
  'message',
  allOf(<Matcher>[for (final word in saying) contains(word)]),
);

LodContext _lod() => LodContext(
  group: LodGroup(
    levels: <LodLevel>[
      LodLevel(
        node: MeshNode(
          DeviceMesh.upload(FakeBackend(), CuboidShape().build()),
          RenderMaterial(),
        ),
        maxScreenFraction: 1,
      ),
    ],
  ),
  camera: CameraNode(),
  choice: 0,
);

void main() {
  group('taking over what the engine draws', () {
    test('a built-in step is provided only by an addon declaring it', () {
      final renderer = _renderer();
      final refused = _install(renderer, <Flutter3dPlugin>[
        _Plugin(
          'acme_glow.glow',
          (host) => host.registry<RendererSteps>().provide(RenderStep.bloom),
        ),
      ]);
      expect(
        installRefusal(refused),
        _refused(<String>['"acme_glow.glow"', 'f3d.bloom', 'replaces']),
      );
      expect(renderer.renderSteps.providerOf(RenderStep.bloom), isNull);

      final declared = _renderer();
      final plugins = _install(declared, <Flutter3dPlugin>[const _Bloomier()]);
      expect(installRefusal(plugins), isNull);
      expect(
        declared.renderSteps.providerOf(RenderStep.bloom),
        'plugin "acme_glow.bloom"',
      );
      expect(
        const _Bloomier().manifest.permissions,
        contains(PluginPermission.replace),
      );
    });

    test('a declaration without the permission is refused', () {
      final renderer = _renderer();
      expect(
        installRefusal(
          _install(renderer, <Flutter3dPlugin>[const _Forgetful()]),
        ),
        _refused(<String>['"acme_glow.forgetful"', '"replace"']),
      );
      expect(renderer.renderSteps.providerOf(RenderStep.bloom), isNull);
    });

    test('an outside library answers its namespace and what it declared', () {
      final own = FakeShaderLibrary();
      final renderer = _renderer();
      final engines = renderer.shaders['Pbr'];
      _install(renderer, <Flutter3dPlugin>[
        _Plugin(
          'acme_glow.ink',
          (host) => host.registry<RendererSteps>().addMaterials(own),
        ),
      ]);
      expect(renderer.shaders['acme_glow__Ink'], same(own['acme_glow__Ink']));
      expect(renderer.shaders['Pbr'], same(engines));

      // What one addon declared is its own, not every plugin's.
      final replacing = _renderer();
      final mine = FakeShaderLibrary();
      _install(replacing, <Flutter3dPlugin>[
        const _Bloomier(),
        _Plugin(
          'acme_glow.stages',
          (host) => host.registry<RendererSteps>().addMaterials(mine),
          dependsOn: const <String>['acme_glow.bloom'],
        ),
      ]);
      expect(replacing.shaders['Pbr'], isNot(same(mine['Pbr'])));
    });

    test('the addon declaring a stage takes it over itself', () {
      final mine = FakeShaderLibrary();
      final renderer = _renderer();
      final plugins = _install(renderer, <Flutter3dPlugin>[const _Bloomier()]);
      expect(installRefusal(plugins), isNull);
      // The addon's own view: what `RendererSteps.addMaterials` sees when
      // the addon's subclass adds its library in `ready`.
      final scoped = renderer.renderSteps.forPlugin(_Scope(const _Bloomier()));
      scoped.addMaterials(mine);
      expect(renderer.shaders['Pbr'], same(mine['Pbr']));
      expect(renderer.shaders['Unlit'], isNot(same(mine['Unlit'])));
    });

    test('a contributor is taken out only by who added it', () {
      final renderer = _renderer();
      final draws = _Draws();
      _install(renderer, <Flutter3dPlugin>[
        _Plugin(
          'acme_glow.sparks',
          (host) => host.registry<RendererSteps>().addContributor(draws),
        ),
      ]);
      expect(
        () => renderer.renderSteps.removeContributor(draws),
        throwsA(_refused(<String>['the application', '"acme_glow.sparks"'])),
      );
      expect(renderer.renderSteps.contributors, contains(draws));
      expect(
        installRefusal(
          _install(_renderer(), <Flutter3dPlugin>[
            _Plugin(
              'acme_glow.editor',
              (host) => host.registry<RendererSteps>().addContributor(_Draws()),
              touches: PluginTouches.tooling,
            ),
          ]),
        ),
        _refused(<String>['"acme_glow.editor"', 'contributor']),
      );

      final other = _renderer();
      final mine = other.renderSteps.addContributor(_Draws());
      expect(other.renderSteps.removeContributor(mine), isTrue);
      expect(other.renderSteps.removeContributor(mine), isFalse);
    });

    test('a node declares no resource outside its own', () {
      final renderer = _renderer();
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      final scene = Scene()..add(camera);
      _install(renderer, <Flutter3dPlugin>[
        _Plugin(
          'acme_glow.declares',
          (host) => host.registry<RendererSteps>().addNode(
            _Declares('acme_glow.declares', 'f3d.hdr_color'),
            at: RenderAnchor.afterScene,
          ),
        ),
      ]);
      final result = renderer.render(
        width: 16,
        height: 16,
        scene: scene,
        views: <CameraView>[CameraView(camera: camera)],
      );
      expect(
        result.nodeFailures.single.error,
        _refused(<String>['"acme_glow.declares"', 'f3d.hdr_color']),
      );
    });
  });

  group('policies register and chain', () {
    test('the application first, then each plugin by dependency', () {
      final renderer = _renderer();
      _install(renderer, <Flutter3dPlugin>[
        _Plugin(
          'acme_lod.second',
          (host) =>
              host.registry<RenderHooks>().addLodPolicy(const _Answers(2)),
          dependsOn: const <String>['acme_lod.first'],
        ),
        _Plugin(
          'acme_lod.first',
          (host) =>
              host.registry<RenderHooks>().addLodPolicy(const _Answers(null)),
        ),
      ]);
      final hooks = renderer.hooks;
      // `first` passes, so `second` decides.
      expect(hooks.lodPolicy!.select(_lod()), 2);
      // The application's, added last, is asked first.
      final mine = hooks.addLodPolicy(const _Answers(0));
      expect(hooks.lodPolicy!.select(_lod()), 0);
      expect(hooks.lodPolicies.first, const _Answers(0));
      mine.cancel();
      expect(hooks.lodPolicy!.select(_lod()), 2);
    });

    test('a plugin\'s policies go with it', () {
      final renderer = _renderer();
      final plugins = _install(renderer, <Flutter3dPlugin>[
        _Plugin('acme_pace.all', (host) {
          host.registry<RenderHooks>()
            ..addLodPolicy(const _Answers(1))
            ..addPacingPolicy(const _Holds(true))
            ..addQualityPolicy(const _Row(1))
            ..addShadowTechnique(const _Soft('acme_pace.soft'));
        }),
      ]);
      final hooks = renderer.hooks;
      expect(hooks.lodPolicies, hasLength(1));
      expect(hooks.pacingPolicies, hasLength(1));
      expect(hooks.qualityPolicies, hasLength(1));
      expect(hooks.shadowTechniques, hasLength(1));
      plugins
        ..disable('acme_pace.all')
        ..applyPending(1);
      expect(hooks.lodPolicy, isNull);
      expect(hooks.pacingPolicy, isNull);
      expect(hooks.qualityPolicy, isNull);
      expect(hooks.shadowTechniques, isEmpty);
    });

    test(
      'a registered pacing policy holds a frame, after the application\'s',
      () {
        final renderer = _renderer();
        final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
        final scene = Scene()..add(camera);
        FrameResult draw() => renderer.render(
          width: 16,
          height: 16,
          scene: scene,
          views: <CameraView>[CameraView(camera: camera)],
        );
        renderer.hooks.addPacingPolicy(const _Holds(true));
        expect(draw().held, isFalse);
        expect(draw().held, isTrue);
        renderer.pacing = const FramePacing(policy: _Holds(false));
        expect(draw().held, isFalse);
      },
    );

    test('a registered quality policy picks the row', () {
      final hooks = _renderer().hooks..addQualityPolicy(const _Row(2));
      final table = QualityTable(
        deviceClass: DeviceClass.desktop,
        rows: <QualityRow>[
          for (final s in QualitySetting.grid.take(3))
            QualityRow(s, cost: 1.0, flip: 0.0),
        ],
      );
      final quality = AdaptiveQuality(
        table,
        settings: const AdaptiveQualitySettings(enabled: true),
        hooks: hooks,
      );
      quality.recordFrame(1000);
      expect(quality.index, 2);
    });

    test('a shadow technique is found by the filter that names it', () {
      final renderer = _renderer();
      final hooks = renderer.hooks;
      const named = ShadowFilter.custom(
        'acme_sun.soft',
        base: ShadowFilter.pcf,
      );
      expect(hooks.techniqueFor(named), ShadowTechnique.pcf);
      final plugins = _install(renderer, <Flutter3dPlugin>[
        _Plugin(
          'acme_sun.soft',
          (host) => host.registry<RenderHooks>().addShadowTechnique(
            const _Soft('acme_sun.soft'),
          ),
        ),
      ]);
      expect(installRefusal(plugins), isNull);
      expect(hooks.techniqueFor(named), const _Soft('acme_sun.soft'));
      // What the settings were given wins.
      expect(
        hooks.techniqueFor(
          const ShadowFilter.custom(
            'acme_sun.soft',
            base: ShadowFilter.pcf,
            technique: ShadowTechnique.evsm,
          ),
        ),
        ShadowTechnique.evsm,
      );
      expect(
        () => hooks.addShadowTechnique(const _Soft('pcss')),
        throwsA(isA<NameTakenException>()),
      );
      expect(
        installRefusal(
          _install(_renderer(), <Flutter3dPlugin>[
            _Plugin(
              'acme_sun.other',
              (host) => host.registry<RenderHooks>().addShadowTechnique(
                const _Soft('soft'),
              ),
            ),
          ]),
        ),
        _refused(<String>['"acme_sun.other"', 'the shadow technique']),
      );
    });
  });
}

/// The scope a plugin host would hand [plugin]'s registrations.
final class _Scope extends PluginScope {
  const _Scope(this.plugin);

  final Flutter3dPlugin plugin;

  @override
  PluginManifest get manifest => plugin.manifest;

  @override
  int get rank => 0;

  @override
  void track(Registration registration) {}
}
