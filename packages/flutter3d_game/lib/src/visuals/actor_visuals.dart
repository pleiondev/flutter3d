import 'dart:async';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;
import 'package:vector_math/vector_math.dart';

import 'actor_appearance.dart';
import 'actor_corpses.dart';
import 'actor_graphs.dart';
import 'outline_marks.dart';

export 'actor_appearance.dart';
export 'actor_corpses.dart';
export 'actor_graphs.dart';

/// Where the monsters are, and which way they are facing.
///
/// Capsules the size of their own collision shapes, which is deliberate rather
/// than lazy: a placeholder that matches the hitbox exactly means every
/// complaint about a shot that should have landed is a complaint about the
/// aiming and not about the art being the wrong size. When rigged models
/// arrive, the mesh changes here and nothing else does.
///
/// One mesh per kind, uploaded once and shared by every node — the only form of
/// instancing flutter_gpu offers. What colour they are is an [ActorAppearance];
/// this owns the shape, the placement and the death pose.
///
/// ## Where it reads the actors from
///
/// **From the simulation's published state** when given [published] — the
/// boundary the view keeps (decision A of `tasks/1.0-arch-review.md`): where
/// each actor is, which way it faces and whether it lives are read out of
/// the step's published rows ([PublishedActor.read]), the numbers the step
/// left rather than the live actor, so this keeps drawing when the
/// simulation runs in another isolate. The actors' world must be published
/// for that — the loop's own, or a genre's run's, which every genre plugin
/// adds — and their body, facing and health are registered published. An actor is still the key — its
/// appearance, its model and its animation are asked of it — and an actor
/// with no published row this step stays where it was last drawn.
///
/// Without [published] it reads the actors directly, which is the same
/// isolate's shortcut and what a test with no loop does.
final class ActorVisuals {
  ActorVisuals(
    this.scene, {
    required this.appearance,
    required GraphicsDevice device,
    IssueSink? onIssue,
    this.layerMask = 1,
    this.corpses,
    this.graphs,
    this.simulated,
    this.published,
  }) : _meshes = SharedMeshes(device),
       _device = device,
       onIssue = onIssue ?? printIssue;

  final Scene scene;

  /// The layers every actor's mesh is drawn on, capsule and model alike.
  ///
  /// The default layer alone, unless a game says otherwise — and the reason
  /// one would is `RenderSettings.xray`, which names a layer to draw
  /// silhouettes for. A game that puts its actors on a layer of their own
  /// can show what walks behind a wall without showing the wall's own
  /// furniture. Set on every mesh node rather than on the actor's root,
  /// because a render list asks the node it draws and not its parents.
  final int layerMask;

  /// Where this says what it could not draw.
  ///
  /// A model that will not load leaves every actor that wanted it a capsule.
  /// That is playable, which is why it is not an exception — and invisible,
  /// which is why it must not be silent: a capsule is also what an actor with
  /// no model at all looks like.
  final IssueSink onIssue;

  /// The game's half: one material per monster and per state.
  final ActorAppearance appearance;

  /// What a modelled actor becomes when it dies, when not its death clip:
  /// the dungeon's monsters fall as ragdolls. Null plays the clip.
  final ActorCorpses? corpses;

  /// What animates a modelled actor by a graph on the frame, when not its
  /// clip names: for a game whose animation is display only — a graph
  /// stepped with the frame's delta, its markers in [markersPassed]. A game
  /// that animates in its simulation's step gives [simulated] instead, and
  /// then this makes no graph; one actor is never animated both ways.
  final ActorGraphs? graphs;

  /// The graph the simulation steps for an actor, when a game animates in
  /// its step — `ActorAnimations.graphOf`. Such an actor is drawn in the
  /// pose its graph was left in by the last step, and [graphs] makes no
  /// graph of its own for it; its markers arrive as game events rather than
  /// in [markersPassed].
  final AnimationGraph? Function(Actor actor)? simulated;

