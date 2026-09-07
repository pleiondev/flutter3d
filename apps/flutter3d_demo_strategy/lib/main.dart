/// A crowd on a hillside: the fourth genre, drawn.
///
///     flutter run -d macos
///
/// A match: your camp in the near corner, a bot's in the far one, both digging
/// the same hillside for the same finishing line. Drag a rectangle to pick out
/// workers, click the ground to send the ones you picked — which takes *them*
/// off their work, the way an order does, and leaves everybody else digging.
/// Drag with the right button to push the view, and use the scroll wheel to
/// pull it back.
///
/// **The primary drag had to be given up to get a selection.** It pushed the
/// view until this screen could pick anybody out, and a rectangle is the only
/// gesture a crowd game can be played with; the view moved to the button that
/// was doing nothing. That is why the controls are written across the bottom of
/// the screen — see `controlsHint`.
///
/// **Units are picked out by a ray, halls by the picking pass, and the split is
/// forced.** `Renderer.pickPixel` answers with the node that was drawn, and the
/// whole crowd is one instanced batch — it can say a unit was clicked and never
/// which one. So `Selection` in the game package tests the ray against each
/// unit's radius, and the pass keeps the buildings, where a silhouette is a
/// better answer than the box around a hall.
///
/// **The map is drawn through your eyes, not the simulation's.** Ground nobody
/// of yours has been to is under fog, ground you have left is dim, and the
/// other side's crowd is drawn only where you can see it. Hovering asks the
/// renderer what is actually under the pointer — by pixel, not by bounding box
/// — and lights it.
///
/// **The match is played on a fixed step and written down as it goes.** A
/// frame's worth of real time is spent in whole sixtieths and the leftover is
/// kept for the next one, so a slow frame is a frame that ran three steps rather
/// than one long one — which is the difference between a crowd that keeps
/// walking at the same speed on any display and one that walks faster on a fast
/// machine. The run itself is a `RunSession`: it resumes the saved match on
/// launch, writes it down every few seconds, and forgets it once somebody has
/// won. See `src/run.dart`.
///
/// Nothing here decides anything about the simulation: it steps, the bridge
/// reads it, and the camera watches — which is the arrangement every game in
/// this repository has, seen at the one scale where a thousand of something is
/// ordinary. The bot is not an exception to that: it writes the same orders
/// through the same handles as the click above, one thought every half second.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show FixedStep;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/backend.dart';
import 'src/command.dart';
import 'src/hud.dart';
import 'src/hud_readout.dart';
import 'src/level_document.dart';
import 'src/pointing.dart';
import 'src/run.dart';
import 'src/staging.dart';

void main() => runApp(const StrategyDemo());

/// The application.
class StrategyDemo extends StatelessWidget {
  /// Builds it.
  const StrategyDemo({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: Color(0xFF10131A), body: _Map()),
  );
}

class _Map extends StatefulWidget {
  const _Map();

  @override
  State<_Map> createState() => _MapState();
}

class _MapState extends State<_Map> with SingleTickerProviderStateMixin {
  /// The longest real frame the match will accept, in seconds.
  ///
  /// A frame longer than this is not a slow frame — it is a window being
  /// dragged, a lid being shut, or a debugger sitting on a breakpoint — and
  /// handing the whole of it to a fixed step asks for a minute of simulation at
  /// once, which arrives as the entire crowd teleporting.
  static const double _longestFrame = 0.25;

  /// How long the match runs between one autosave and the next, in seconds.
  ///
  /// **A match has no checkpoints to hang a save on**, which is what makes this
  /// a clock rather than an event: the other genres write the run down at a door
  /// or a start line, and the only comparable moment here is the end, which is
  /// exactly when a save must *not* be written. Five seconds is a few hundred
  /// steps — cheap against a step over a crowd of hundreds, and short enough
  /// that a launch after a crash resumes somewhere a player recognises.
  static const double _saveEvery = 5.0;

  /// How far a pointer may travel and still have been a click, in pixels.
  ///
  /// Without it every click is a rectangle a pixel wide, which selects nobody
  /// and, worse, is indistinguishable from the click that was meant to send the
  /// squad somewhere.
  static const double _slop = 4.0;

  Renderer? _renderer;
  Staged? _staged;

