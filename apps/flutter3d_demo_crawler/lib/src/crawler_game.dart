/// The crawl as a Flame game over the 3D layer.
///
/// **Everything here that is not content is the bridge's.** The fixed step
/// is `HasFixedStep`, and the crawl's own `step` runs in its `fixedUpdate`
/// with the game as the `StepClock` every drawing follows. The device, the
/// scene and the renderer are `HasFlutter3d`'s, and a new level is
/// `replaceScene3d`. The players are `PlayerSeats` over `FlameInputBridge`s —
/// two keyboard layouts and four controller slots, keys from the keyboard
/// itself — and join by pressing fire. The heroes are
/// `CharacterBodyComponent`s, the horde `InstancedActorComponent`s over one
/// batch a kind, the shots `InstancedPoseComponent`s, the level's furniture a
/// `FixtureVisualsComponent`, and the view a `ViewCamera` turned by the
/// crawl's own framing.
///
/// What is left is the game: which buttons mean fire and potion, how a class
/// is chosen, and what happens between levels.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart' show LoadedLevel;
import 'package:flutter3d_game/flutter3d_game.dart'
    show Bindings, InputSource, PadInput;
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show Actor, GameAction, InputState, RunOutcome, Snapshot;
import 'package:pad_input/pad_input.dart';

import 'crawl_visuals.dart';
import 'hud.dart';
import 'level_open.dart';
import 'net_crawl.dart';
import 'staging.dart';

/// Where the game is between its screens.
enum CrawlPhase { choosing, connecting, loading, playing, between, over }

/// One way of holding the game: a name for the select screen, and its input.
final class Device {
  Device(this.name, this.input);

  final String name;
  final FlameInputBridge input;
}

final class CrawlerGame extends FlameGame with HasFlutter3d, HasFixedStep {
  /// [party] are class names to go straight in with, the first on WASD and
  /// the second on the arrows: a demo with nobody at the keys.
  ///
  /// With a [room], the crawl is one of two machines' and waits for
  /// [goOnline]: [slot] is which hero this one drives — nought for whoever
  /// made the room — and its class is [party]'s first.
  CrawlerGame({
    this.party = const <String>[],
    this.room,
    this.slot = 0,
    this.onSettled,
  }) : phase = room == null ? CrawlPhase.choosing : CrawlPhase.connecting;

  final List<String> party;

  /// The room this game plays in online, or null for one screen.
  final String? room;

  /// Which of the two heroes this machine drives, online.
  final int slot;

  /// Told of every step both machines have agreed on, with the level it was
  /// in: what a test compares the two machines by.
  final void Function(String level, int step, Snapshot after)? onSettled;

  static const GameAction fire = GameAction('fire');
  static const GameAction potion = GameAction('potion');

  /// A beat between one level and the next.
  static const double _pause = 2.0;

  /// Every way of holding the game: two keyboard layouts, then four
  /// controller slots.
  late final List<Device> devices = <Device>[
    Device('WASD, Space to fire, Q for a potion', _keys(_wasd)),
    Device('arrows, / to fire, . for a potion', _keys(_arrows)),
    for (var i = 0; i < 4; i++) Device('controller ${i + 1}', _pad()),
  ];

  late final PlayerSeats seats = PlayerSeats(<FlameInputBridge>[
    for (final device in devices) device.input,
  ]);

  final List<PadInput> _pads = <PadInput>[];

  /// The class each seated player picked.
  final Map<FlameInputBridge, HeroClass> classes =
      <FlameInputBridge, HeroClass>{};

  /// Bumped whenever an overlay has something new to show.
  final ValueNotifier<int> changed = ValueNotifier<int>(0);

  final Announcer announcer = Announcer();

  CrawlPhase phase;

  /// What the level on screen is, once there is one.
  StagedCrawl? staged;

  /// What the players are told when a level ends.
  String? message;

  /// The level's name, for its first moments.
  String? title;

  double levelTime = 0.0;
  double _waited = 0.0;

  LoadedLevel? _loaded;
  Component? _level;
  final List<void Function()> _retiring = <void Function()>[];

  @override
  CameraNode createCamera3d() => CameraNode(
    name: 'camera 3d',
    projection: PerspectiveProjection(
      fovYRadians: const FramingTuning().fieldOfView,
      far: 200.0,
    ),
  );

  @override
  RenderSettings renderSettings() => crawlRenderSettings;

