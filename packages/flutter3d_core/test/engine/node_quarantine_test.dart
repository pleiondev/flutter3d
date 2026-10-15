/// A node a plugin placed that throws is quarantined and the frame goes on;
/// a node's registration disposes it; a name taken is a
/// `NameTakenException`.
///
///     dart test test/engine/node_quarantine_test.dart
///
/// Mutation: rethrow from the per-node catch in `Renderer.render` and the
/// first test loses the frame; drop `failed:` from the frame's compile and
/// the throwing node runs, and throws, every frame; call nothing on cancel
/// in `RendererSteps.addNode` and the fourth test finds the node undisposed.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show TextureFormat;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        BusChannel,
        BusEvent,
        EventCodec,
        EventDeclaration,
        EventHandler,
        EventRegistry,
        Flutter3dPlugin,
        LoopPhase,
        LoopRegistry,
        LoopSystem,
        NameTakenException,
        PluginApiVersion,
        PluginHost,
        PluginManager,
        PluginManifest,
        PluginRegistry,
        PluginScope,
        PluginTouches,
        Registration,
        RenderAnchor;
import 'package:test/test.dart';

const ResourceId _glow = ResourceId('acme.glow');

/// Writes a resource of its own and, while [throws], throws halfway.
final class _Glow extends RenderNode {
  _Glow({this.throws = true});

  bool throws;
  int ran = 0;
  int disposed = 0;

  @override
  String get name => 'acme.glow';

  @override
  void setup(FrameGraphBuilder builder) {
    builder
      ..read(FrameResourceIds.hdrColor)
      ..write(FrameResourceIds.hdrColor)
      ..create(
        const ResourceDesc(id: _glow, format: TextureFormat.r8g8b8a8UNormInt),
      );
  }

  @override
  void execute(RenderFrame frame) {
    ran++;
    if (throws) throw StateError('the glow broke');
    frame.resources.provide(
      FrameResourceIds.hdrColor,
      frame.resources.texture(FrameResourceIds.hdrColor),
    );
  }

  @override
  void dispose() => disposed++;
}

/// Reads what the glow makes, as a plugin's composite would.
final class _UsesGlow extends RenderNode {
  int ran = 0;

  @override
  String get name => 'acme.uses_glow';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    _glow,
    FrameResourceIds.hdrColor,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {
    ran++;
    frame.resources.provide(
      FrameResourceIds.hdrColor,
      frame.resources.texture(FrameResourceIds.hdrColor),
    );
  }
}

final class _Acme extends Flutter3dPlugin {
  _Acme(this.glow);

  final _Glow glow;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'acme',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) =>
      host.registry<RendererSteps>().addNode(glow, at: RenderAnchor.afterScene);
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
    EventCodec<T>? codec,
    String? description,
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

typedef _Stage = ({Renderer renderer, Scene scene, CameraNode camera});

_Stage _stage() {
  final device = FakeBackend();
  final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        RenderMaterial(),
      ),
    )
    ..add(camera);
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

FrameResult _draw(_Stage it) => it.renderer.render(
  width: 32,
  height: 24,
  scene: it.scene,
  views: <CameraView>[CameraView(camera: it.camera)],
);

void main() {
  test('a throwing plugin node is quarantined, its plugin named, and the '
      'frame goes on', () {
    final it = _stage();
    final glow = _Glow();
    final reader = _UsesGlow();
    PluginManager(
      loop: _Loop(),
      events: _Events(),
      registries: <PluginRegistry>[it.renderer.renderSteps],
    ).installAll(<Flutter3dPlugin>[_Acme(glow)]);
    // The application's nodes at an anchor come before the plugins', so a
    // reader of the glow says it runs after it.
    it.renderer.renderSteps.addNode(
      reader,
      at: RenderAnchor.afterScene,
      after: const <String>['acme.glow'],
    );

    final first = _draw(it);
    expect(glow.ran, 1);
    expect(first.nodeFailures, hasLength(1));
    final failure = first.nodeFailures.single;
    expect(failure.node, 'acme.glow');
    expect(failure.plugin, 'acme');
    expect(failure.owner, 'plugin "acme"');
    expect(failure.error, isA<StateError>());
    expect(
      first.skipped.where((s) => s.reason == PassSkip.failed).single.failure,
      same(failure),
    );
    // The frame was drawn to the end: the engine's passes after it ran.
    final ran = <String>{for (final pass in first.passes) pass.name};
    expect(ran, contains('composite'));

    // From the next frame on it is left out, and what read its output too.
    final second = _draw(it);
    expect(glow.ran, 1);
    expect(second.nodeFailures, isEmpty);
    final skipped = <String, SkippedPass>{
      for (final skip in second.skipped) skip.name: skip,
    };
    expect(skipped['acme.glow']!.reason, PassSkip.failed);
    expect(skipped['acme.glow']!.failure!.plugin, 'acme');
    expect(skipped['acme.uses_glow']!.reason, PassSkip.starved);
    // It ran in the frame the glow threw in, reading the glow's resource as
    // a blank, and not since.
    expect(reader.ran, 1);
  });

  test('the application\'s node is quarantined too, and placing it again '
      'lets it run', () {
    final it = _stage();
    final glow = _Glow();
    final added = it.renderer.renderSteps.addNode(
      glow,
      at: RenderAnchor.afterScene,
    );
    expect(_draw(it).nodeFailures.single.owner, 'the application');
    _draw(it);
    expect(glow.ran, 1);

    added.cancel();
    glow.throws = false;
    it.renderer.renderSteps.addNode(glow, at: RenderAnchor.afterScene);
    final again = _draw(it);
    expect(again.nodeFailures, isEmpty);
    expect(glow.ran, 2);
  });

  test('a frame with no node of a plugin\'s reports no failure', () {
    expect(_draw(_stage()).nodeFailures, isEmpty);
  });

  test('cancelling a registration disposes the node', () {
    final it = _stage();
    final glow = _Glow(throws: false);
    final added = it.renderer.renderSteps.addNode(
      glow,
      at: RenderAnchor.afterScene,
    );
    expect(glow.disposed, 0);
    added.cancel();
    // No frame was drawn, so nothing in flight can be using it.
    expect(glow.disposed, 1);

    final drawn = _Glow(throws: false);
    final again = it.renderer.renderSteps.addNode(
      drawn,
      at: RenderAnchor.afterScene,
    );
    _draw(it);
    again.cancel();
    // Kept until the frames in flight have finished with it.
    expect(drawn.disposed, 0);
    for (var i = 0; i < 4; i++) {
      _draw(it);
    }
    expect(drawn.disposed, 1);
  });

  test('a name taken is a NameTakenException naming who has it', () {
    final steps = _stage().renderer.renderSteps
      ..addNode(_Glow(), at: RenderAnchor.afterScene);
    expect(
      () => steps.addNode(_Glow(), at: RenderAnchor.afterBloom),
      throwsA(
        isA<NameTakenException>()
            .having((e) => e.name, 'name', 'acme.glow')
            .having((e) => e.owner, 'owner', 'the application'),
      ),
    );
    expect(
      () => steps.addStep(RenderStep.bloom),
      throwsA(isA<NameTakenException>()),
    );
  });
}
