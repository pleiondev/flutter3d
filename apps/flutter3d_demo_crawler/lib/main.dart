/// Up to four heroes, one screen, and a maze that keeps making monsters.
///
///     flutter run -d macos
///
/// Press fire to join — Space on WASD, / on the arrows, or the bottom face
/// button on a controller — move sideways to choose a class, and press the
/// potion button to go in. Everybody shares one view, which rises as the party
/// spreads out and stops anybody walking off its edge. Health drains by the
/// second; food brings it back. A key opens any one locked door. Walking into
/// a monster is fighting it; a potion clears everything on screen.
///
/// The simulation is `flutter3d_game_crawler` and it is stepped on a fixed
/// sixtieth: a frame's worth of real time is spent in whole steps and the rest
/// kept for the next frame. Nothing here decides anything about the crawl; it
/// reads the players' hands before the steps, and draws what the steps did.
library;

import 'dart:async';

// Flutter's `Hero` is a page transition; this game's is somebody holding a
// controller.
import 'package:flutter/material.dart' hide Hero, Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show FixtureVisuals;
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show FixedStep, RunOutcome;

import 'src/backend.dart';
import 'src/controls.dart';
import 'src/crawl_visuals.dart';
import 'src/hud.dart';
import 'src/level_open.dart';
import 'src/staging.dart';

/// A party to go straight in with, skipping the select screen:
/// `--dart-define=CRAWLER_PARTY=warrior,elf`. For a demo on a machine with
/// nobody at the keys, and for looking at a level without choosing first. The
/// heroes stand still until somebody takes a seat's keys: the first on WASD,
/// the second on the arrows.
const String _party = String.fromEnvironment('CRAWLER_PARTY');

void main() => runApp(const CrawlerDemo());

class CrawlerDemo extends StatelessWidget {
  const CrawlerDemo({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Crawler',
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: Color(0xFF0C0B10), body: _Crawl()),
  );
}

/// Where the game is between its screens.
enum _Phase { choosing, loading, playing, between, over }

class _Crawl extends StatefulWidget {
  const _Crawl();

  @override
  State<_Crawl> createState() => _CrawlState();
}

class _CrawlState extends State<_Crawl> with SingleTickerProviderStateMixin {
  /// The longest real frame the crawl will accept, in seconds: longer is a
  /// window being dragged, and handing all of it to the steps teleports the
  /// horde.
  static const double _longestFrame = 0.25;

  /// A beat between one level and the next.
  static const double _pause = 2.0;

  final Controls _controls = Controls();
  final FixedStep _clock = FixedStep();
  final Announcer _announcer = Announcer();

  Renderer? _renderer;
  Ticker? _ticker;
  Duration _since = Duration.zero;

  _Phase _phase = _Phase.choosing;
  String? _message;

  Scene? _scene;
  late CameraNode _camera;
  late RenderView _view;
  StagedCrawl? _staged;
  FixtureVisuals? _fixtures;
  CrawlVisuals? _visuals;
  LoadedLevelHandle? _loaded;
  CrawlCamera _crawlCamera = CrawlCamera();
  double _levelTime = 0.0;
  double _waited = 0.0;
  String? _title;

  @override
  void initState() {
    super.initState();
    // From the keyboard itself rather than from a focus node: a press has to
    // arrive whichever widget holds the focus, and the held keys the players
    // walk with are read the same way. A `Focus.onKeyEvent` saw nothing once
    // the focus went elsewhere, so joining worked and starting did not.
    HardwareKeyboard.instance.addHandler(_controls.onKey);
    unawaited(_open());
  }

