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
  Snapshots({EcsWorld? world})
    : _scope = null,
      _parts = <SnapshotPart>[],
      _owners = <SnapshotPart, String>{} {
    if (world != null) add(WorldSnapshotPart(world));
  }

  Snapshots._scoped(Snapshots of, PluginScope scope)
    : _scope = scope,
      _parts = of._parts,
      _owners = of._owners;

  final PluginScope? _scope;
  final List<SnapshotPart> _parts;

  /// The namespace of the plugin that added each part it added; a part the
  /// application or the engine's own code added has none.
  final Map<SnapshotPart, String> _owners;

  @override
  List<String> get parts => <String>[for (final part in _parts) part.id];

  /// The version the part registered under [id] captures at, or null when
  /// no part is: what a run's own snapshot, which carries no version of its
  /// own, is wrapped with to go back in as that part.
  int? versionOf(String id) {
    for (final part in _parts) {
      if (part.id == id) return part.version;
    }
    return null;
  }

  /// Whether no part is registered.
  bool get isEmpty => _parts.isEmpty;

  /// Whether there is nothing to capture: every part a world with no entity
  /// and no resource in it, or a part whose capture is null — a genre with no
  /// run set. What a determinism check refuses to pass, since a check of
  /// nothing agrees with itself whatever the systems do.
  bool get holdsNothing => _parts.every(
    (part) => switch (part) {
      WorldSnapshotPart(:final world) => world.isEmpty,
      _ => part.capture() == null,
    },
  );

  @override
  Registration add(SnapshotPart part) {
    // A part is filed under its plugin's id, or a name in its namespace.
    if (_scope?.manifest case final manifest? when part.id != manifest.id) {
      if (manifest.nameProblem(part.id, what: 'the snapshot part')
          case final problem?) {
        throw PluginException(problem);
      }
    }
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
    if (_scope?.manifest.namespace case final owner?) _owners[part] = owner;
    final registration = Registration(() {
      _parts.remove(part);
      _owners.remove(part);
    });
    _scope?.track(registration);
    return registration;
  }

  /// Every part's state, in registration order, requiring the plugins whose
  /// state it holds ([Snapshot.requires]).
  @override
  Snapshot capture() {
    final data = <String, Object?>{
      for (final part in _parts)
        part.id: <String, Object?>{
          'version': part.version,
          'data': part.capture(),
        },
    };
    final requires = <String>{
      for (final part in _parts) ?_owners[part],
      for (final part in _parts)
        if (part is WorldSnapshotPart)
          ..._componentOwners(
            part.world,
            (data[part.id]! as Map<String, Object?>)['data'],
          ),
    };
    return Snapshot(data, requires: requires.toList()..sort());
  }

  /// The namespaces of the plugins whose components or resources [saved],
  /// a world's capture, holds a value of.
  static Iterable<String> _componentOwners(EcsWorld world, Object? saved) {
    if (saved is! Map) return const <String>[];
    bool holds(Object? rows, String id) =>
        rows is Map &&
        switch (rows[id]) {
          final Map<Object?, Object?> some => some.isNotEmpty,
          null => false,
          _ => true,
        };
    return <String>{
      for (final info in world.components.registered)
        if (info.declaredBy != _byTheApplication &&
            (holds(saved['components'], info.id) ||
                holds(saved['resources'], info.id)))
          _namespaceOf(info.declaredBy),
    };
  }

  /// What `ComponentInfo.declaredBy` says for a component nobody's plugin
  /// registered.
  static const String _byTheApplication = 'app';

  /// A plugin id's namespace, as `PluginManifest.namespace` reads it.
  static String _namespaceOf(String id) {
    final dot = id.indexOf('.');
    return dot < 0 ? id : id.substring(0, dot);
  }

  /// The namespaces of the plugins whose state this engine can take back:
  /// those that added a part, or registered a component, here.
  Set<String> get _installed => <String>{
    ..._owners.values,
    for (final part in _parts)
      if (part is WorldSnapshotPart)
        for (final info in part.world.components.registered)
          if (info.declaredBy != _byTheApplication)
            _namespaceOf(info.declaredBy),
  };

  /// Puts every part back to what [snapshot] holds.
  ///
  /// Throws a [SnapshotFormatException] naming the part when the snapshot was
  /// written by a newer version of it than this build reads: restoring half a
  /// state is worse than refusing the whole. Throws a [StateError] when the
  /// snapshot holds none of the registered parts, naming what it holds and
  /// what was looked for.
  @override
  void restore(covariant Snapshot snapshot) {
    // Before anything moves: a plugin's state with nobody to take it back
    // would be skipped, and the next save written without it.
    if (snapshot.requires.isNotEmpty) {
      final installed = _installed;
      final missing = <String>[
        for (final name in snapshot.requires)
          if (!installed.contains(name)) name,
      ];
      if (missing.isNotEmpty) {
        throw SnapshotFormatException(
          'the snapshot holds the state of ${missing.map((n) => '"$n"').join(', ')}, '
          'which this engine has no plugin of: install '
          '${missing.length == 1 ? 'it' : 'them'} and restore again, or '
          'that state would be lost',
        );
      }
    }
    final read = <(SnapshotPart, Object?, int)>[];
    for (final part in _parts) {
      final entry = snapshot.data[part.id];
      if (entry is! Map) continue;
      final version = switch (entry['version']) {
        final num n => switch (FormatSpec.wholeNumber(n)) {
          final int whole => whole,
          null => throw SnapshotFormatException(
            'the snapshot part "${part.id}" names version $n, which is not a '
            'whole number',
          ),
        },
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
        if (part.restoresFirst == first) {
          part.restore(SnapshotRestoreContext(data, version: version));
        }
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
///
/// **With the change stamps since [changesVersion]**: the step each component
/// was last set at (`EcsWorld.save(withChanges: true)`), so a system asking
/// `query().changed<T>(since:)` sees on a resimulated step what it saw on the
/// live one. A version-1 part restores with no stamps, as it always did; a
/// build that reads only 1 refuses a part at 2 rather than drop them.
///
/// **The digest leaves them out** ([digest]): every checkpoint a run recorded
/// before the stamps were captured is a digest of the world's `save()`, and
/// those keep verifying.
final class WorldSnapshotPart extends SnapshotPart {
  /// The part capturing and restoring [world].
  const WorldSnapshotPart(this.world);

  /// The part version from which the capture holds the change stamps.
  static const int changesVersion = 2;

  /// The world saved and restored.
  final EcsWorld world;

  @override
  String get id => 'world';

  @override
  int get version => changesVersion;

  @override
  Object? capture() => world.save(withChanges: true);

  @override
  int? digest() => StateDigest.of(world.save());

  @override
  void restore(SnapshotRestoreContext context) {
    final data = context.data;
    if (data is Map) world.restore(data.cast<String, Object?>());
  }
}