  /// Whom the player has picked out, and the one door their orders go through.
  ///
  /// **State on the widget, because a selection is not a fact about the
  /// match.** Nothing in the simulation knows or should know which six of six
  /// hundred workers somebody has a rectangle round; it is the same kind of
  /// thing as where the camera is pointing. Built in [_place] because it needs
  /// the simulation the document made, and rebuilt whenever a new one is.
  CommandPost? _command;

  /// The corners of the rectangle being dragged, in widget coordinates, or null
  /// when nothing is being dragged.
  Offset? _bandFrom;
  Offset? _bandTo;

  /// Whether the drag under way is pushing the view rather than selecting.
  bool _panning = false;

  late final Scene _scene;
  late final RenderView _view;
  late final CameraNode _camera;

  /// The frame source, once there is something to spend a frame on.
  ///
  /// Nullable rather than `late final`, because there are now two awaits
  /// between this widget being built and this being started: a widget taken
  /// away in either gap used to reach `dispose` with nothing here to dispose.
  Ticker? _ticker;
  final Raycaster _ray = Raycaster();
  Size _surface = const Size(1280, 720);

  /// The run: which map is up, how it is going, and where it is written down.
  StrategyRun? _run;

  /// Real time turned into whole steps of simulated time.
  ///
  /// **Two of what it offers are deliberately not read here, and saying which
  /// is worth more than pretending otherwise.** `alpha` is the fraction of a
  /// step the frame sits past the last one, for a picture that draws between
  /// two simulated states; the crowd is one instanced batch written from where
  /// everybody is *now*, and blending would mean the batch keeping each unit's
  /// previous transform as well — a second buffer of a thousand matrices, for a
  /// unit that is a few pixels across from a camera this high up. `droppedSteps`
  /// is the count of simulated time thrown away when a frame asked for more
  /// steps than the ceiling allows, and it belongs in a frame overlay this demo
  /// does not have. Both are the clock's to report the day either is worth
  /// spending; neither is worth faking a use for today.
  final FixedStep _clock = strategyClock();

  /// What the ticker read last, so a frame can be told from a total.
  ///
  /// A `Ticker` reports how long it has been running rather than how long the
  /// last frame took, and the difference between the two is the whole of what a
  /// fixed step is fed.
  Duration _since = Duration.zero;

  /// Simulated seconds since the run was last written down.
  double _unsaved = 0.0;

  /// Whether a picking question is already waiting on a frame.
  bool _asking = false;

  /// The building the cursor is over, lit.
  MeshNode? _lit;

  /// What the cursor is over, by name, for the line in the corner.
  String? _under;

  @override
  void initState() {
    super.initState();
    _open();
  }

  /// Opens the device, the scene over it, and the run played in that scene.
  ///
  /// **The map is no longer read here**, and that is the change this file came
  /// with: reading it is `StrategyRun.open`'s job, so that the same sequence
  /// which reads it can also resume the match that was saved from it. The
  /// device is opened first because a session asks for one while it loads, and
  /// the guard below is what the map-first ordering used to buy — a device that
  /// outlived the widget it was opened for is a device nobody frees.
  Future<void> _open() async {
    final device = await openDevice(width: 1280, height: 720);
    if (!mounted) return device.dispose();

    // The scene, and the one thing in it that belongs to the view rather than
    // to any particular match: a sun does not come out of the document.
    _scene = Scene(name: 'map');
    _scene.add(
      LightNode(
        type: LightType.directional,
        color: vm.Vector3(1.0, 0.96, 0.88),
        intensity: 3.2,
        name: 'sun',
      )..lookAt(vm.Vector3(0.35, -1.0, 0.5)),
    );
    _camera = _scene.add(CameraNode(name: 'camera'));
    _view = RenderView(camera: _camera);

    final run = StrategyRun(
      firstLevel: mapAsset,
      saves: SaveFile(appName: 'flutter3d_demo_strategy'),
      openDevice: () async => device,
      onLevelBuilt: _place,
    );
    _run = run;
    // Resumes the saved match if there is one, and starts a fresh one if there
    // is not. Either way the map is whole before anything is put back into it.
    await run.begin();
    if (!mounted) return;

    _ticker = createTicker(_frame)..start();
    setState(() => _renderer = Renderer.create(device: device));
  }

