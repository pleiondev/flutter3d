/// A crowd on a hillside: the fourth genre, drawn.
///
///     flutter run -d macos
///
/// A match: your camp in the near corner, a bot's in the far one, both digging
/// the same hillside for the same finishing line. Click the ground to send your
/// crowd there — which takes it off its work, the way an order does. Drag to
/// push the view, and use the scroll wheel to pull it back.
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

  Renderer? _renderer;
  Staged? _staged;
  late final Scene _scene;
  late final RenderView _view;
  late final CameraNode _camera;
  late final Ticker _ticker;
  final Raycaster _ray = Raycaster();
  Size _surface = const Size(1280, 720);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final device = await openDevice(width: 1280, height: 720);
    if (!mounted) return device.dispose();

    final staged = stage(device: device);
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

    _ticker = createTicker((_) {
      staged.match.step(_dt);
      staged.visuals.sync();
      staged.camera.place(_dt);
      _camera
        ..setPositionFrom(staged.camera.eye)
        ..lookAt(staged.camera.target);
      setState(() {});
    })..start();

    setState(() {
      _staged = staged;
      _renderer = Renderer.create(device: device);
    });
  }

  /// Sends the whole crowd to wherever the ground was clicked.
  void _order(Offset at) {
    final staged = _staged;
    if (staged == null) return;

    _ray.setFromScreen(
      _camera,
      at.dx,
      at.dy,
      width: _surface.width,
      height: _surface.height,
    );

    // Where the ray meets the ground plane under the view. Good enough for a
    // demo: the terrain is gentle, and the simulation puts everybody on the
    // real surface the moment they arrive.
    final vm.Vector3 origin = _ray.ray.origin;
    final vm.Vector3 direction = _ray.ray.direction;
    if (direction.y >= -1e-4) return;
    final double t = (staged.camera.focus.y - origin.y) / direction.y;
    final vm.Vector3 goal = vm.Vector3(
      origin.x + direction.x * t,
      0.0,
      origin.z + direction.z * t,
    );

    // Only this side's units. The other one has a policy of its own and takes
    // its orders from that; a click that moved both crowds would be a demo of
    // nothing.
    Squad(staged.mine).moveTo(goal);
  }

  /// The score, and who has won when somebody has.
  String get _score {
    final staged = _staged;
    if (staged == null) return '';
    final sim = staged.simulation;
    final String tally =
        'you ${sim.delivered[0].round()} · '
        'bot ${sim.delivered[1].round()}';
    final Standing standing = staged.match.standing;
    if (!standing.isOver) return tally;
    return switch (standing.winner) {
      0 => '$tally — you win',
      1 => '$tally — the bot wins',
      _ => '$tally — drawn',
    };
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

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final staged = _staged;
    if (renderer == null || staged == null) {
      return const ColoredBox(color: Color(0xFF10131A));
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          staged.camera.zoom(event.scrollDelta.dy * 0.05);
        }
      },
      child: GestureDetector(
        onTapUp: (TapUpDetails details) => _order(details.localPosition),
        onPanUpdate: (DragUpdateDetails details) => staged.camera.pan(
          -details.delta.dx * 0.12,
          -details.delta.dy * 0.12,
        ),
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
                Positioned(
                  left: 16.0,
                  top: 16.0,
                  child: Text(
                    _score,
                    style: const TextStyle(
                      color: Color(0xFFE8ECF4),
                      fontSize: 16.0,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
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