  Future<void> _open() async {
    final device = await openDevice(width: 1280, height: 720);
    if (!mounted) return device.dispose();
    _ticker = createTicker(_frame)..start();
    setState(() => _renderer = Renderer.create(device: device));
    if (_party.isNotEmpty) {
      final keyboards = <Keys>[Keys.wasd, Keys.arrows];
      final names = _party.split(',');
      for (var i = 0; i < names.length && i < keyboards.length; i++) {
        final kind = HeroClass.all.firstWhere(
          (HeroClass k) => k.name == names[i].trim(),
          orElse: () => HeroClass.all[i],
        );
        _controls.seats.add(Seat(keyboards[i], kind));
      }
      unawaited(_enter(firstLevel));
    }
  }

  Future<void> _enter(
    String name, {
    List<Hero> carried = const <Hero>[],
  }) async {
    final renderer = _renderer;
    if (renderer == null) return;
    setState(() => _phase = _Phase.loading);
    _close();
    final device = renderer.device;
    final (:kinds, :loaded, :fixtures) = await openLevel(
      levelAsset(name),
      device: device,
    );
    if (!mounted) return;
    final staged = stage(
      loaded.level,
      loaded.collision,
      party: <HeroClass>[for (final seat in _controls.seats) seat.kind],
      carried: carried,
      registry: kinds,
      onFixture: fixtures.add,
    );
    final visuals = CrawlVisuals(device: device, heroes: staged.sim.heroes)
      ..addTo(loaded.scene);
    _camera = loaded.scene.add(
      CameraNode(
        name: 'camera',
        projection: PerspectiveProjection(
          fovYRadians: staged.sim.framing.tuning.fieldOfView,
          far: 200.0,
        ),
      ),
    );
    _view = RenderView(camera: _camera);
    _crawlCamera = CrawlCamera();
    setState(() {
      _scene = loaded.scene;
      _loaded = LoadedLevelHandle(loaded, device);
      _staged = staged;
      _fixtures = fixtures;
      _visuals = visuals;
      _levelTime = 0.0;
      _title = loaded.level.name;
      _phase = _Phase.playing;
    });
  }

  void _close() {
    _fixtures?.dispose();
    _loaded?.dispose();
    _fixtures = null;
    _loaded = null;
    _staged = null;
    _visuals = null;
    _scene = null;
  }

  void _frame(Duration elapsed) {
    final double frame =
        (elapsed - _since).inMicroseconds / Duration.microsecondsPerSecond;
    _since = elapsed;
    final double dt = frame.isNaN ? 0.0 : frame.clamp(0.0, _longestFrame);

    switch (_phase) {
      case _Phase.choosing:
        if (_controls.choose()) unawaited(_enter(firstLevel));
        setState(() {});
      case _Phase.loading:
        break;
      case _Phase.playing:
        _play(dt);
      case _Phase.between:
        _waited += dt;
        _draw(dt);
        if (_waited >= _pause) {
          final next = _staged?.sim.nextLevel;
          final heroes = _staged?.sim.heroes ?? const <Hero>[];
          if (next != null) unawaited(_enter(next, carried: heroes));
        }
      case _Phase.over:
        _draw(dt);
        // A press of the potion button goes back to choosing.
        if (_controls.choose()) {
          _controls.seats.clear();
          setState(() {
            _close();
            _phase = _Phase.choosing;
          });
        }
    }
  }

  void _play(double dt) {
    final staged = _staged;
    if (staged == null) return;
    final sim = staged.sim;
    _controls.drive(sim.heroes);
    final steps = _clock.advance(dt);
    for (var i = 0; i < steps; i++) {
      sim.step(_clock.stepSeconds);
      _announcer.hear(sim.events.drain());
    }
    _levelTime += dt;
    _draw(dt);
    switch (sim.outcome) {
      case RunOutcome.won when sim.nextLevel != null:
        _waited = 0.0;
        _phase = _Phase.between;
        _message = 'Through! On to ${sim.nextLevel}.';
      case RunOutcome.won:
        _phase = _Phase.over;
        _message =
            'Out of the ossuary. Well done. Potion button to play again.';
      case RunOutcome.lost:
        _phase = _Phase.over;
        _message = 'Everybody has fallen. Potion button to try again.';
      case RunOutcome.playing:
        break;
    }
  }