  /// The state the simulation last published — `() => loop.published`, or a
  /// `SimulationHandle`'s — read once per [recordStep] and [sync]; null reads
  /// the actors directly. See the class doc.
  final PublishedState Function()? published;

  /// What the view knows of [actor] from [state] when there is published
  /// state, from the actor when there is not; null for an actor with no
  /// body to place.
  ({Vector3 at, double yaw, bool isAlive, double steppedUp})? _read(
    Actor actor,
    PublishedState? state,
  ) {
    if (state == null) {
      final at = actor.position;
      return at == null
          ? null
          : (
              at: at,
              yaw: actor.yaw,
              isAlive: actor.isAlive,
              steppedUp: actor.body?.steppedUp ?? 0.0,
            );
    }
    final row = PublishedActor.read(state, actor.entity);
    return row == null
        ? null
        : (
            at: row.at,
            yaw: row.yaw,
            isAlive: row.isAlive,
            steppedUp: row.steppedUp,
          );
  }

  /// Whether [actor] lives, as [animate] draws it: from its published row
  /// when there is published [state], and as it was last seen when the step
  /// left it none; from the actor when there is no published state.
  bool _isAlive(Actor actor, PublishedActor? row, PublishedState? state) {
    if (state == null) return actor.isAlive;
    final alive = row?.isAlive ?? _wasAlive[actor] ?? true;
    _wasAlive[actor] = alive;
    return alive;
  }

  /// Each actor's life as [animate] last read it from published state.
  final Map<Actor, bool> _wasAlive = <Actor, bool>{};

  /// The colour each actor is ringed in under the high-contrast look, or
  /// null for none — `N9`. Asked every [sync], and applied to whatever the
  /// actor is drawn as at the time: the capsule, then the model that replaces
  /// it, then the corpse, which a game may well want left unringed.
  ///
  /// Left null, nothing is ringed and nothing is walked. A game can leave it
  /// set with the look off: the engine reads no ring until the look is on.
  Vector3? Function(Actor actor)? outlineOf;

  final OutlineMarks _marks = OutlineMarks();

  /// Each actor [graphs] gave a machine, its graph.
  final Map<Actor, AnimationGraph> _graphs = <Actor, AnimationGraph>{};

  /// Every marker an actor's graph passed in the last [animate], with whose
  /// and in which state: a monster's foot down is a footstep a game plays
  /// where it is.
  List<({Actor actor, String state, String name})> get markersPassed =>
      List<({Actor actor, String state, String name})>.unmodifiable(_markers);
  final List<({Actor actor, String state, String name})> _markers =
      <({Actor actor, String state, String name})>[];

  /// The graph animating [actor], if one does: to ask what state it is in.
  AnimationGraph? graphOf(Actor actor) =>
      _graphs[actor] ?? simulated?.call(actor);

  /// The model [actor] is drawn as, once it has arrived: its joints, its
  /// player, its meshes. Null for an actor still, or only ever, a capsule.
  ModelInstance? modelOf(Actor actor) => _instances[actor];

  /// The models, kept for [corpses]: a ragdoll is made of a model's joints.
  final Map<Actor, ModelInstance> _instances = <Actor, ModelInstance>{};

  /// Actors [corpses] took over, and those it declined.
  final Set<Actor> _taken = <Actor>{};
  final Set<Actor> _declined = <Actor>{};

  /// Each living modelled actor's joints as the last frame left them, for
  /// the motion a corpse starts with; kept only when there are [corpses].
  final Map<Actor, List<Matrix4>> _lastPose = <Actor, List<Matrix4>>{};
  double _lastDt = 1.0 / 60.0;

  final SharedMeshes _meshes;
  final GraphicsDevice _device;

  final Map<Actor, SceneNode> _nodes = <Actor, SceneNode>{};

  /// Every model asked for so far, by path. One load per file, however many
  /// actors are drawn with it.
  final Map<String, Future<ModelAsset?>> _models =
      <String, Future<ModelAsset?>>{};

