/// A snapshot names the plugins whose state it holds, and an engine without
/// one of them refuses it rather than dropping that state.
///
///     dart test test/plugin_state_requires_test.dart
///
/// Mutation: write no `requires` in `Snapshots.capture`, and the save of a
/// run with `acme` installed opens in an engine without it, skips `acme`'s
/// part and component, and the next save is written without them.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A plugin's own component.
final class _Heat {
  _Heat(this.kelvin);

  int kelvin;

  static final ComponentCodec<_Heat> codec = ComponentCodec<_Heat>.of(
    id: 'acme.heat',
    encode: (heat) => heat.kelvin,
    decode: (context) => _Heat(context.data! as int),
  );
}

/// The application's own component.
final class _Score {
  _Score(this.points);

  int points;

  static final ComponentCodec<_Score> codec = ComponentCodec<_Score>.of(
    id: 'game.score',
    encode: (score) => score.points,
    decode: (context) => _Score(context.data! as int),
  );
}

/// A plugin keeping a count of its own in a snapshot part, and a component.
final class _Acme extends Flutter3dPlugin {
  _Acme({this.part = true});

  final bool part;
  int count = 0;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'acme.stove',
    apiVersion: PluginApiVersion.current,
  );

  @override
  void install(PluginHost host) {
    if (part) {
      host.registry<SnapshotRegistry>().add(
        SnapshotPart.of(
          id: 'acme.count',
          capture: () => count,
          restore: (context) => count = context.data! as int,
        ),
      );
    }
    host.registry<ComponentRegistry>().register<_Heat>(_Heat.codec);
  }
}

EngineLoop _loop(List<Flutter3dPlugin> plugins) {
  final loop = EngineLoop(input: InputState(), plugins: plugins);
  loop.world.components.register<_Score>(_Score.codec);
  loop.world.set(loop.world.spawn(), _Score(3));
  return loop;
}

void main() {
  test('a capture requires the plugins whose part or component it holds', () {
    final acme = _Acme()..count = 7;
    final loop = _loop(<Flutter3dPlugin>[acme]);
    loop.world.set(loop.world.spawn(), _Heat(300));
    final saved = loop.capture();
    // The plugin's namespace, once, for its part and its component; never
    // the application's own `game.score`.
    expect(saved.requires, <String>['acme']);
    expect(saved.toJson()['requires'], <String>['acme']);
    final read = Snapshot.fromJson(saved.toJson());
    expect(read.requires, <String>['acme']);

    // Restored where it is installed, it comes back whole.
    final again = _Acme();
    final other = _loop(<Flutter3dPlugin>[again])..restore(read);
    expect(again.count, 7);
    expect(other.world.query().having<_Heat>().entities, hasLength(1));
  });

  test('an engine without the plugin refuses the snapshot, naming it', () {
    final loop = _loop(<Flutter3dPlugin>[_Acme()..count = 2]);
    final saved = Snapshot.fromJson(loop.capture().toJson());
    final without = _loop(const <Flutter3dPlugin>[]);
    expect(
      () => without.restore(saved),
      throwsA(
        isA<SnapshotFormatException>().having(
          (SnapshotFormatException e) => e.message,
          'message',
          contains('"acme"'),
        ),
      ),
    );
    // Nothing moved before the refusal.
    expect(
      without.world
          .get<_Score>(without.world.query().having<_Score>().entities.single)!
          .points,
      3,
    );
  });

  test('a component alone requires its plugin only while a body holds it', () {
    final loop = _loop(<Flutter3dPlugin>[_Acme(part: false)]);
    expect(loop.capture().requires, isEmpty);
    loop.world.set(loop.world.spawn(), _Heat(280));
    expect(loop.capture().requires, <String>['acme']);
    // A snapshot of the engine and the application alone requires nothing,
    // and is written as it was.
    final plain = _loop(const <Flutter3dPlugin>[]).capture();
    expect(plain.requires, isEmpty);
    expect(plain.toJson()['requires'], isEmpty);
  });
}