  void _draw(double dt) {
    final staged = _staged;
    if (staged == null) return;
    _announcer.pass(dt);
    _visuals?.sync(staged.sim, staged.horde);
    _fixtures?.sync(_levelTime);
    _crawlCamera.follow(staged.sim.framing, dt);
    _camera
      ..setPositionFrom(_crawlCamera.eye)
      ..lookAt(_crawlCamera.target);
    setState(() {});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_controls.onKey);
    _ticker?.dispose();
    _close();
    final renderer = _renderer;
    if (renderer != null) {
      renderer.dispose();
      renderer.device.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_phase) {
    _Phase.choosing => _Choosing(seats: _controls.seats),
    _Phase.loading => const _Centred('…'),
    _ => _playing(context),
  };

  Widget _playing(BuildContext context) {
    final renderer = _renderer;
    final scene = _scene;
    final staged = _staged;
    if (renderer == null || scene == null || staged == null) {
      return const _Centred('…');
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: scene,
          views: <RenderView>[_view],
          settings: crawlRenderSettings,
        );
        return Stack(
          children: <Widget>[
            Positioned.fill(child: presentFrame(renderer.device, frame.frame)),
            CrawlHud(
              heroes: staged.sim.heroes,
              lines: <String>[
                ..._announcer.lines,
                if (_phase != _Phase.playing) ?_message,
              ],
              title: _levelTime < 2.5 ? _title : null,
            ),
          ],
        );
      },
    );
  }
}

/// The select screen: who has joined, as what, and how to join.
class _Choosing extends StatelessWidget {
  const _Choosing({required this.seats});

  final List<Seat> seats;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: const TextStyle(color: Color(0xFFE8E2D6), fontSize: 18.0),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'CRAWLER',
            style: TextStyle(fontSize: 56.0, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24.0),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: i < seats.length
                  ? Text(
                      'Player ${i + 1}: ${seats[i].kind.name}',
                      style: TextStyle(
                        color: _colour(seats[i].kind),
                        fontSize: 24.0,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Text(
                      'Player ${i + 1}: free — ${_howToJoin(i)}',
                      style: const TextStyle(color: Color(0xFF807A70)),
                    ),
            ),
          const SizedBox(height: 24.0),
          Text(
            'Two can share the keyboard:\n'
            '  left hand — ${Keys.wasd.name}\n'
            '  right hand — ${Keys.arrows.name}\n'
            'Players three and four need a controller: stick to move, A to '
            'fire, B for a potion.\n\n'
            'Joined: move left or right to change class.\n'
            'When everybody is in, press a potion button (Q or .) to start.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB8B0A2), fontSize: 15.0),
          ),
        ],
      ),
    ),
  );

  /// Seats go in the order people join, so a free seat can be taken by any
  /// device nobody is holding yet; what is shown is what is still unclaimed.
  String _howToJoin(int seat) {
    final keyboards = <Keys>[
      for (final keys in <Keys>[Keys.wasd, Keys.arrows])
        if (!seats.any((Seat s) => identical(s.device, keys))) keys,
    ];
    final taken = seat - seats.length;
    if (taken < keyboards.length) {
      return identical(keyboards[taken], Keys.wasd)
          ? 'press Space'
          : 'press / (right hand, on the arrows)';
    }
    return 'press A on a controller';
  }

  static Color _colour(HeroClass kind) {
    final c = colourOf(kind);
    return Color.fromARGB(
      255,
      (c.x * 255).round(),
      (c.y * 255).round(),
      (c.z * 255).round(),
    );
  }
}

class _Centred extends StatelessWidget {
  const _Centred(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(text, style: const TextStyle(color: Color(0xFFE8E2D6))),
  );
}

/// A loaded level and the device its resources live on, released together.
final class LoadedLevelHandle {
  LoadedLevelHandle(this.level, this.device);

  final LoadedLevel level;
  final GraphicsDevice device;

  void dispose() => level.dispose(device);
}