  /// The animation of each actor that has one.
  final Map<Actor, AnimationPlayer> _players = <Actor, AnimationPlayer>{};

  /// What each one was last told to play, so a cross-fade is started once and
  /// not restarted sixty times a second.
  final Map<Actor, String> _playing = <Actor, String>{};

  /// The models [add] started dressing actors in that have not arrived yet.
  final Set<Future<void>> _dressing = <Future<void>>{};

  /// Completes once every actor added so far wears its model — `N3`.
  ///
  /// Play does not wait for the models, but a loading screen that warms the
  /// renderer up should: the crypt's monsters are skinned, and a model
  /// arriving after `Renderer.warmUp` left the first frame of play to link
  /// the skinned pipelines.
  Future<void> get settled => Future.wait(_dressing.toList());

  /// Gives an actor something to be drawn as.
  ///
  /// An actor with no body is skipped rather than refused: a turret, a trigger
  /// or a director is a perfectly good actor and simply is not a capsule. What
  /// draws those is the game's own business.
  void add(Actor actor) {
    final body = actor.body;
    if (body == null) return;

    final model = appearance.modelFor(actor);
    if (model != null) {
      // The capsule goes in first and is replaced when the file arrives. The
      // alternative — nothing until it loads — is a monster that walks up to
      // you invisible, which is worse than one that is briefly a capsule.
      _addCapsule(actor, body);
      final dressing = _dress(actor, model);
      _dressing.add(dressing);
      unawaited(dressing.whenComplete(() => _dressing.remove(dressing)));
      return;
    }
    _addCapsule(actor, body);
  }

  /// Takes an actor's node out of the scene and forgets it.
  ///
  /// **There was `add` and nothing else.** `ActorSystem.remove` exists, and an
  /// actor removed through it kept its `SceneNode` here for ever — so the next
  /// [sync] read `actor.position!` on an entity whose `Body` component was
  /// gone and threw from inside the render path. It was latent only because
  /// nothing calls `ActorSystem.remove` today, which is the worst kind of
  /// latent: the first caller finds out in a frame rather than at a compile.
  void remove(Actor actor) {
    if (_nodes.remove(actor) case final node?) {
      node.removeFromParent();
      _marks.forget(node);
    }
    _players.remove(actor);
    _playing.remove(actor);
    _instances.remove(actor);
    _graphs.remove(actor);
    _lastPose.remove(actor);
    _wasAlive.remove(actor);
    _declined.remove(actor);
    if (_taken.remove(actor)) corpses?.end(actor);
  }

  /// Lets go of every node, every uploaded mesh and every loaded model.
  ///
  /// The level's, not the game's: what this holds was built for one level and
  /// is worth nothing to the next. See `RunSession.close` for when that is.
  ///
  /// **The models used to be deliberately left in [_models]**, on the claim
  /// that they were "a `ResourceCache`'s business and shared between levels".
  /// No such cache exists: the map is this instance's own and dies with it, so
  /// keeping the entries only stranded the uploads — a real driver-object leak
  /// per level on WebGL2. They are released here now, through the future
  /// rather than its value, so a model that finishes loading *after* the level
  /// ended is released the moment it arrives instead of never.
  void dispose() {
    // Anything still reading a file will find this and stop rather than
    // instantiate into a scene that has been torn down.
    _generation++;
    for (final node in _nodes.values) {
      node.removeFromParent();
    }
    _nodes.clear();
    _marks.clear();
    _players.clear();
    _playing.clear();
    _smoothed.clear();
    _instances.clear();
    _graphs.clear();
    _lastPose.clear();
    _wasAlive.clear();
    _taken.clear();
    _declined.clear();
    corpses?.dispose();
    for (final pending in _models.values) {
      unawaited(pending.then((asset) => asset?.dispose()));
    }
    _models.clear();
    _meshes.dispose();
  }

