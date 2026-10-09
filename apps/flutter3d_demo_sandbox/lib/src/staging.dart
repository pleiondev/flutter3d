import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_app/flutter3d_app.dart'
    show Storage, StorageException;
import 'package:flutter3d_game/flutter3d_game.dart'
    show ActionMap, DesktopInput, InputSource, LevelWalk;
import 'package:flutter3d_game_kit/world.dart' show Daylight;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:vector_math/vector_math.dart';

import 'elements.dart';
import 'palette.dart';

/// The things this game does that no other does.
abstract final class SandboxActions {
  /// Takes out the block looked at.
  static const GameAction dig = GameAction('dig');

  /// Puts the hotbar's block against the face looked at.
  static const GameAction place = GameAction('place');

  /// Strikes flint at the block looked at.
  static const GameAction strike = GameAction('strike');

  /// Tips a bucket of water onto the column looked at.
  static const GameAction pour = GameAction('pour');
}

/// The keys: walking as every game here walks, Q to dig and E to place —
/// E taken back from `use`, which nothing here is — and the number row, one
/// key a hotbar slot.
ActionMap sandboxActionMap() {
  final map = DesktopInput.addDefaultsTo(ActionMap(actions: ActionSet.common));
  map.buttons
    ..bind(InputSource.key(LogicalKeyboardKey.keyQ.keyId), SandboxActions.dig)
    ..bind(InputSource.key(LogicalKeyboardKey.keyE.keyId), SandboxActions.place)
    ..bind(
      InputSource.key(LogicalKeyboardKey.keyF.keyId),
      SandboxActions.place,
    );
  const row = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];
  // A number past the hotbar picks nothing.
  for (final key in row.skip(hotbar.length)) {
    map.buttons.unbind(InputSource.key(key.keyId));
  }
  return DesktopInput.addSlotsTo(map, row.take(hotbar.length).toList());
}

/// The hills every new world is, and every save is a delta against.
const VoxelTerrain sandboxTerrain = VoxelTerrain(seed: 2026);

/// The name the world is saved under in the game's storage.
const String sandboxSaveName = 'world.json';

/// The sandbox's simulation, written into its run files: a run recorded on
/// another one is refused rather than replayed wrong, and its pose record
/// plays instead.
///
/// Bump [SimulationVersion.genreVersion] when the step reads its input
/// differently, or a block, a dig or the elements over them behave
/// differently.
const SimulationVersion sandboxSimulation = SimulationVersion(genre: 'sandbox');

/// What a run file names as its level: the hills [sandboxTerrain] draws.
/// The edits a run starts from are in its starting state, not here.
const String sandboxLevel = 'sandbox-terrain';