  /// Takes a staged match and gives the screen its half of it.
  ///
  /// Called from inside `StrategyRun.open`, before the session restores
  /// anything — the visuals and the command post are part of "the level is
  /// whole", and a snapshot arrives after that.
  void _place(Staged staged) {
    staged.visuals.addTo(_scene);
    _staged = staged;
    _command = CommandPost(simulation: staged.simulation, side: viewerSide);
  }

  /// One frame: whole steps of the match, then the picture over them.
  void _frame(Duration elapsed) {
    final Staged? staged = _staged;
    final CommandPost? command = _command;
    final StrategyRun? run = _run;
    if (staged == null || command == null || run == null) return;

    // Clamped once, here, and everything else in the frame is given the clamped
    // number: the camera eases in real time rather than in steps, and handing it
    // the raw frame after a hitch would swing the view somewhere the match has
    // not been.
    final double frame =
        (elapsed - _since).inMicroseconds / Duration.microsecondsPerSecond;
    _since = elapsed;
    final double dt = frame.isNaN ? 0.0 : frame.clamp(0.0, _longestFrame);

    final int steps = _clock.advance(dt);
    for (var i = 0; i < steps; i++) {
      // The near camp has no policy behind it, and a hall makes nothing it was
      // not asked for, so without this the player's side would open with the
      // crowd the document gave it and never gain another while the far camps
      // grew. Asked before the step so the order is in the queue the step
      // drains.
      command.restock();
      staged.match.step(_clock.stepSeconds);
      // Before the picture and before the readout: a squad the player is
      // holding may have lost somebody to the step that just ran, and both the
      // count on the screen and the next order given would otherwise be about a
      // crowd that is one larger than the one on the map. Cheap — it walks the
      // crowd only while something is selected.
      command.prune();
    }

    // Once the steps have run and never between two of them: a save taken
    // mid-frame would describe a match half a frame old, and the outcome the
    // session republishes has to be the one the last step decided.
    run.observe();
    _keep(run, steps * _clock.stepSeconds);

    staged.visuals.sync();
    staged.camera.place(dt);
    _camera
      ..setPositionFrom(staged.camera.eye)
      ..lookAt(staged.camera.target);
    setState(() {});
  }

  /// Writes the run down every [_saveEvery] seconds, and lets it go when it
  /// ends.
  ///
  /// **The ending is the session's business, not this file's.** `advance` is
  /// what clears the save on a finished match — and it does nothing twice, so a
  /// match that stays won for every frame afterwards is written off once. Left
  /// to a widget, the same three lines would run sixty times a second and the
  /// save would be deleted again on every one of them.
  ///
  /// `RunSession.save` refuses a finished run of its own accord, so the clock
  /// below needs no guard against writing one down at the finishing line.
  void _keep(StrategyRun run, double seconds) {
    if (run.isOver) {
      unawaited(run.advance());
      return;
    }
    _unsaved += seconds;
    if (_unsaved < _saveEvery) return;
    _unsaved = 0.0;
    run.save();
  }

  /// Aims [_ray] through a point on the widget, and hands back the world ray.
  ///
  /// The unprojecting is the engine's — `Raycaster.setFromScreen` knows about
  /// the Y flip and the aspect ratio, which are exactly the two things that get
  /// silently reversed when a game writes them out again. What comes back is
  /// handed down as an origin and a direction, which is the seam every genre
  /// here uses for pointing and what keeps `Selection` testable with no camera.
  ///
  /// **The two vectors are the caster's own and are overwritten by the next
  /// aim.** A raycaster keeps one ray so that pointing costs no allocation, so
  /// a caller that wants to hold on to an answer past the next call has to copy
  /// it. Nobody here does: every reader below uses what it is given before
  /// aiming again.
  ({vm.Vector3 origin, vm.Vector3 direction}) _aim(Offset at) {
    _ray.setFromScreen(
      _camera,
      at.dx,
      at.dy,
      width: _surface.width,
      height: _surface.height,
    );
    return (origin: _ray.ray.origin, direction: _ray.ray.direction);
  }

  /// Where a point on the widget lands on the map, or null for a click that
  /// meets no ground.
  vm.Vector3? _ground(Offset at, Staged staged) {
    final ray = _aim(at);
    return groundUnder(
      ray.origin,
      ray.direction,
      planeY: staged.camera.focus.y,
    );
  }