  @override
  void onOpen3d() {
    add(seats.listenToKeyboard());
    addAll(seats.stepEnds());
    for (var i = 0; i < _pads.length; i++) {
      add(devices[2 + i].input.followPad(_pads[i]));
    }
    add(
      ViewCameraComponent(
        ViewCamera(
          camera: camera3d,
          view: (Vector3 eye, Vector3 target) {
            final framing = staged?.sim.framing;
            if (framing == null || !framing.isFramed) return false;
            framing.view(eye, target);
            return true;
          },
        ),
      ),
    );
    if (party.isNotEmpty) {
      for (var i = 0; i < party.length && i < 2; i++) {
        final seat = devices[i].input;
        seats.claim(seat);
        classes[seat] = HeroClass.all.firstWhere(
          (HeroClass k) => k.name == party[i].trim(),
          orElse: () => HeroClass.all[i],
        );
      }
      // Online, the crawl waits for the other machine instead.
      if (!online) unawaited(enter(firstLevel));
    }
  }

  // MARK: - Two machines

  PeerWire? _wire;
  PeerRoom? _room;
  RollbackPlay<Snapshot>? _play;

  /// Whether this game is one of two machines playing one crawl.
  bool get online => room != null;

  /// Starts talking to the other machine over [wire], the room's; the crawl
  /// goes in once it has said which class it is.
  void goOnline(PeerWire wire) => _wire = wire;

  /// The class the other machine said it plays.
  HeroClass get _peerClass => HeroClass.all.firstWhere(
    (HeroClass k) => k.name == _room?.peer?['class'],
    orElse: () => HeroClass.warrior,
  );

  /// How the agreed step of the level came out: a level is over only when it
  /// is over there, since a step still resting on a guess can be taken back.
  RunOutcome get _agreedOutcome {
    final outcome = _play?.agreedEnd?.after.data['outcome'];
    return RunOutcome.values.firstWhere(
      (RunOutcome o) => o.name == outcome,
      orElse: () => RunOutcome.playing,
    );
  }

  HeroClass get _localClass {
    final seated = seats.seated;
    return seated.isEmpty ? HeroClass.warrior : classes[seated.first]!;
  }

  /// This machine's hands for the step about to be captured.
  Map<String, Object?> _captureLocal() {
    final seated = seats.seated;
    if (seated.isEmpty) return heroFrame(0.0, 0.0, fire: false, drink: false);
    final state = seated.first.inputState;
    final axis = state.moveAxis;
    return heroFrame(
      axis.x,
      -axis.y,
      fire: state.held(fire),
      drink: state.pressed(potion),
    );
  }

  /// Goes into the level named [name], carrying [carried] from the last.
  Future<void> enter(String name, {List<Hero> carried = const <Hero>[]}) async {
    phase = CrawlPhase.loading;
    changed.value++;
    final (:kinds, :loaded, :fixtures) = await openLevel(
      levelAsset(name),
      device: device,
    );
    final crawl = stage(
      loaded.level,
      loaded.collision,
      // Online, the party is the room's — hero nought is whoever made it —
      // and the same on both machines.
      party: online
          ? <HeroClass>[
              if (slot == 0) ...<HeroClass>[_localClass, _peerClass],
              if (slot == 1) ...<HeroClass>[_peerClass, _localClass],
            ]
          : <HeroClass>[for (final seat in seats.seated) classes[seat]!],
      carried: carried,
      registry: kinds,
      onFixture: fixtures.add,
    );

    // The level before goes once the next is on screen: its scene is not
    // drawn after this frame, and its meshes are let go of the frame after.
    final previous = _level;
    final previousLoaded = _loaded;
    previous?.removeFromParent();
    if (previousLoaded != null) {
      _retiring.add(() => previousLoaded.dispose(device));
    }
    replaceScene3d(loaded.scene);

    final level = Component();
    await add(level);
    await level.add(FixtureVisualsComponent(fixtures));
    for (final hero in crawl.sim.heroes) {
      await level.add(_HeroFigure(hero, loaded.scene, device, this));
    }
    await level.add(_Mirror(crawl, loaded.scene, device, this, level));

    final peers = _room;
    if (peers != null) {
      final sim = crawl.sim;
      final seconds = fixedStep.stepSeconds;
      final levelName = loaded.level.name;
      _play = RollbackPlay<Snapshot>(
        wire: peers.channel('level:$name'),
        localSlot: slot,
        capture: _captureLocal,
        applyAndStep: (List<Map<String, Object?>> hands) {
          for (var i = 0; i < hands.length; i++) {
            applyHeroFrame(hands[i], sim.heroes[i]);
          }
          sim.step(seconds);
        },
        save: sim.save,
        restore: sim.restore,
        endsAt: (Snapshot after) =>
            after.data['outcome'] != RunOutcome.playing.name,
        onSettled: (int step, Snapshot after) =>
            onSettled?.call(levelName, step, after),
      );
    }
    _loaded = loaded;
    _level = level;
    staged = crawl;
    title = loaded.level.name;
    levelTime = 0.0;
    phase = CrawlPhase.playing;
    changed.value++;
  }

