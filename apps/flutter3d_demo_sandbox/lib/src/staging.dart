import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_game/flutter3d_game.dart'
    show Bindings, DesktopInput, InputSource, LevelWalk;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:vector_math/vector_math.dart';

import 'palette.dart';

/// The two things this game does that no other does.
abstract final class SandboxActions {
  /// Takes out the block looked at.
  static const GameAction dig = GameAction('dig');

  /// Puts the hotbar's block against the face looked at.
  static const GameAction place = GameAction('place');
}

/// The keys: walking as every game here walks, Q to dig and E to place —
/// E taken back from `use`, which nothing here is.
Bindings sandboxBindings() => DesktopInput.defaultBindings()
  ..bind(InputSource.key(LogicalKeyboardKey.keyQ.keyId), SandboxActions.dig)
  ..bind(InputSource.key(LogicalKeyboardKey.keyE.keyId), SandboxActions.place)
  ..bind(InputSource.key(LogicalKeyboardKey.keyF.keyId), SandboxActions.place);

/// The number row, one key a hotbar slot.
Map<LogicalKeyboardKey, int> sandboxSlotKeys() => <LogicalKeyboardKey, int>{
  for (final (i, key) in const <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ].indexed)
    if (i < hotbar.length) key: i,
};

/// The hills every new world is, and every save is a delta against.
const VoxelTerrain sandboxTerrain = VoxelTerrain(seed: 2026);

/// The name the world is saved under in the game's storage.
const String sandboxSaveName = 'world.json';

/// One sandbox being played: the blocks, the physics they collide in, the
/// navigation kept on them, and the body walking them.
///
/// **The one place a run is assembled**, for the repository's rule that a
/// game answers "what does a level contain" once: the application and the
/// tests both build a run through [SandboxRun.new], [SandboxRun.fresh] or
/// [SandboxRun.open], and nothing else adds a collider or bakes a mesh.
///
/// It holds no device and no scene. What the screen needs from an edit is
/// which chunks to draw again, and [takeStaleSurfaces] hands that over.
final class SandboxRun {
  /// A run over [blocks], its physics on [backend] — the run's own, chosen
  /// once in `main` — with the body at [at] facing [yaw], or on the middle
  /// of the world when not given.
  SandboxRun(
    this.blocks, {
    PhysicsBackend? backend,
    Vector3? at,
    double yaw = 0.0,
    double pitch = 0.0,
    this.slot = 0,
  }) {
    // Attached before anything collides: the core mirrors the world's
    // statics — every chunk's boxes — at the end of each `update`, and
    // moves the body and casts its rays from then on.
    (backend ?? PhysicsBackend.current).attach(physics);
    collision = VoxelCollision(blocks, physics);
    navigation = VoxelNavigation(blocks);
    spawn = _standingAt(blocks.sizeX ~/ 2, blocks.sizeZ ~/ 2);
    walk = LevelWalk(world: physics, at: at ?? spawn, yaw: yaw)..pitch = pitch;
  }

  /// A new world from [sandboxTerrain], and nobody's edits on it.
  factory SandboxRun.fresh({PhysicsBackend? backend}) => SandboxRun(
    VoxelWorld(chunksX: 4, chunksY: 2, chunksZ: 4, terrain: sandboxTerrain),
    backend: backend,
  );