  /// A click: pick out a worker, or send the ones already picked.
  void _tap(Offset at) {
    final staged = _staged;
    final command = _command;
    if (staged == null || command == null) return;

    final ray = _aim(at);
    switch (command.unitUnder(ray.origin, ray.direction)) {
      // One of ours: it becomes the selection, replacing whatever was picked.
      case final Unit unit when unit.side == viewerSide:
        setState(() => command.select(unit));

      // Theirs. **This is where an attack order goes, and there is not one to
      // give.** `orders.dart` says why in as many words: a unit has no target,
      // no reach and no health, so an `AttackOrder` written today would be a
      // document with nowhere to be carried out. Doing nothing is the honest
      // answer — in particular the selection is left standing, because a click
      // that cannot be obeyed must not disband the squad the player gathered.
      case final Unit _:
        break;

      // Empty ground: an order, for the picked units and nobody else.
      case null:
        final vm.Vector3? goal = _ground(at, staged);
        if (goal != null) command.orderTo(goal);
    }
  }

  /// A rectangle: everybody of ours standing inside it, on the ground.
  ///
  /// Both corners are projected onto the same flat plane, which is what makes
  /// this a rectangle in the world rather than a frustum — see `groundUnder`
  /// for what that costs on a hillside and why it is paid.
  void _band(Offset from, Offset to) {
    final staged = _staged;
    final command = _command;
    if (staged == null || command == null) return;

    final vm.Vector3? corner = _ground(from, staged);
    final vm.Vector3? opposite = _ground(to, staged);
    if (corner == null || opposite == null) return;
    setState(() => command.selectWithin(corner, opposite));
  }

  /// Says what the cursor is over: a unit by ray, anything else by pixel.
  ///
  /// **The crowd is asked first, and it has to be.** A batch is picked as the
  /// batch, so the pass would answer "the crowd" for a cursor over any worker
  /// on the map and could never name one. The ray can, and it is also the
  /// cheaper question — no frame is drawn to answer it.
  ///
  /// The other side's workers are named only where this side can see them. The
  /// map is already drawn through side [viewerSide]'s eyes, and a readout that
  /// named a unit standing under the fog would be a line of text handing the
  /// player what the picture is careful not to show.
  void _sight(Offset at) {
    final staged = _staged;
    final command = _command;
    if (staged == null || command == null) return;

    final ray = _aim(at);
    final Unit? unit = command.unitUnder(ray.origin, ray.direction);
    final bool seen =
        unit != null &&
        (unit.side == viewerSide ||
            staged.simulation.fog.sees(
              viewerSide,
              unit.position.x,
              unit.position.z,
            ));
    if (seen) {
      setState(() {
        _light(null);
        _under = unit.side == viewerSide ? 'worker' : 'their worker';
      });
      return;
    }
    _hover(at);
  }

  /// Asks the next frame what is drawn under the cursor, and lights it.
  ///
  /// **The first place a game in this repository uses the picking pass.** A ray
  /// against bounds — which is what every other genre here points with, and
  /// what the click below still uses to find a spot of ground — answers "which
  /// box did I point at", and a box is a metre wider than the hall in it. The
  /// pass draws the scene again with each mesh writing its own number and reads
  /// the one pixel back, so the answer is the silhouette: the corner of a hall
  /// stops being the hall exactly where it looks like it does.
  ///
  /// One question at a time. The pass costs a scene's worth of draws on the
  /// frame it runs, and a pointer that moves sixty times a second would
  /// otherwise queue sixty of them — the cursor would be answered about where
  /// it used to be, more slowly, for ever.
  void _hover(Offset at) {
    final renderer = _renderer;
    if (renderer == null || _asking) return;
    _asking = true;
    renderer
        .pickPixel(at.dx / _surface.width, at.dy / _surface.height)
        .then(
          (MeshNode? node) {
            if (!mounted) return;
            setState(() {
              _asking = false;
              _light(node);
              _under = node?.name;
            });
          },
          // A pick belongs to a frame, and a frame can fail — see `pickPixel`.
          // Nothing about the game depends on the answer, so a question that
          // cannot be answered is one nothing was under.
          onError: (Object _, StackTrace _) {
            if (!mounted) return;
            setState(() {
              _asking = false;
              _light(null);
              _under = null;
            });
          },
        );
  }