  @override
  void fixedUpdate(double step) {
    switch (phase) {
      case CrawlPhase.choosing:
        if (_choose()) unawaited(enter(firstLevel));
      case CrawlPhase.playing:
        final crawl = staged;
        if (crawl == null) return;
        final play = _play;
        if (play != null) {
          play.advance();
        } else {
          _drive(crawl.sim.heroes);
          crawl.sim.step(step);
        }
        // Online, a step taken back and run again says its news twice; the
        // announcer repeating a line is the price, not a desync.
        announcer.hear(crawl.sim.events.drain());
        _judge(crawl.sim);
      case CrawlPhase.between || CrawlPhase.over when _play != null:
        // Still talking after the end, so the other machine hears the frames
        // it needs to agree on the same ending; what these steps do to this
        // crawl is thrown away.
        _play!.advance();
      case CrawlPhase.over:
        if (seats.seated.any(
          (FlameInputBridge s) => s.inputState.pressed(potion),
        )) {
          _backToChoosing();
        }
      case CrawlPhase.connecting:
        _handshake(step);
      case CrawlPhase.loading || CrawlPhase.between:
        break;
    }
  }

  /// Says which class this machine is until the other one has said which
  /// it is, then goes in. The room is made here rather than on
  /// [goOnline], once the seats say what this machine plays.
  void _handshake(double step) {
    final wire = _wire;
    if (wire == null) return;
    final peers = _room ??= PeerRoom(
      wire,
      slot: slot,
      about: <String, Object?>{'class': _localClass.name},
    );
    peers.step(step);
    if (peers.met) unawaited(enter(firstLevel));
  }

  @override
  void update(double dt) {
    for (final retire in _retiring) {
      retire();
    }
    _retiring.clear();
    super.update(dt);
    if (phase == CrawlPhase.playing || phase == CrawlPhase.over) {
      levelTime += dt;
      announcer.pass(dt);
    }
    if (phase == CrawlPhase.between) {
      _waited += dt;
      final crawl = staged;
      final next = crawl?.sim.nextLevel;
      if (_waited >= _pause && crawl != null && next != null) {
        // Carried on from the agreed step, not from the steps this machine
        // has run past it on a guess: the next level starts from the same
        // heroes on both.
        if (_play?.agreedEnd case (:final after, step: _)) {
          crawl.sim.restore(after);
        }
        unawaited(enter(next, carried: crawl.sim.heroes));
      }
    }
    changed.value++;
  }

  /// One step of the select screen: a device whose fire went down joins, a
  /// seated one moving sideways changes class. True when somebody seated
  /// pressed the potion button, which starts the game.
  bool _choose() {
    var start = false;
    for (final device in devices) {
      final input = device.input;
      final state = input.inputState;
      if (!seats.seated.contains(input)) {
        if (state.pressed(fire) && seats.claim(input)) {
          classes[input] = _freeClass();
        }
        continue;
      }
      final step =
          (state.pressed(GameAction.moveRight) ? 1 : 0) -
          (state.pressed(GameAction.moveLeft) ? 1 : 0);
      if (step != 0) {
        final all = HeroClass.all;
        classes[input] =
            all[(all.indexOf(classes[input]!) + step) % all.length];
      }
      if (state.pressed(potion)) start = true;
    }
    return start && seats.seated.isNotEmpty;
  }

  HeroClass _freeClass() {
    for (final kind in HeroClass.all) {
      if (!classes.values.contains(kind)) return kind;
    }
    return HeroClass.all.first;
  }

  /// Each seated player's input written onto their hero, for this step.
  void _drive(List<Hero> heroes) {
    final seated = seats.seated;
    for (var i = 0; i < seated.length && i < heroes.length; i++) {
      final state = seated[i].inputState;
      final hero = heroes[i];
      final axis = state.moveAxis;
      // Forward on the stick is up the screen, which is north, which is −Z.
      hero.wish.setValues(axis.x, 0.0, -axis.y);
      if (hero.wish.length > 1.0) hero.wish.normalize();
      hero.fire = state.held(fire);
      if (state.pressed(potion)) hero.drink = true;
    }
  }

  void _judge(CrawlerSimulation sim) {
    switch (online ? _agreedOutcome : sim.outcome) {
      case RunOutcome.won when sim.nextLevel != null:
        _waited = 0.0;
        phase = CrawlPhase.between;
        message = 'Through! On to ${sim.nextLevel}.';
      case RunOutcome.won:
        phase = CrawlPhase.over;
        message = 'Out of the ossuary. Well done. Potion button to play again.';
      case RunOutcome.lost:
        phase = CrawlPhase.over;
        message = 'Everybody has fallen. Potion button to try again.';
      case RunOutcome.playing:
        break;
    }
  }

  void _backToChoosing() {
    seats.releaseAll();
    classes.clear();
    message = null;
    phase = CrawlPhase.choosing;
  }

