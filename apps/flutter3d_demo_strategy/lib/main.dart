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
/// Nothing here decides anything about the simulation: it steps, the bridge
/// reads it, and the camera watches — which is the arrangement every game in
/// this repository has, seen at the one scale where a thousand of something is
/// ordinary. The bot is not an exception to that: it writes the same orders
/// through the same handles as the click above, one thought every half second.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_backend/flutter3d_backend.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/command.dart';
import 'src/hud.dart';
import 'src/hud_readout.dart';
import 'src/level_document.dart';
import 'src/pointing.dart';
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
  static const double _dt = 1.0 / 60.0;

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
  /// thing as where the camera is pointing. Built in [_open] because it needs
  /// the simulation the document made.
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
  late final Ticker _ticker;
  final Raycaster _ray = Raycaster();
  Size _surface = const Size(1280, 720);

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

  Future<void> _open() async {
    // The map first, then the device: a document that failed to load with a
    // device already open would leak the device.
    final map = await StrategyMap.load();
    final device = await openDevice(width: 1280, height: 720);
    if (!mounted) return device.dispose();

    final staged = stage(device: device, map: map);
    _scene = Scene(name: 'map');
    staged.visuals.addTo(_scene);

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

    final command = CommandPost(
      simulation: staged.simulation,
      side: viewerSide,
    );

    _ticker = createTicker((_) {
      staged.match.step(_dt);
      // Before the picture and before the readout: a squad the player is
      // holding may have lost somebody to the step that just ran, and both the
      // count on the screen and the next order given would otherwise be about a
      // crowd that is one larger than the one on the map. Cheap — it walks the
      // crowd only while something is selected.
      command.prune();
      staged.visuals.sync();
      staged.camera.place(_dt);
      _camera
        ..setPositionFrom(staged.camera.eye)
        ..lookAt(staged.camera.target);
      setState(() {});
    })..start();

    setState(() {
      _staged = staged;
      _command = command;
      _renderer = Renderer.create(device: device);
    });
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
    _ticker.dispose();
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
