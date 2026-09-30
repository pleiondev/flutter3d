part of 'river_game.dart';

/// How two players share the river.
enum Versus {
  /// One jet at a time, a lost jet handing over to the other player — on one
  /// machine passing the keys, or on two, one watching while the other
  /// flies.
  turns,

  /// Two machines, both flying the same river at once, each seeing the
  /// other as a ghost.
  race,
}

/// The other machine's jet in a race: drawn where it is on its own run of
/// the same river, see-through, touching nothing.
final class GhostComponent extends Object3dComponent {
  GhostComponent({required super.node, required super.scene})
    : super(
        plane: RiverGame.river,
        direction: SyncDirection.flameToScene,
        elevation: flightHeight,
        size: Vector2(1.5, 1.8),
        anchor: Anchor.center,
      ) {
    tint.setValues(0.55, 0.85, 1.0, 1.0);
    opacity = 0.45;
    visual.setRotation(JetComponent._upRiver);
    isVisible = false;
  }

  /// Rolled as the rival's stick says, as the jet itself is.
  void bankAs(double bank) =>
      visual.setRotation(JetComponent._upRiver * _roll(bank));
}

/// What the other machine last said about itself in a race.
final class Rival {
  int score = 0;
  double distance = 0.0;
  Phase phase = Phase.ready;
}

/// Two players on one river: whose turn it is, who is watching, and the
/// ghost in a race — the river's side of `flame_multiplayer`.
///
/// **The machinery is the package's.** [PeerRoom] is the handshake, a
/// [BatonStream] the turns across two machines, a [PeerFeed] the ghost.
/// What is the river's here is what goes in a frame, which events a
/// watching machine is told, and how it replays them.
///
/// ## Taking turns across two machines
///
/// The machine whose player is flying runs everything a game on its own
/// would: the stick, the hitboxes, the fuel, both players' runs. Each step
/// it tells the other where the jet is and what it did, and the other draws
/// that, a fraction of a second behind. What went down, the bridges and the
/// loss of the jet come as events from the machine that decided them, so
/// the watching machine's own helicopters may turn a little differently and
/// nothing has to agree. When the jet is lost and it is the other player's
/// turn, the whole of [Turns] goes across with the baton.
///
/// ## Racing
///
/// Both fly their own game, of the same river, and tell only where their
/// jet is and what it has scored; the other draws a ghost there and puts
/// the score beside its own.
extension RiverGameVersus on RiverGame {
  /// Starts talking to the other machine over [wire], the room's.
  void goOnline(PeerWire wire) {
    final peers = _room = PeerRoom(wire, slot: slot);
    switch (versus) {
      case Versus.turns:
        _baton = BatonStream(
          peers.channel('turns'),
          holding: false,
          onFrame: _replayFrame,
          onEvent: _hearEvent,
          onBaton: _takeBaton,
        );
      case Versus.race:
        _feed = PeerFeed(peers.channel('ghost'));
      case null:
        break;
    }
  }

  /// Whether this game is waiting to hear from the other machine before the
  /// first take-off.
  bool get waiting => room != null && !_begun;

  /// Whether the jet on screen is the other machine's, replayed.
  bool get watching => _baton?.holding == false;

  /// The ghost's owner, in a race.
  Rival? get rival => _rival;

  /// Whether this machine tells the other what its jet does.
  bool get _streaming => _baton?.holding ?? false;

  /// The first turn on one machine: nothing to wait for.
  void _beginAlone() {
    if (versus == null || room != null) return;
    _begun = true;
    turns?.reset(checkpoint: run.checkpoint);
    _takeTurn();
  }

  /// Makes [turns]' player the one flying, from their own checkpoint.
  void _takeTurn() {
    run = turns!.current;
    _restart();
  }

  /// Hands the jet on after a loss, or ends the game.
  void _passTurn() {
    final t = turns!;
    final next = t.next();
    if (next == null) {
      phase = Phase.over;
      _baton?.tellEvent(<String, Object?>{'t': 'over', 'turns': t.toJson()});
      return;
    }
    final baton = _baton;
    if (baton != null && next != slot) {
      // The other machine's player: it flies, this one watches.
      baton.pass(t.toJson());
    } else {
      baton?.tellEvent(<String, Object?>{'t': 'turn', 'turns': t.toJson()});
    }
    _takeTurn();
  }

  /// This machine holds the game now, with [state] its turn starts from.
  void _takeBaton(Map<String, Object?> state) {
    _begun = true;
    turns!.load(state);
    _takeTurn();
  }

  /// Fire at the end: another game.
  ///
  /// Online, the machine that held the game when it ended starts the next,
  /// the room's maker's player first; the other asks it to.
  void _again() {
    final t = turns;
    final baton = _baton;
    if (t == null) {
      run = RunState();
      _restart();
      return;
    }
    if (baton != null && !baton.holding) {
      baton.tellEvent(const <String, Object?>{'t': 'again'});
      return;
    }
    t.reset();
    if (baton != null && slot != 0) {
      baton.pass(t.toJson());
    } else {
      baton?.tellEvent(<String, Object?>{'t': 'turn', 'turns': t.toJson()});
    }
    _takeTurn();
  }

  /// Once a step, before it: the room's hello, the first turn once the
  /// other machine is here, and what it has sent since.
  void _hear(double dt) {
    final peers = _room;
    if (peers == null) return;
    peers.step(dt);
    if (!_begun && peers.met) {
      if (versus == Versus.race) {
        _begun = true;
      } else if (slot == 0) {
        _begun = true;
        final t = turns!..reset(checkpoint: run.checkpoint);
        _baton!.take();
        _baton!.tellEvent(<String, Object?>{'t': 'turn', 'turns': t.toJson()});
        _takeTurn();
      }
    }
    _baton?.step();
    final said = _feed?.latest;
    if (said != null) _ghostFrame(said);
    // Watching, the fire button at the end is a request to the one holding
    // the game, which [_step] does not see.
    if (watching && phase == Phase.over && input.pressed(RiverGame.fire)) {
      _again();
    }
  }