  /// Bumped by [dispose], so a model that arrives late can tell.
  int _generation = 0;

  void _addCapsule(Actor actor, CharacterController body) {
    // Straight off the body, so this works for anything with one. It used to
    // read a `MonsterDef`, which is how the renderer's bridge came to depend on
    // a shooter's idea of what walks about in a level.
    final radius = body.halfExtents.x;
    final height = body.halfExtents.y * 2.0;
    final key = appearance.meshKeyFor(actor);
    final mesh = _meshes.shape(
      'actor:$key',
      () => CapsuleShape(radius: radius, height: height),
    );

    final node = MeshNode(mesh, appearance.materialFor(actor), name: key)
      ..layerMask = layerMask;
    scene.add(node);
    _nodes[actor] = node;
  }

  /// Swaps an actor's capsule for its model once the file has been read.
  Future<void> _dress(Actor actor, String path) async {
    final generation = _generation;
    final asset = await _models.putIfAbsent(path, () => _load(path));
    // Dead by the time it arrived, or the level changed underneath it. Both
    // happen: a runner can be shot before its own model finishes loading.
    //
    // **The level check used to be the actor check**, which is not the same
    // question: a model arriving after the level ended found `_nodes` empty
    // and stopped by luck, and one arriving after a *new* level had spawned an
    // actor into the same map would have instantiated into it. The generation
    // asks the question directly.
    if (asset == null ||
        generation != _generation ||
        !_nodes.containsKey(actor)) {
      return;
    }

    final instance = asset.instantiate(scene);
    for (final mesh in instance.meshes) {
      mesh.layerMask = layerMask;
    }
    final capsule = _nodes.remove(actor);
    if (capsule != null) {
      scene.remove(capsule);
      // The model is a new tree with no ring on it yet; the next sync rings
      // it, and the capsule's entry would only keep the capsule alive.
      _marks.forget(capsule);
    }

    _nodes[actor] = instance.root;
    _instances[actor] = instance;
    final player = instance.player;
    if (player != null) _players[actor] = player;
    final machine = player == null || simulated != null
        ? null
        : graphs?.machineFor(actor, player.clips);
    if (machine != null) {
      final graph = _graphs[actor] = AnimationGraph(
        machine: machine,
        clips: player!.clips,
        pose: AnimationPose.fromNodes(asset.nodes),
      );
      graphs!.dress(actor, graph, instance);
    }
  }

  Future<ModelAsset?> _load(String path) async {
    try {
      // The same door the fixtures load through, so an actor's model may be
      // named by its `assets_src/` source too — see [loadModelByPath].
      final document = await loadModelByPath(path);
      return await ModelAsset.fromDocument(
        document,
        device: _device,
        name: path,
      );
    } catch (error) {
      // A missing or broken model leaves every actor that wanted it a capsule,
      // which is a level somebody can still play through and report.
      onIssue(
        Issue('actors: could not load $path, staying a capsule ($error)'),
      );
      return null;
    }
  }

  /// Which way to turn what is drawn for [actor], in radians.
  ///
  /// **A model faces the other way to a capsule.** An actor's yaw is the
  /// direction it is walking — the shooter builds its forward as
  /// `(-sin(yaw), 0, -cos(yaw))`, so yaw nought points down -Z — and a
  /// character exported from Blender through glTF faces +Z. That is half a
  /// turn apart, so every monster walked at the player backwards and fell over
  /// backwards, which is what it looked like from the corridor.
  ///
  /// A capsule never showed it, being round about the axis it spins on, so this
  /// arrived with the models and not with the code that placed them.
  ///
  /// [model] is false for the capsule an actor is drawn as before its model
  /// loads, and for one whose model never does.
  static double yawFor(Actor actor, {required bool model}) =>
      model ? actor.yaw + math.pi : actor.yaw;

  /// How far below its body's centre [actor]'s model has its feet: a model of
  /// somebody standing has them at its origin, a body is a shape about its
  /// middle.
  static double feetBelowCenter(Actor actor) =>
      actor.body?.halfExtents.y ?? 0.0;