  /// Lights [node] if it is a building, and puts out whatever was lit.
  ///
  /// Buildings only. A batch is picked as the batch by the engine's own
  /// account, so lighting what the cursor found over the crowd would light
  /// every unit on the map — and over the fog it would light the fog.
  ///
  /// **What the cursor is over is set by the caller, not here.** The two used to
  /// be one method, and the early return below — which skips the work when the
  /// same thing is still lit — skipped the name with it: moving the cursor from
  /// one thing that is not a building to another left the readout naming the
  /// first for as long as the pointer stayed off the halls.
  void _light(MeshNode? node) {
    final staged = _staged;
    if (staged == null) return;
    final MeshNode? wanted = staged.visuals.buildings.contains(node)
        ? node
        : null;
    if (identical(wanted, _lit)) return;
    _lit?.material.emissive.setZero();
    _lit = wanted;
    wanted?.material.emissive.setValues(0.30, 0.26, 0.10);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    final renderer = _renderer;
    if (renderer != null) {
      renderer.dispose();
      renderer.device.dispose();
    }
    super.dispose();
  }

  /// A button went down: a drag starts, and which kind it is is decided now.
  ///
  /// **Decided on the button rather than settled by a gesture arena.** A
  /// `GestureDetector` is not told which button dragged it, so a screen that
  /// wanted a rectangle on one button and a pan on another could not be built
  /// out of one; a `Listener` sees the buttons and competes with nobody.
  void _down(PointerDownEvent event) {
    _panning = event.buttons != kPrimaryButton;
    // No corners for a drag that is moving the view. They would draw a
    // rectangle of no size in the corner of the screen for as long as the
    // player pushed the map about.
    if (_panning) return;
    _bandFrom = event.localPosition;
    _bandTo = event.localPosition;
  }

  /// The pointer moved with a button held: push the view, or stretch the
  /// rectangle.
  void _drag(PointerMoveEvent event, Staged staged) {
    if (_panning) {
      staged.camera.pan(-event.delta.dx * 0.12, -event.delta.dy * 0.12);
      return;
    }
    if (_bandFrom == null) return;
    setState(() => _bandTo = event.localPosition);
  }

  /// The button came up: a click, or the rectangle it turned out to be.
  void _up() {
    final Offset? from = _bandFrom;
    final Offset? to = _bandTo;
    setState(() {
      _bandFrom = null;
      _bandTo = null;
    });
    if (from == null || to == null || _panning) return;
    if ((to - from).distance <= _slop) {
      _tap(to);
    } else {
      _band(from, to);
    }
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final staged = _staged;
    final command = _command;
    if (renderer == null || staged == null || command == null) {
      return const ColoredBox(color: Color(0xFF10131A));
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          staged.camera.zoom(event.scrollDelta.dy * 0.05);
        }
      },
      onPointerDown: _down,
      onPointerMove: (PointerMoveEvent event) => _drag(event, staged),
      onPointerUp: (PointerUpEvent _) => _up(),
      // A pointer taken away mid-drag — the window losing it, a touch
      // cancelled — is not a click and is not a rectangle. Without this the
      // next press would stretch a rectangle from wherever the lost one began.
      onPointerCancel: (PointerCancelEvent _) => setState(() {
        _bandFrom = null;
        _bandTo = null;
      }),
      child: MouseRegion(
        onHover: (PointerHoverEvent event) => _sight(event.localPosition),
        onExit: (PointerExitEvent _) => setState(() {
          _light(null);
          _under = null;
        }),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            _surface = constraints.biggest;
            final frame = renderer.render(
              width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
              height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
              scene: _scene,
              views: <RenderView>[_view],
              settings: const RenderSettings(),
            );
            return Stack(
              children: <Widget>[
                Positioned.fill(child: renderer.device.present(frame.frame)),
                if (_bandFrom case final Offset from)
                  if (_bandTo case final Offset to)
                    // Drawn from the corners rather than from the units it
                    // holds: the selection is decided when the button comes
                    // up, and a rectangle that highlighted its catch as it
                    // went would be walking the crowd on every mouse move to
                    // show an answer that is not final.
                    Positioned.fromRect(
                      rect: Rect.fromPoints(from, to),
                      child: const _Band(),
                    ),
                StrategyHud(
                  readout: readoutOf(
                    staged.match,
                    side: viewerSide,
                    selected: command.count,
                    under: _under,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The rectangle being dragged.
class _Band extends StatelessWidget {
  const _Band();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF8FD3FF), width: 1.0),
        color: const Color(0xFF8FD3FF).withValues(alpha: 0.12),
      ),
    ),
  );
}