  void _hearEvent(Map<String, Object?> event) {
    switch (event['t']) {
      case 'turn':
        if (event['turns'] case final Map<Object?, Object?> json) {
          _begun = true;
          turns!.load(json.cast<String, Object?>());
          _takeTurn();
        }
      case 'over':
        if (event['turns'] case final Map<Object?, Object?> json) {
          turns!.load(json.cast<String, Object?>());
        }
        phase = Phase.over;
      case 'again':
        if (phase == Phase.over) _again();
      case 'hit' when watching:
        final target = _targetAt(event['s'], event['i']);
        if (target != null) _replaying(() => hitTarget(target));
      case 'bridge' when watching:
        final bridge = _stretches[_int(event['s'])]?.bridge;
        if (bridge != null) {
          _replaying(
            () => hitBridge(
              bridge,
              at: Vector2(_double(event['x']), _double(event['y'])),
              fell: event['down'] == true,
            ),
          );
        }
      case 'crash' when watching:
        final cause = _int(event['c']);
        if (cause >= 0 && cause < Crash.values.length) {
          _replaying(() => crash(Crash.values[cause]));
        }
    }
  }

  void _replaying(void Function() it) {
    _isReplaying = true;
    try {
      it();
    } finally {
      _isReplaying = false;
    }
  }

  /// After a step: where the jet is and how it is flying, for the other
  /// machine to replay or to draw as a ghost.
  void _tell() {
    final shot = _shotThisStep;
    _shotThisStep = false;
    if (!_begun) return;
    final baton = _baton;
    if (baton != null && baton.holding) {
      baton.tellFrame(<String, Object?>{
        ..._pose(),
        'v': speed,
        if (shot) 'shot': true,
        if (refuelling) 'fill': true,
        'turns': turns!.toJson(),
      });
    }
    _feed?.tell(() => <String, Object?>{..._pose(), 'score': run.score});
  }

  Map<String, Object?> _pose() => <String, Object?>{
    'x': jet.position.x,
    'y': jet.position.y,
    'b': jet.bank,
    'p': phase.index,
  };

  /// Tells the other machine something went down, when it is this one's
  /// jet that brought it down.
  void _tellHit(TargetComponent target) {
    if (!_streaming || _isReplaying) return;
    for (final stretch in _stretches.chunks) {
      final i = stretch.targets.indexOf(target);
      if (i >= 0) {
        _baton!.tellEvent(<String, Object?>{
          't': 'hit',
          's': stretch.index,
          'i': i,
        });
        return;
      }
    }
  }

  void _tellBridge(BridgeComponent bridge, Vector2 at, {required bool fell}) {
    if (!_streaming || _isReplaying) return;
    _baton!.tellEvent(<String, Object?>{
      't': 'bridge',
      's': bridge.section,
      'x': at.x,
      'y': at.y,
      'down': fell,
    });
  }

  void _tellCrash(Crash cause) {
    if (!_streaming || _isReplaying) return;
    _baton!.tellEvent(<String, Object?>{'t': 'crash', 'c': cause.index});
  }

  TargetComponent? _targetAt(Object? section, Object? index) {
    final targets = _stretches[_int(section)]?.targets;
    final i = _int(index);
    if (targets == null || i < 0 || i >= targets.length) return null;
    return targets[i];
  }

  /// One step of somebody else's flight.
  void _replayFrame(Map<String, Object?> frame) {
    jet.position.setValues(_double(frame['x']), _double(frame['y']));
    jet
      ..bank = _double(frame['b'])
      ..visual.setRotation(JetComponent._upRiver * _roll(jet.bank));
    speed = _double(frame['v']);
    refuelling = frame['fill'] == true;
    final p = _int(frame['p']);
    // Down is the crash event's to say, with its fire and smoke.
    if (p >= 0 && p < Phase.values.length && Phase.values[p] != Phase.crashed) {
      phase = Phase.values[p];
    }
    if (frame['shot'] == true) _fire();
    if (frame['turns'] case final Map<Object?, Object?> json) {
      turns!.load(json.cast<String, Object?>());
    }
    _ensureStretches();
  }

  void _ghostFrame(Map<String, Object?> frame) {
    final seen = _rival!;
    final ghost = _ghost!;
    ghost.position.setValues(_double(frame['x']), _double(frame['y']));
    ghost.bankAs(_double(frame['b']));
    seen
      ..score = _int(frame['score'])
      ..distance = -_double(frame['y']);
    final p = _int(frame['p']);
    if (p >= 0 && p < Phase.values.length) seen.phase = Phase.values[p];
    ghost.isVisible = seen.phase == Phase.flying || seen.phase == Phase.ready;
  }

  /// The ghost, made with the river in a race.
  void _addGhost() {
    if (versus != Versus.race) return;
    final ghost = GhostComponent(
      node: SceneNode(name: 'ghost'),
      scene: _scene,
    );
    ghost.visual.add(
      MeshNode(_kit.playerJet, _kit.painted, name: 'ghost primitive'),
    );
    wardrobe.dress(ghost.visual, Craft.player);
    _ghost = ghost;
    _rival = Rival();
    add(ghost);
  }

  static int _int(Object? value) => (value as num?)?.toInt() ?? -1;
  static double _double(Object? value) => (value as num?)?.toDouble() ?? 0.0;
}
