/// The engine's [SnapshotRegistry]: every part of the state, captured and
/// restored the one way.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../save/snapshot.dart';
import '../save/state_digest.dart';
import 'ecs_world.dart';

/// Every [SnapshotPart] of one engine, and the one way a state is captured,
/// restored and digested.
///
/// **The single path** (item 27): `EngineLoop.rewindTo`, the debug
/// double-step check (`DeterminismCheck` with no functions of its own), a
/// rollback, a replay's checkpoints and the editor's scrub all call [capture]
/// and [restore] here. A plugin that keeps state outside the world adds a
/// part through `host.registry<SnapshotRegistry>()`, and every one of those
/// uses covers it from then on.
///
/// ## The shape
///
/// A [Snapshot] whose data has one entry per part, by id, holding
/// `{'version': n, 'data': …}`. A part that is not registered when a snapshot
/// is restored is skipped, and a registered part missing from it is left as
/// it is — the same leniency `EcsWorld.restore` has about components. **A
/// snapshot that holds none of the registered parts is refused**: it was
/// taken of something else — a genre's own `save()`, another engine — and
/// restoring it would leave everything where it was while the caller went on
/// as if it had moved.
final class Snapshots extends SnapshotRegistry {
  /// A registry whose first part is [world], under `'world'`.
  Snapshots({EcsWorld? world}) : _scope = null, _parts = <SnapshotPart>[] {
    if (world != null) add(WorldSnapshotPart(world));
  }

  Snapshots._scoped(Snapshots of, PluginScope scope)
    : _scope = scope,
      _parts = of._parts;

  final PluginScope? _scope;
  final List<SnapshotPart> _parts;

  @override
  List<String> get parts => <String>[for (final part in _parts) part.id];

  /// Whether no part is registered.
  bool get isEmpty => _parts.isEmpty;

  /// Whether there is nothing to capture: no part but a world with no
  /// entity and no resource in it. What a determinism check refuses to
  /// pass, since a check of nothing agrees with itself whatever the systems
  /// do.
  bool get holdsNothing =>
      _parts.every((part) => part is WorldSnapshotPart && part.world.isEmpty);

  @override
  Registration add(SnapshotPart part) {
    for (final existing in _parts) {
      if (existing.id == part.id) {
        throw ArgumentError.value(
          part.id,
          'part.id',
          'a snapshot part named "${part.id}" is already registered; a part '
              'id is unique in one engine, so prefix it with the plugin id',
        );
      }
    }
    _parts.add(part);
    final registration = Registration(() => _parts.remove(part));
    _scope?.track(registration);
    return registration;
  }

  /// Every part's state, in registration order.
  @override
  Snapshot capture() => Snapshot(<String, Object?>{
    for (final part in _parts)
      part.id: <String, Object?>{
        'version': part.version,
        'data': part.capture(),
      },
  });

  /// Puts every part back to what [snapshot] holds.
  ///
  /// Throws a [SnapshotFormatException] naming the part when the snapshot was
  /// written by a newer version of it than this build reads: restoring half a
  /// state is worse than refusing the whole. Throws a [StateError] when the
  /// snapshot holds none of the registered parts, naming what it holds and
  /// what was looked for.
  @override
  void restore(covariant Snapshot snapshot) {
    final read = <(SnapshotPart, Object?, int)>[];
    for (final part in _parts) {
      final entry = snapshot.data[part.id];
      if (entry is! Map) continue;
      final version = switch (entry['version']) {
        final num n => n.toInt(),
        _ => 1,
      };
      if (version > part.version) {
        throw SnapshotFormatException(
          'the snapshot part "${part.id}" was written at version $version and '
          'this build reads up to ${part.version}: update the plugin that '
          'registers it',
        );
      }
      read.add((part, entry['data'], version));
    }
    if (read.isEmpty && _parts.isNotEmpty) {
      throw StateError(
        'the snapshot restores none of this engine\'s parts: it holds '
        '${snapshot.data.keys.isEmpty ? 'nothing' : snapshot.data.keys.join(', ')}'
        ' and the parts are ${parts.join(', ')}. A snapshot for the loop is '
        'one the loop captured (EngineLoop.capture), not a run\'s own save',
      );
    }
    // A frame the others are relative to goes back first — a physics world's
    // origin before the bodies written in it.
    for (final first in <bool>[true, false]) {
      for (final (part, data, version) in read) {
        if (part.restoresFirst == first) part.restore(data, version);
      }
    }
  }

  /// A number that differs when any part's state does: each part's own
  /// digest where it has one, the digest of its capture otherwise.
  @override
  int digest() {
    final hash = StateDigest();
    for (final part in _parts) {
      hash
        ..add(part.id)
        ..add(part.digest() ?? StateDigest.of(part.capture()));
    }
    return hash.value;
  }

  @override
  SnapshotRegistry forPlugin(PluginScope scope) =>
      Snapshots._scoped(this, scope);
}

/// An [EcsWorld] as a [SnapshotPart]: its `save()` and `restore()`.
final class WorldSnapshotPart extends SnapshotPart {
  const WorldSnapshotPart(this.world);

  final EcsWorld world;

  @override
  String get id => 'world';

  @override
  Object? capture() => world.save();

  @override
  void restore(Object? data, int version) {
    if (data is Map) world.restore(data.cast<String, Object?>());
  }
}