  @override
  void onClose3d() {
    _level?.removeFromParent();
    _loaded?.dispose(device);
    _level = null;
    _loaded = null;
    staged = null;
  }

  FlameInputBridge _keys(Map<LogicalKeyboardKey, GameAction> keys) =>
      FlameInputBridge(
        bindings: Bindings(<InputSource, GameAction>{
          for (final MapEntry(:key, :value) in keys.entries)
            InputSource.key(key.keyId): value,
        }),
        inputState: InputState(),
      );

  FlameInputBridge _pad() {
    final state = InputState();
    final bindings = Bindings(<InputSource, GameAction>{
      InputSource.pad(PadButton.dpadUp.id): GameAction.moveForward,
      InputSource.pad(PadButton.dpadDown.id): GameAction.moveBack,
      InputSource.pad(PadButton.dpadLeft.id): GameAction.moveLeft,
      InputSource.pad(PadButton.dpadRight.id): GameAction.moveRight,
      InputSource.pad(PadButton.faceSouth.id): fire,
      InputSource.pad(PadButton.triggerRight.id): fire,
      InputSource.pad(PadButton.faceEast.id): potion,
    });
    _pads.add(
      PadInput(
        state: state,
        pad: Gamepad(index: _pads.length),
        bindings: bindings,
      ),
    );
    return FlameInputBridge(bindings: bindings, inputState: state);
  }

  static final Map<LogicalKeyboardKey, GameAction> _wasd =
      <LogicalKeyboardKey, GameAction>{
        LogicalKeyboardKey.keyW: GameAction.moveForward,
        LogicalKeyboardKey.keyS: GameAction.moveBack,
        LogicalKeyboardKey.keyA: GameAction.moveLeft,
        LogicalKeyboardKey.keyD: GameAction.moveRight,
        LogicalKeyboardKey.space: fire,
        LogicalKeyboardKey.keyQ: potion,
      };

  static final Map<LogicalKeyboardKey, GameAction> _arrows =
      <LogicalKeyboardKey, GameAction>{
        LogicalKeyboardKey.arrowUp: GameAction.moveForward,
        LogicalKeyboardKey.arrowDown: GameAction.moveBack,
        LogicalKeyboardKey.arrowLeft: GameAction.moveLeft,
        LogicalKeyboardKey.arrowRight: GameAction.moveRight,
        LogicalKeyboardKey.slash: fire,
        LogicalKeyboardKey.period: potion,
      };
}

/// A hero: their body, which the crawl moves, drawn between its steps; turned
/// the way they face; hidden once fallen.
final class _HeroFigure extends CharacterBodyComponent {
  _HeroFigure(this.hero, Scene scene, GraphicsDevice device, StepClock clock)
    : super(
        body: hero.body,
        node: heroFigure(device, hero.kind),
        scene: scene,
        plane: BridgePlane.ground(),
        stepper: clock,
      );

  final Hero hero;

  @override
  void update(double dt) {
    super.update(dt);
    isVisible = hero.isAlive;
    final f = hero.facing;
    // Yaw nought looks along −Z, as an actor's does.
    turnNodeTo(math.atan2(-f.x, -f.z));
  }
}

/// Keeps a component for every monster the horde has and every shot in the
/// air: the simulation makes them, and this is what notices.
final class _Mirror extends Component {
  _Mirror(
    this.crawl,
    Scene scene,
    GraphicsDevice device,
    this.clock,
    this.level,
  ) : _bolts = boltBatch(device),
      _batches = <MonsterKind, InstancedMeshNode>{
        for (final kind in crawl.horde.kinds) kind: monsterBatch(device, kind),
      } {
    scene.add(_bolts);
    _batches.values.forEach(scene.add);
  }

  final StagedCrawl crawl;
  final StepClock clock;
  final Component level;
  final InstancedMeshNode _bolts;
  final Map<MonsterKind, InstancedMeshNode> _batches;
  final Set<Object> _drawn = Set<Object>.identity();

  @override
  void update(double dt) {
    super.update(dt);
    for (final monster in crawl.horde.monsters) {
      if (!_drawn.add(monster)) continue;
      final kind = crawl.horde.kindOf(monster);
      final batch = kind == null ? null : _batches[kind];
      if (batch == null) continue;
      level.add(
        InstancedActorComponent(actor: monster, batch: batch, stepper: clock),
      );
    }
    final volley = crawl.sim.volley;
    for (final bolt in volley.bolts) {
      if (!_drawn.add(bolt)) continue;
      level.add(
        InstancedPoseComponent(
          batch: _bolts,
          place: (Vector3 at) {
            if (!volley.isFlying(bolt)) {
              _drawn.remove(bolt);
              return false;
            }
            at.setFrom(bolt.at);
            return true;
          },
        ),
      );
    }
    _drawn.removeWhere((Object o) => o is Actor && !o.exists);
  }
}