  /// The world [storage] kept, edits and where the body stood, or a
  /// [SandboxRun.fresh] one when it kept none or keeps one this build
  /// cannot read — and [onUnread], when given, is told why.
  ///
  /// **Never throws**: a save that will not read is a world started again,
  /// which costs a player their building; a game that will not open costs
  /// them the game.
  factory SandboxRun.open(
    Storage storage, {
    PhysicsBackend? backend,
    void Function(Object error)? onUnread,
  }) {
    final text = storage.read(sandboxSaveName);
    if (text == null) return SandboxRun.fresh(backend: backend);
    try {
      final saved = Snapshot.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      ).data;
      final body = saved['body']! as List<Object?>;
      return SandboxRun(
        VoxelWorld.fromJson(
          (saved['world']! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
        backend: backend,
        at: Vector3(
          (body[0]! as num).toDouble(),
          (body[1]! as num).toDouble(),
          (body[2]! as num).toDouble(),
        ),
        yaw: saved.number('yaw'),
        pitch: saved.number('pitch'),
        slot: saved.integer('slot').clamp(0, hotbar.length - 1),
      );
    } on Object catch (error) {
      onUnread?.call(error);
      return SandboxRun.fresh(backend: backend);
    }
  }

  /// The blocks.
  final VoxelWorld blocks;

  /// What the body and the blocks collide in.
  final CollisionWorld physics = CollisionWorld();

  /// The blocks' boxes in [physics].
  late final VoxelCollision collision;

  /// The navigation mesh, baked again where an edit lands.
  late final VoxelNavigation navigation;

  /// The body, its look, and the camera it carries.
  late final LevelWalk walk;

  /// Where a body starts, and comes back to after falling out of the world:
  /// standing on the middle column.
  late final Vector3 spawn;

  /// Which of [hotbar] is in hand.
  int slot;

  /// How far a block can be reached, in metres from the eye.
  static const double reach = 6.0;

  /// How far below the world a body falls before it is put back.
  static const double floorOfTheVoid = -16.0;

  final Set<ChunkKey> _stale = <ChunkKey>{};
  bool _unsaved = false;
  bool? _homeReachable;

  /// The block [place] puts down.
  int get inHand => hotbar[slot];

  /// Whether an edit has been made since the last [save].
  bool get unsaved => _unsaved;

  /// Where the eye is.
  Vector3 get eye => walk.body.position + Vector3(0.0, walk.eyeHeight, 0.0);

  /// Which way the eye looks — where [LevelWalk.placeCamera] points it.
  Vector3 get gaze {
    final level = math.cos(walk.pitch);
    return Vector3(
      math.sin(walk.yaw) * level,
      math.sin(walk.pitch),
      -math.cos(walk.yaw) * level,
    );
  }

  /// The block looked at, within [reach], or null.
  VoxelHit? get target => blocks.raycast(eye, gaze, reach);

  /// One frame of play: the hotbar, the look, a dig or a place if one was
  /// asked for, then the walk, and the physics brought up to date.
  void step(double dt, InputState input) {
    if (input.slotRequest case final asked?
        when asked >= 0 && asked < hotbar.length) {
      slot = asked;
    }
    final look = input.lookDelta;
    if (look.x != 0.0 || look.y != 0.0) walk.look(look.x, look.y);
    if (input.pressed(SandboxActions.dig)) dig();
    if (input.pressed(SandboxActions.place)) place();
    walk.step(dt, input);
    physics.update();
    if (walk.body.position.y < floorOfTheVoid) walk.body.teleport(spawn);
  }

  /// Takes out the block looked at, and says whether there was one to take.
  ///
  /// The world's lowest layer stays: under it is nothing, and a hole
  /// through it is a fall nobody comes back from.
  bool dig() {
    final hit = target;
    if (hit == null || hit.y == 0) return false;
    return _edit(hit.x, hit.y, hit.z, Voxels.empty);
  }

  /// Puts [inHand] against the face looked at, and says whether it went
  /// down — not into the body, and not outside the world.
  bool place() {
    final hit = target;
    if (hit == null) return false;
    final at = hit.before;
    if (!blocks.contains(at.x, at.y, at.z) ||
        blocks.isSolid(at.x, at.y, at.z)) {
      return false;
    }
    if (_inBody(at.x, at.y, at.z)) return false;
    return _edit(at.x, at.y, at.z, inHand);
  }

  /// The chunks drawn out of date by edits since the last call.
  Set<ChunkKey> takeStaleSurfaces() {
    final stale = Set<ChunkKey>.of(_stale);
    _stale.clear();
    return stale;
  }

  /// Whether the body could walk back to [spawn] from where it stands, on
  /// the navigation mesh as the edits have left it — a wall built round it
  /// or a pit dug under it says no. Asked again after every edit.
  bool get homeReachable => _homeReachable ??=
      navigation.mesh
          .route(_feet(walk.body.position), _feet(spawn))
          ?.complete ??
      false;

  /// The run as a save keeps it: the world's seed and edits, where the body
  /// is, how it looks, and what is in hand.
  Snapshot snapshot() => Snapshot(<String, Object?>{
    'world': blocks.toJson(),
    'body': <double>[
      walk.body.position.x,
      walk.body.position.y,
      walk.body.position.z,
    ],
    'yaw': walk.yaw,
    'pitch': walk.pitch,
    'slot': slot,
  });

  /// Writes the run into [storage], and says whether it was kept.
  bool save(Storage storage) {
    final kept = storage.write(
      sandboxSaveName,
      jsonEncode(snapshot().toJson()),
    );
    if (kept) _unsaved = false;
    return kept;
  }

  /// Takes the blocks' boxes out of the physics, for a run being left.
  void dispose() {
    collision.dispose();
    walk.body.world.remove(walk.body.collider);
  }

  bool _edit(int x, int y, int z, int material) {
    if (!blocks.edit(x, y, z, material)) return false;
    final changes = blocks.takeChanges();
    collision.refresh(changes.chunks);
    navigation.follow(changes);
    _stale.addAll(changes.surfaces);
    _unsaved = true;
    _homeReachable = null;
    return true;
  }

  bool _inBody(int x, int y, int z) {
    // Where the body is now, not where the broadphase last indexed it.
    final body = Aabb3();
    walk.body.shape.computeBounds(walk.body.position, body);
    bool overlaps(double min, double max, int from) =>
        max > from && min < from + 1;
    return overlaps(body.min.x, body.max.x, x) &&
        overlaps(body.min.y, body.max.y, y) &&
        overlaps(body.min.z, body.max.z, z);
  }

  /// Standing on column `(x, z)`: the body's centre half its height above
  /// the column's top, and a little more so it starts clear of the floor.
  Vector3 _standingAt(int x, int z) {
    var top = blocks.sizeY;
    while (top > 0 && !blocks.isSolid(x, top - 1, z)) {
      top--;
    }
    return Vector3(x + 0.5, top + 0.95, z + 0.5);
  }

  static Vector3 _feet(Vector3 body) => body - Vector3(0.0, 0.9, 0.0);
}
