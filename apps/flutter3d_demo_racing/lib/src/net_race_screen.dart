import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_race_session.dart';
import 'party_race_session.dart';

/// `net-03`'s own missing screen: "создать / войти по коду".
///
/// **What this proves, and what it does not.** `NetRace`/`NetRaceSession`
/// already carry the whole race — input delay, prediction, rollback,
/// which grid slot is whose, the ghost before a peer has said anything —
/// and are proved against the real, shipped `RacingSimulation` in
/// `net_race_test.dart` and `net_race_session_test.dart`. What was
/// missing, and what this widget builds, is the two-button door into that
/// mechanism and the one indicator a player watching an empty seat needs:
/// whether the other side has actually said anything yet. Drawing the
/// race itself — two cars on the circuit, not a line of text about them —
/// is the single-player game's own render loop in `main.dart`, wiring a
/// `NetRaceSession` into it is further integration this screen does not
/// attempt, the same class of boundary `rp-02`/`net-02` already named for
/// "the running game in an open window".
final class NetRaceScreen extends StatefulWidget {
  const NetRaceScreen({
    super.key,
    required this.relayBase,
    this.trackAsset = 'assets/tracks/ring.json',
    this.onEnded,
  });

  /// `ws://host:port/` — the relay's own root; a room is `relayBase`
  /// resolved against `room/<code>`, the shape `bin/relay.dart` listens on.
  final Uri relayBase;
  final String trackAsset;

  /// Called with the finished [NetRaceSession] when "End race" is pressed,
  /// before it is disposed — a caller decides where its `.f3drun` goes
  /// (a save panel, a fixed path, a test's own temp directory) rather than
  /// this widget guessing a location nobody asked for.
  final void Function(NetRaceSession session)? onEnded;

  @override
  State<NetRaceScreen> createState() => _NetRaceScreenState();
}

enum _Phase { idle, connecting, racing, failed }

