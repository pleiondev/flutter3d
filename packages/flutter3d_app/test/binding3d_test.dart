/// `Binding3D`: the simulation's components shown as the renderer's scene
/// bindings say (D37) — a node per entity, placed, blended and driven by
/// its fields, and taken away or hidden as the binding's lifetime says.
///
///     flutter test test/binding3d_test.dart
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_core/flutter3d_core.dart'
    show SceneBindingContext, SceneNodeKind;
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

/// How hot a body is, in kelvin.
final class _Heat {
  _Heat(this.kelvin);

  double kelvin;

  static final ComponentCodec<_Heat> codec = ComponentCodec<_Heat>.of(
    id: 'acme.heat',
    encode: (heat) => <String, Object?>{'temperature': heat.kelvin},
    decode: (data, _) =>
        data is Map ? _Heat((data['temperature']! as num).toDouble()) : null,
  );
}

/// A kind of node that remembers what it was told.
final class _Ember extends SceneNodeKind {
  _Ember(this.device);

  final GraphicsDevice device;

  /// The temperature each update read, blended as the binding says.
  final List<double> read = <double>[];

  @override
  String get name => 'acme.ember';

  @override
  SceneNode create(SceneBindingContext context) => MeshNode(
    DeviceMesh.upload(device, CuboidShape().build()),
    RenderMaterial(),
    name: 'ember ${context.entity}',
  );

  @override
  void update(SceneBindingContext context) =>
      read.add((context.field('temperature')! as num).toDouble());
}

/// A scene showing the heat of one body at (1, 2, 3) that warms by a
/// hundred kelvin a step, whose heat is taken off at [loseAt] and put back
/// at [regainAt], under [lifetime].
Widget _scene({
  required FakeBackend device,
  required _Ember kind,
  required void Function(Flutter3dEngine engine) onEngine,
  BindingLifetime lifetime = BindingLifetime.component,
  int? loseAt,
  int? regainAt,
  RenderMaterial? Function(String id)? materials,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 32,
    height: 24,
    child: Scene3D(
      device: device,
      presenter: _noPresenter,
      onCreated: (controller) {
        controller.renderer.sceneBindings
          ..addKind(kind)
          ..add(
            SceneBindingSpec(
              component: 'acme.heat',
              nodeKind: 'acme.ember',
              material: 'acme.glowing',
              parameters: const <String, String>{'temperature': 'glow'},
              lifetime: lifetime,
            ),
          );
        final world = controller.engine.loop.world;
        world.components.register<_Heat>(_Heat.codec, published: true);
        final body = world.spawn();
        world
          ..set<_Heat>(body, _Heat(300))
          ..set<WorldPosition>(body, const WorldPosition(1, 2, 3));
        controller.engine.loop.addSystem('acme.warm', LoopPhase.rules, (
          LoopContext context,
        ) {
          world.get<_Heat>(body)?.kelvin += 100;
          if (context.step == loseAt) world.remove<_Heat>(body);
          if (context.step == regainAt) world.set<_Heat>(body, _Heat(300));
        });
        onEngine(controller.engine);
      },
      children: <Widget>[Binding3D(materials: materials)],
    ),
  ),
);

/// Pumps [count] refreshes of a 60 Hz display.
Future<void> _refreshes(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// The ember in [engine]'s scene, or null.
MeshNode? _ember(Flutter3dEngine engine) {
  MeshNode? found;
  engine.scene.root.traverse((SceneNode node) {
    if (node is MeshNode && (node.name ?? '').startsWith('ember ')) {
      found = node;
    }
  });
  return found;
}

void main() {
  testWidgets('a bound component is a node where its entity is, driven by '
      'its fields', (tester) async {
    // Mutation: skip `SceneBinding.applyParameters` in `Binding3D`. The
    // node's own parameters then stay null, and the glow the temperature
    // drives never changes.
    final device = FakeBackend();
    final kind = _Ember(device);
    final glowing = RenderMaterial(name: 'acme.glowing');
    Flutter3dEngine? engine;
    await tester.pumpWidget(
      _scene(
        device: device,
        kind: kind,
        onEngine: (e) => engine = e,
        materials: (id) => id == 'acme.glowing' ? glowing : null,
      ),
    );
    await tester.pump();
    await _refreshes(tester, 6);
    final ember = _ember(engine!)!;
    expect(ember.localMatrix.getTranslation().x, closeTo(1.0, 1e-6));
    expect(ember.localMatrix.getTranslation().y, closeTo(2.0, 1e-6));
    expect(ember.localMatrix.getTranslation().z, closeTo(3.0, 1e-6));
    expect(ember.material, same(glowing));
    expect(kind.read, isNotEmpty);
    final temperature = kind.read.last;
    // Blended between the last two steps: never past the newest.
    final newest = 300.0 + 100.0 * engine!.loop.step;
    expect(temperature, lessThanOrEqualTo(newest));
    expect(temperature, greaterThanOrEqualTo(newest - 100.0));
    // Held in single precision, as the GPU reads it.
    expect(
      ember.parameters!.uniforms['glow']!.single,
      closeTo(temperature, 1e-3),
    );
  });

  testWidgets('a component lost takes its node away', (tester) async {
    // Mutation: return false for every key in `_forgetGone`. The ember of a
    // body that stopped being hot is left glowing in the scene.
    final device = FakeBackend();
    Flutter3dEngine? engine;
    await tester.pumpWidget(
      _scene(
        device: device,
        kind: _Ember(device),
        onEngine: (e) => engine = e,
        loseAt: 4,
      ),
    );
    await tester.pump();
    await _refreshes(tester, 3);
    expect(_ember(engine!), isNotNull);
    await _refreshes(tester, 6);
    expect(_ember(engine!), isNull);
  });

  testWidgets('under the entity lifetime it is hidden, and shown again', (
    tester,
  ) async {
    // Mutation: drop the `BindingLifetime.entity` branch in `_forgetGone`.
    // The node is then taken away and made again, and the one a game held
    // is no longer the one drawn.
    final device = FakeBackend();
    Flutter3dEngine? engine;
    await tester.pumpWidget(
      _scene(
        device: device,
        kind: _Ember(device),
        onEngine: (e) => engine = e,
        lifetime: BindingLifetime.entity,
        loseAt: 4,
        regainAt: 10,
      ),
    );
    await tester.pump();
    await _refreshes(tester, 3);
    final ember = _ember(engine!)!;
    expect(ember.isVisible, isTrue);
    await _refreshes(tester, 3);
    expect(_ember(engine!), same(ember));
    expect(ember.isVisible, isFalse);
    await _refreshes(tester, 8);
    expect(_ember(engine!), same(ember));
    expect(ember.isVisible, isTrue);
  });

  testWidgets('the widget gone takes its nodes with it', (tester) async {
    final device = FakeBackend();
    Flutter3dEngine? engine;
    await tester.pumpWidget(
      _scene(device: device, kind: _Ember(device), onEngine: (e) => engine = e),
    );
    await tester.pump();
    await _refreshes(tester, 3);
    final ember = _ember(engine!)!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ember.parent, isNull);
  });
}