  /// Where [actor]'s model is when its body's centre is [center]: feet under
  /// it, turned by [yawFor] — what [sync] places a model by, for a
  /// simulation that has no model to ask, such as one aiming a head.
  static Matrix4 modelMatrixAt(Actor actor, Vector3 center) => Matrix4.compose(
    Vector3(center.x, center.y - feetBelowCenter(actor), center.z),
    Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yawFor(actor, model: true)),
    Vector3.all(1.0),
  );

  /// How [actor]'s clip should behave when it runs off its end.
  ///
  /// **A corpse does not die twice.** [AnimationPlayer.wrap] defaults to
  /// looping and nothing set it, so a monster's death clip started over the
  /// moment it finished: the frog fell, snapped upright and fell again, for
  /// ever, in a room the player had already cleared.
  /// [AnimationWrap.once] holds the final pose, which is the pose a body
  /// should be left in.
  ///
  /// Read from the actor rather than from the clip's name, because the name
  /// belongs to whoever exported the model: two of the crypt's three files
  /// spell their hit clip differently, and the death clip in the fourth model
  /// somebody adds will be called whatever that artist called it. Being dead is
  /// not a spelling.
  ///
  /// Its own method because that is the whole of what can be tested without a
  /// device: reaching the line inside [animate] means uploading a rigged model
  /// to a GPU to look at one enum.
  static AnimationWrap wrapFor(Actor actor) => wrapWhen(isAlive: actor.isAlive);

  /// [wrapFor], from whether the actor lives rather than from the actor:
  /// what [animate] asks with what the step published.
  static AnimationWrap wrapWhen({required bool isAlive}) =>
      isAlive ? AnimationWrap.loop : AnimationWrap.once;

  /// Advances every animation. Once a frame, with the frame's own delta.
  ///
  /// **From published state when there is some** ([published]): whether an
  /// actor lives — which decides a corpse, a clip that holds its last pose
  /// and whether a pose is kept for a ragdoll — and which clips it plays
  /// ([ActorAppearance.clipsFrom]) are read from its published row, not from
  /// the actor, so this keeps animating when the simulation runs in another
  /// isolate. An actor the step left no row for keeps what was last read.
  void animate(double dt) {
    _markers.clear();
    final state = published?.call();
    for (final entry in _players.entries) {
      final actor = entry.key;
      final row = state == null
          ? null
          : PublishedActor.read(state, actor.entity);
      final alive = _isAlive(actor, row, state);
      if (_taken.contains(actor)) {
        // A corpse stays the corpses' until its actor stands again — a
        // rewind to before the death, a rollback — and then it is let go,
        // so the actor is animated again and a second death is handed over
        // again. `end` for a body the corpses already let go (the ragdolls'
        // own snapshot part) does nothing.
        if (!alive) continue;
        _taken.remove(actor);
        corpses?.end(actor);
      }
      if (!alive && _takeOver(actor)) continue;
      if (simulated?.call(actor) case final stepped?) {
        _drawnPose(actor, stepped).writeTo(entry.value.targets);
        if (corpses != null && alive) _keepPose(actor);
        continue;
      }
      final graph = _graphs[actor];
      if (graph != null) {
        graphs!.drive(actor, graph, _instances[actor]!);
        graph.evaluate(dt).writeTo(entry.value.targets);
        for (final passed in graph.passed) {
          _markers.add((actor: actor, state: passed.state, name: passed.name));
        }
        if (corpses != null && alive) _keepPose(actor);
        continue;
      }
      final wanted = row == null
          ? appearance.clipsFor(actor)
          : appearance.clipsFrom(actor, row);
      // The first the model actually has. `crossFadeToNamed` reports whether
      // the name was there, so a clip this export does not carry is a miss
      // rather than a crash — and the next candidate gets a turn.
      for (final name in wanted) {
        if (_playing[entry.key] == name) break;
        // Only on a change: `crossFadeToNamed` restarts the fade every time it
        // is called, so calling it per frame is an animation that never gets
        // anywhere — always a tenth of a second into the same blend.
        if (entry.value.crossFadeToNamed(name)) {
          _playing[entry.key] = name;
          break;
        }
      }
      entry.value
        ..wrap = wrapWhen(isAlive: alive)
        ..update(dt)
        ..apply();
      if (corpses != null && alive) _keepPose(actor);
    }
    _wasAlive.removeWhere((Actor actor, _) => !_players.containsKey(actor));
    _lastDt = dt > 0.0 ? dt : _lastDt;
    corpses?.step(dt);
  }

  /// Whether [corpses] takes [actor] over now that it is dead: asked once.
  bool _takeOver(Actor actor) {
    final corpses = this.corpses;
    final instance = _instances[actor];
    if (corpses == null || instance == null || _declined.contains(actor)) {
      return false;
    }
    final taken = corpses.begin(
      actor,
      instance,
      previous: _lastPose.remove(actor),
      dt: _lastDt,
    );
    (taken ? _taken : _declined).add(actor);
    return taken;
  }

  /// [actor]'s joints as they stand now, into the list kept for it.
  void _keepPose(Actor actor) {
    final skeletons = _instances[actor]?.skeletons;
    if (skeletons == null || skeletons.isEmpty) return;
    final joints = skeletons.first.joints;
    final kept = _lastPose.putIfAbsent(
      actor,
      () => <Matrix4>[for (final _ in joints) Matrix4.zero()],
    );
    for (var i = 0; i < joints.length; i++) {
      kept[i].setFrom(joints[i].worldMatrix);
    }
  }

  /// Remembers where every actor is, as the step that has just run left it.
  ///
  /// **Call once per simulation step**, from the same place the game steps its
  /// world. Without it there is nothing to interpolate between and [sync]
  /// draws the authoritative position, which is what it did for as long as
  /// this class existed: every monster, and every door and lift on the
  /// [FixtureVisuals] side, moved in fixed-step jumps while the player's own
  /// camera was smooth — because `Player.eyeFrom` interpolates and this did
  /// not. On a 60 Hz display the two are indistinguishable; on anything
  /// faster the difference is the whole reason `InterpolatedVector3` exists.
  ///
  /// A stair the body climbed this step is what keeps a staircase from
  /// being a series of small jumps — the same mechanism the runner uses for
  /// itself — read from the published `Gait` when there is [published]
  /// state, and from the body when there is not.
  void recordStep({double dt = 0.0}) {
    final state = published?.call();
    for (final actor in _nodes.keys) {
      final read = _read(actor, state);
      if (read == null) continue;
      final position = read.at;
      final smoothed = _smoothed[actor];
      if (smoothed == null) {
        // First sight: no previous to come from, so it arrives where it is
        // rather than sliding in from the origin.
        _smoothed[actor] = InterpolatedVector3()..jumpTo(position);
        continue;
      }
      smoothed.push(position, dt: dt, steppedUp: read.steppedUp);
    }
    // An actor that has gone stops being interpolated, or the map grows for
    // the life of the level with one entry per corpse.
    _smoothed.removeWhere((Actor actor, _) => !_nodes.containsKey(actor));
    // The simulation's poses, the one this step left and the one before it,
    // for [animate] to draw between as [sync] draws the body between.
    for (final actor in _nodes.keys) {
      final graph = simulated?.call(actor);
      if (graph == null) continue;
      final kept = _stepPoses[actor] ??= (
        before: graph.pose.restCopy()..setFrom(graph.pose),
        after: graph.pose.restCopy()..setFrom(graph.pose),
        drawn: graph.pose.restCopy(),
      );
      kept.before.setFrom(kept.after);
      kept.after.setFrom(graph.pose);
    }
    _stepPoses.removeWhere((Actor actor, _) => !_nodes.containsKey(actor));
  }

  /// Each simulated actor's pose after the last two steps, and the pose
  /// drawn between them.
  final Map<
    Actor,
    ({AnimationPose before, AnimationPose after, AnimationPose drawn})
  >
  _stepPoses =
      <
        Actor,
        ({AnimationPose before, AnimationPose after, AnimationPose drawn})
      >{};

  /// How far through the step the last [sync] drew: the poses are drawn as
  /// far, so a planted foot stays under a body drawn between two steps.
  double _alpha = 1.0;

  /// [actor]'s pose to draw this frame: between the last two steps' as the
  /// body is, when [recordStep] has kept them; the last step's when not.
  AnimationPose _drawnPose(Actor actor, AnimationGraph graph) {
    final kept = _stepPoses[actor];
    if (kept == null) return graph.pose;
    return kept.drawn
      ..setFrom(kept.after)
      ..blendFrom(kept.before, _alpha);
  }

  final Map<Actor, InterpolatedVector3> _smoothed =
      <Actor, InterpolatedVector3>{};

  /// Where to draw [actor] this frame: between the last two steps when
  /// something has been recording them, and where it authoritatively is —
  /// [at], as [_read] has it — when nothing has.
  Vector3 _drawAt(Actor actor, Vector3 at, double alpha) {
    final smoothed = _smoothed[actor];
    if (smoothed == null) return at;
    smoothed.read(alpha, _drawn);
    return _drawn;
  }

  /// Reused, because this is read once per actor per frame and a `Vector3` is
  /// a heap object — the reason half of this engine takes an out parameter.
  final Vector3 _drawn = Vector3.zero();

  /// Moves every node to its actor.
  ///
  /// Called once per frame rather than per simulation step: this is display,
  /// and the simulation does not care where the capsules are.
  ///
  /// [alpha] is how far through the current step the frame is drawing —
  /// `EngineLoop.alpha`. The default of 1.0 is the authoritative position, which
  /// is exactly what this did before [recordStep] existed, so a game that has
  /// not wired the per-step call up draws what it always drew.
  void sync([double alpha = 1.0]) {
    _alpha = alpha;
    final state = published?.call();
    for (final entry in _nodes.entries) {
      final actor = entry.key;
      final node = entry.value;
      if (outlineOf case final ring?) _marks.mark(node, ring(actor));
      // A corpse a ragdoll took over stays where it fell: its joints are
      // the ragdoll's, and moving its root would move them.
      if (_taken.contains(actor)) continue;
      // An actor the step left no row for stays where it was last drawn.
      final read = _read(actor, state);
      if (read == null) continue;
      final position = _drawAt(actor, read.at, alpha);

      // Only a capsule takes the game's material; a model brings its own, and
      // painting over it would make three monsters one colour.
      if (node is MeshNode) node.material = appearance.materialFor(actor);

      if (!read.isAlive && !_players.containsKey(actor)) {
        // Laid on its side and sunk, which reads as a corpse without needing a
        // death animation. It stays: an emptied corridor should show what
        // happened in it.
        node
          ..setPosition(
            position.x,
            position.y - actor.body!.halfExtents.y * 0.64,
            position.z,
          )
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2.0),
          );
        continue;
      }

      // A capsule is a shape about its middle and sits on the body's centre;
      // a model of somebody standing has its feet at its origin. The same two
      // conventions the platformer reconciles every frame for its runner —
      // rooted at the centre, a monster's model hovers half its height off
      // the floor from the moment it replaces its capsule.
      final isModel = node is! MeshNode;
      final drop = isModel ? feetBelowCenter(actor) : 0.0;
      node
        ..setPosition(position.x, position.y - drop, position.z)
        ..setRotation(
          Quaternion.axisAngle(
            Vector3(0.0, 1.0, 0.0),
            isModel ? read.yaw + math.pi : read.yaw,
          ),
        );
    }
  }
}