final class _NetRaceScreenState extends State<NetRaceScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;
  NetRaceSession? _session;

  /// A race of three or four, when that is what was made or joined — the
  /// other door on this screen, onto the relay's parties.
  PartyRaceSession? _party;
  int _partySize = PartyRaceSession.sizes.last;

  /// How many of the party's other drivers have been heard, polled as
  /// [_connected] is.
  int _heard = 0;

  /// Whether every car of the party has its driver, polled as [_heard] is.
  bool _full = false;
  Timer? _ticker;
  final TextEditingController _codeField = TextEditingController();
  final InputState _input = InputState();

  /// Rebuilt on every tick so [NetRaceSession.connected] reaches the
  /// screen — the mechanism itself is polled rather than pushed, the same
  /// way `main.dart`'s own render loop reads simulation state each frame
  /// rather than subscribing to it.
  bool _connected = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _session?.dispose();
    _party?.dispose();
    _codeField.dispose();
    super.dispose();
  }

  Future<void> _createRoom() => _connect(join: false);

  Future<void> _joinRoom() =>
      _connect(join: true, code: _codeField.text.trim());

  /// The circuit, and a world with its walls in it on the run's physics.
  Future<({TrackDocument document, CollisionWorld world})> _track() async {
    final text = await rootBundle.loadString(widget.trackAsset);
    final document = TrackDocument.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );
    final world = CollisionWorld();
    document.level?.addTo(world);
    // On the run's physics, as a track loaded alone is.
    usePhysics().attach(world);
    return (document: document, world: world);
  }

  /// Makes a party of [_partySize], or with [code] joins one, or with
  /// [find] is seated among strangers who asked for the same race.
  Future<void> _openParty({String? code, bool find = false}) async {
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    try {
      final (:document, :world) = await _track();
      final party = await PartyRaceSession.open(
        relayBase: widget.relayBase,
        document: document,
        world: world,
        input: _input,
        code: code,
        size: _partySize,
        find: find,
        circuit: widget.trackAsset,
      );
      if (!mounted) {
        await party.dispose();
        return;
      }
      setState(() {
        _party = party;
        _phase = _Phase.racing;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 1000 ~/ 60), (_) {
        party.advance();
        _input.endStep();
        if (party.heard != _heard || party.full != _full) {
          setState(() {
            _heard = party.heard;
            _full = party.full;
          });
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$error';
      });
    }
  }

  Future<void> _connect({required bool join, String? code}) async {
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    try {
      final (:document, :world) = await _track();

      final session = join
          ? await NetRaceSession.join(
              relayBase: widget.relayBase,
              document: document,
              world: world,
              input: _input,
              trackAsset: widget.trackAsset,
              roomCode: code!,
            )
          : await NetRaceSession.create(
              relayBase: widget.relayBase,
              document: document,
              world: world,
              input: _input,
              trackAsset: widget.trackAsset,
            );
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _phase = _Phase.racing;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 1000 ~/ 60), (_) {
        // Turned away by the relay — another machine's physics, a room
        // already holding two: say so rather than race a ghost.
        if (session.closedBecause case final String reason) {
          _ticker?.cancel();
          session.dispose();
          setState(() {
            _session = null;
            _phase = _Phase.failed;
            _error = reason;
          });
          return;
        }
        session.advance();
        _input.endStep();
        if (session.connected != _connected) {
          setState(() => _connected = session.connected);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$error';
      });
    }
  }

  Future<void> _end() async {
    _ticker?.cancel();
    final session = _session;
    if (session != null) widget.onEnded?.call(session);
    await session?.dispose();
    await _party?.dispose();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _session = null;
      _party = null;
      _connected = false;
      _heard = 0;
      _full = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Race with a friend')),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.idle:
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_error != null) ...<Widget>[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16.0),
              ],
              FilledButton(
                onPressed: _createRoom,
                child: const Text('Create room'),
              ),
              const SizedBox(height: 24.0),
              SizedBox(
                width: 200.0,
                child: TextField(
                  controller: _codeField,
                  decoration: const InputDecoration(labelText: 'Room code'),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(height: 8.0),
              FilledButton(onPressed: _joinRoom, child: const Text('Join')),
              const SizedBox(height: 32.0),
              const Text('Or a party, a car each'),
              const SizedBox(height: 8.0),
              SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  for (final size in PartyRaceSession.sizes)
                    ButtonSegment<int>(value: size, label: Text('$size cars')),
                ],
                selected: <int>{_partySize},
                onSelectionChanged: (Set<int> chosen) =>
                    setState(() => _partySize = chosen.single),
              ),
              const SizedBox(height: 8.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FilledButton(
                    onPressed: _openParty,
                    child: const Text('Make a party'),
                  ),
                  const SizedBox(width: 8.0),
                  // The code field above serves both doors: a party's code
                  // is a room's, five letters nobody misreads.
                  FilledButton(
                    onPressed: () =>
                        _openParty(code: _codeField.text.trim().toUpperCase()),
                    child: const Text('Join the party'),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              // No code to pass round: the relay seats this machine with
              // whoever else asked for a race of this size on this circuit.
              OutlinedButton(
                onPressed: () => _openParty(find: true),
                child: const Text('Find a race'),
              ),
            ],
          ),
        );
      case _Phase.connecting:
        return const CircularProgressIndicator();
      case _Phase.failed:
        return Text('could not connect: $_error');
      case _Phase.racing:
        if (_party case final PartyRaceSession party) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Party ${party.code} — car ${party.localCarIndex + 1} of '
                '${party.size}',
              ),
              const SizedBox(height: 8.0),
              Text(
                _full
                    ? 'Heard $_heard of ${party.size - 1} drivers'
                    : 'Waiting for drivers to fill the grid…',
                key: const Key('party-heard'),
              ),
              const SizedBox(height: 24.0),
              FilledButton(onPressed: _end, child: const Text('End race')),
            ],
          );
        }
        final session = _session!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Room ${session.roomCode} — car ${session.localCarIndex}'),
            const SizedBox(height: 8.0),
            Text(
              _connected ? 'Opponent connected' : 'Waiting for opponent…',
              key: const Key('ghost-indicator'),
            ),
            const SizedBox(height: 24.0),
            FilledButton(onPressed: _end, child: const Text('End race')),
          ],
        );
    }
  }
}