/// The hills as a run file checks them: a run recorded over another seed
/// says so rather than parting at its first dig.
String get sandboxLevelHash => StateDigest.of(<String, Object?>{
  'terrain': sandboxTerrain.toJson(),
}).toRadixString(16).padLeft(8, '0');

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
  /// of the world when not given, and the day at [hour].
  SandboxRun(
    this.blocks, {
    PhysicsBackend? backend,
    Vector3? at,
    double yaw = 0.0,
    double pitch = 0.0,
    this.slot = 0,
    double hour = Daylight.morning,
  }) : day = Daylight(hour: hour),
       physics = CollisionWorld(backend: backend ?? const DartPhysics()) {
    // Attached before anything collides: the core mirrors the world's
    // statics — every chunk's boxes — at the end of each `update`, and
    // moves the body and casts its rays from then on.
    physics.backend.attach(physics);
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
  static Future<SandboxRun> open(
    Storage storage, {
    PhysicsBackend? backend,
    void Function(Object error)? onUnread,
  }) async => SandboxRun.fromSaved(
    await storage.read(sandboxSaveName),
    backend: backend,
    onUnread: onUnread,
  );

  /// [open], given the document already read — null for none — for a
  /// caller that read it before it had anywhere to wait: the app's `main`.
  factory SandboxRun.fromSaved(
    String? text, {
    PhysicsBackend? backend,
    void Function(Object error)? onUnread,
  }) {
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
        // A save from before the day turned has no hour, and opens in the
        // morning a new world starts in.
        hour: saved.number('hour', Daylight.morning),
      );
    } on Object catch (error) {
      onUnread?.call(error);
      return SandboxRun.fresh(backend: backend);
    }
  }

  /// The blocks.
  final VoxelWorld blocks;

  /// What the body and the blocks collide in.
  final CollisionWorld physics;

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

  /// The hour, and the sun and the sky that go with it. Made again by
  /// [restore], at the hour the state holds.
  Daylight day;

  /// Water, fire and falling blocks over the world, when the application
  /// has a renderer to draw them with and asks for them; null in a run that
  /// is only blocks.
  BlockElements? elements;

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

  /// One step of play, in the order [install] runs it: the hotbar, the
  /// look, a dig, a place, a flint or a bucket if one was asked for, then
  /// the walk, the physics brought up to date, the elements, and the day
  /// moved on.
  void step(double dt, InputState input) {
    _hands(input);
    _walk(dt, input);
    elements?.step(dt, eye);
    _world(dt);
  }

  /// The run's step, phase by phase, on [loop], reading [input]: what the
  /// hands do in `input`, the walk and the physics in `physics`, the water,
  /// the fire and the falling blocks in `elements`, and the void and the
  /// day in `rules`.
  ///
  /// **A fixed step now, at the loop's world rate.** The sandbox was stepped
  /// with each frame's own time, unclamped; it is stepped in sixtieths
  /// whatever the display, and a long frame is cut as the loop cuts one.
  void install(LoopRegistry loop, InputState input) {
    loop
      ..addSystem('sandbox.hands', LoopPhase.input, (_) => _hands(input))
      ..addSystem(
        'sandbox.walk',
        LoopPhase.physics,
        (step) => _walk(step.dt, input),
      )
      ..addSystem(
        'sandbox.elements',
        LoopPhase.fields,
        (step) => elements?.step(step.dt, eye),
      )
      ..addSystem('sandbox.world', LoopPhase.rules, (step) => _world(step.dt));
  }

  void _hands(InputState input) {
    if (input.slotRequest case final asked?
        when asked >= 0 && asked < hotbar.length) {
      slot = asked;
    }
    final look = input.lookDelta;
    if (look.x != 0.0 || look.y != 0.0) walk.look(look.x, look.y);
    if (input.pressed(SandboxActions.dig)) dig();
    if (input.pressed(SandboxActions.place)) place();
    if (input.pressed(SandboxActions.strike)) strike();
    if (input.pressed(SandboxActions.pour)) pour();
  }

  void _walk(double dt, InputState input) {
    walk.step(dt, input);
    physics.update();
  }

  void _world(double dt) {
    if (walk.body.position.y < floorOfTheVoid) walk.body.teleport(spawn);
    day.advance(dt);
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
  /// is, how it looks, what is in hand, and the hour.
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
    'hour': day.hour,
  });

  /// The run's whole state, as a run file starts from and a checkpoint
  /// compares: [snapshot]'s, with what a step reads beyond a save — the
  /// body's speed, its footing and the jump it was asked for — and the
  /// water, the fires and the falling blocks when [elements] are up.
  Snapshot state() => Snapshot(<String, Object?>{
    ...snapshot().data,
    'walk': walk.body.save(),
    if (elements case final elements?) 'elements': elements.save(),
  });

  /// Back to what [state] wrote, in place: the edits put right block by
  /// block — the collision, the navigation and the chunks drawn following
  /// them — the body where it stood and moving as it moved, the hand, the
  /// hour, and the elements.
  ///
  /// **Throws a [FormatException] for edits over other hills** — a state
  /// from another seed is not this world's.
  void restore(Snapshot state) {
    final data = state.data;
    if (data.object('world') case final world?) {
      blocks.restoreEdits(world);
      final changes = blocks.drainChanges();
      if (changes.chunks.isNotEmpty) {
        collision.refresh(changes.chunks);
        navigation.follow(changes);
        _stale.addAll(changes.surfaces);
      }
    }
    if (data.object('walk') case final saved?) walk.body.restore(saved);
    walk
      ..yaw = data.number('yaw')
      ..pitch = data.number('pitch');
    slot = data.integer('slot').clamp(0, hotbar.length - 1);
    day = Daylight(hour: data.number('hour', Daylight.morning));
    elements?.restore(data.object('elements'));
    physics.update();
    _homeReachable = null;
    _unsaved = true;
  }

  /// Where the body is, and every falling block: a run file's pose record,
  /// for a build that cannot replay its tape.
  List<BodyPose> poses() => <BodyPose>[
    BodyPose(
      'walker',
      walk.body.position,
      Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), -walk.yaw),
    ),
    ...?elements?.poses(),
  ];

  /// Writes the run into [storage], and says whether it was kept.
  ///
  /// The world is read now; only the write waits.
  Future<bool> save(Storage storage) async {
    final text = jsonEncode(snapshot().toJson());
    try {
      await storage.write(sandboxSaveName, text);
    } on StorageException {
      return false;
    }
    _unsaved = false;
    return true;
  }

  /// Takes the blocks' boxes out of the physics, for a run being left.
  void dispose() {
    elements?.dispose();
    collision.dispose();
    walk.body.world.remove(walk.body.collider);
  }

  /// Puts [material] at a block as an edit, as digging or placing does:
  /// what [elements] burns away or drops goes through this.
  bool setBlock(int x, int y, int z, int material) => _edit(x, y, z, material);

  /// Strikes flint at the block looked at: planks catch.
  bool strike() {
    final hit = target;
    return hit != null && (elements?.ignite(hit.x, hit.y, hit.z) ?? false);
  }

  /// Tips a bucket of water onto the column looked at.
  bool pour() {
    final hit = target;
    final water = elements;
    if (hit == null || water == null) return false;
    water.pour(hit.x, hit.z);
    return true;
  }

  bool _edit(int x, int y, int z, int material) {
    if (!blocks.edit(x, y, z, material)) return false;
    final changes = blocks.drainChanges();
    collision.refresh(changes.chunks);
    navigation.follow(changes);
    _stale.addAll(changes.surfaces);
    _unsaved = true;
    _homeReachable = null;
    elements?.changed(x, y, z);
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
