part of 'scene_widgets.dart';

/// A camera that orbits a point, turned by a drag and moved in by a pinch
/// or a scroll — the camera a model viewer, a product page or a lab bench
/// wants, in one widget.
///
///     Scene3D(children: <Widget>[
///       const OrbitCamera3D(distance: 4.0),
///       const Light3D.sun(),
///       Model3D(source: 'assets_src/robot.glb'),
///     ])
///
/// **A camera like [Camera3D]**: the camera built last is the one drawn
/// through, and gestures turn the [OrbitCamera3D] built last. [distance],
/// [yaw] and [pitch] are where it starts; the person moves it from there, and
/// a rebuild with other numbers does not put it back. [target] is applied on
/// every build where it changed, so a game may follow something with it.
///
/// **Turned by one finger or the mouse**: a horizontal drag swings round the
/// target, a vertical one tilts, short of the poles. **Moved in and out** by
/// a pinch or a scroll wheel, between [minDistance] and [maxDistance]. A
/// fling keeps turning and slows by [damping] per second; null stops dead
/// on release. Through `OrbitController` underneath.
///
/// Only a [Scene3D] hands it gestures; under `SceneWidgets.mount` it is a
/// camera at its starting place.
final class OrbitCamera3D extends Spatial3D {
  const OrbitCamera3D({
    super.key,
    this.target,
    this.distance = 5.0,
    this.yaw = 0.0,
    this.pitch = 0.35,
    this.minDistance = 0.5,
    this.maxDistance = 100.0,
    this.turnSpeed = 0.008,
    this.zoomSpeed = 0.002,
    this.damping = 6.0,
    this.projection = const PerspectiveProjection(),
    super.children,
  });

  /// The point orbited, a place in the world; the world's origin if null.
  final Vector3? target;

  /// How far from [target] the camera starts, in metres.
  final double distance;

  /// Where round [target] the camera starts, in radians about world Y:
  /// nought looks down −Z from +Z.
  final double yaw;

  /// How high above [target] the camera starts, in radians: nought is level.
  final double pitch;

  /// The closest a pinch or a scroll brings the camera, in metres.
  final double minDistance;

  /// The farthest it takes it, in metres.
  final double maxDistance;

  /// Radians turned per logical pixel dragged.
  final double turnSpeed;

  /// How much a scroll of one logical pixel moves in or out, as a fraction
  /// of the distance: the default moves a wheel's click (about 100 px) a
  /// fifth of the way.
  final double zoomSpeed;

  /// How fast a fling slows, per second: its speed falls by `e^−damping`
  /// each second. Null stops the camera when the finger lifts.
  final double? damping;

  final Projection projection;

  @override
  State<OrbitCamera3D> createState() => _OrbitCamera3DState();
}

/// What a [Scene3D] drives with its gestures.
abstract interface class _Orbit {
  /// A drag of [delta] logical pixels.
  void turn(Offset delta);

  /// Distance times [factor]: below one is closer.
  void zoom(double factor);

  /// A scroll of [pixels] logical pixels, positive away from the person.
  void scroll(double pixels);

  /// The finger lifted moving at [velocity] logical pixels a second.
  void fling(Offset velocity);
}

class _OrbitCamera3DState extends _SpatialState<OrbitCamera3D, CameraNode>
    implements _Orbit, _Animated {
  late OrbitController _orbit;
  Vector3? _target;

  /// What a fling still turns by, in logical pixels a second.
  Offset _spin = Offset.zero;

  @override
  CameraNode createNode(_Scene3DScope scope) {
    final camera = CameraNode(projection: widget.projection);
    _target = widget.target?.clone();
    final scene = scope.host.scene;
    _orbit = OrbitController(
      camera,
      target: scene.toScene(_world(widget.target)),
      distance: widget.distance,
      yaw: widget.yaw,
      pitch: widget.pitch,
      minDistance: widget.minDistance,
      maxDistance: widget.maxDistance,
    )..rotateSensitivity = widget.turnSpeed;
    final host = scope.host;
    host.cameras.add(camera);
    host.animated.add(this);
    host.orbits.add(this);
    if (host.orbits.length == 1) host.gesturesChanged();
    // The point orbited is in the scene's space, which a shift moves under
    // it: it moves by the shift, as the camera node does, so a fling
    // between builds turns round the same place in the world.
    _shifts = scene.onOriginShift((OriginShifted shift) {
      _orbit.target.add(
        Vector3(
          shift.from.x - shift.to.x,
          shift.from.y - shift.to.y,
          shift.from.z - shift.to.z,
        ),
      );
    });
    return camera;
  }

  Registration? _shifts;

  static WorldPosition _world(Vector3? target) => switch (target) {
    final t? => WorldPosition(t.x, t.y, t.z),
    null => WorldPosition.origin,
  };

  @override
  void apply(CameraNode node, _Scene3DScope scope) {
    node.projection = widget.projection;
    _orbit
      ..minDistance = widget.minDistance
      ..maxDistance = widget.maxDistance
      ..rotateSensitivity = widget.turnSpeed;
    // A target is a value: the same point in a new `Vector3` is no change,
    // and a turn of the person's is not undone by a rebuild.
    final target = widget.target;
    final same = target == null ? _target == null : target == _target;
    if (!same) {
      _target = target?.clone();
      scope.host.scene.toScene(_world(target), _orbit.target);
    }
    _orbit.distance = _orbit.distance.clamp(
      widget.minDistance,
      widget.maxDistance,
    );
    _orbit.apply();
  }

  @override
  void turn(Offset delta) {
    _spin = Offset.zero;
    _orbit.rotate(delta.dx, delta.dy);
  }

  @override
  void zoom(double factor) => _orbit.zoom(factor);

  @override
  void scroll(double pixels) =>
      _orbit.zoom(math.exp(pixels * widget.zoomSpeed));

  @override
  void fling(Offset velocity) {
    if (widget.damping != null) _spin = velocity;
  }

  @override
  void advance(double seconds) {
    final damping = widget.damping;
    if (damping == null || _spin == Offset.zero) return;
    _orbit.rotate(_spin.dx * seconds, _spin.dy * seconds);
    _spin *= math.exp(-damping * seconds);
    // Below a pixel a second the turn is no longer seen.
    if (_spin.distanceSquared < 1.0) _spin = Offset.zero;
  }

  @override
  void dispose() {
    _shifts?.cancel();
    final host = _scope?.host;
    if (host != null) {
      host.cameras.remove(_node);
      host.animated.remove(this);
      host.orbits.remove(this);
      if (host.orbits.isEmpty) host.gesturesChanged();
    }
    super.dispose();
  }
}

/// A tap that landed on something in a [Scene3D]: what the ray through the
/// finger hit, and the pointer that tapped — what [Mesh3D.onTap] and
/// [Model3D.onTap] are handed.
///
/// **One object, so a minor can say more.** Hover, a drag, the pointer's
/// pressure would each be a field here, not a parameter added to every
/// handler written against 1.0.
///
/// **Yours to keep.** [hit] is a [HitResult] of its own, not a scratch the
/// next tap rewrites, and nothing here changes after the handler returns.
final class Tap3D {
  const Tap3D({
    required this.hit,
    required this.localPosition,
    required this.kind,
    this.buttons = kPrimaryButton,
  });

  /// What the ray through the finger hit first: the mesh, the point and
  /// normal in the world, the distance.
  final HitResult hit;

  /// Where the tap was, in the scene widget's own logical pixels from its
  /// top-left corner.
  final Offset localPosition;

  /// What tapped: a finger, a mouse, a stylus.
  final PointerDeviceKind kind;

  /// The buttons held, as Flutter's pointer events give them
  /// ([kPrimaryButton] for a finger or a left click).
  final int buttons;

  @override
  String toString() => 'Tap3D($hit at $localPosition, $kind)';
}

/// Has [nodes] answer a tap with [handler], or no longer answer when it is
/// null, telling [host] when the first starts listening or the last stops.
void _answerTaps(
  _SceneHost host,
  Iterable<MeshNode> nodes,
  void Function(Tap3D tap)? handler,
) {
  final before = host.tappable.isEmpty;
  for (final node in nodes) {
    if (handler == null) {
      host.tappable.remove(node);
    } else {
      host.tappable[node] = handler;
    }
  }
  if (before != host.tappable.isEmpty) host.gesturesChanged();
}

/// The gestures of a [Scene3D]: a tap cast into the scene, and drags,
/// pinches and scrolls handed to the last [OrbitCamera3D]. Built around the
/// view in every build, with no recognizer while nothing answers, so the
/// view underneath is never made again.
mixin _SceneGestures on State<Scene3D> implements _SceneHost {
  @override
  final Map<MeshNode, void Function(Tap3D tap)> tappable =
      <MeshNode, void Function(Tap3D tap)>{};

  @override
  final List<_Orbit> orbits = <_Orbit>[];

  bool _listensForTaps = false;
  bool _listensForDrags = false;
  bool _gesturesScheduled = false;
  double _lastScale = 1.0;
  int _pointers = 0;

  CameraNode get _drawnThrough;

  @override
  void gesturesChanged() {
    if (_gesturesScheduled) return;
    _gesturesScheduled = true;
    // Told while the children build, which is inside this widget's build:
    // the recognizers change on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gesturesScheduled = false;
      if (!mounted) return;
      final taps = tappable.isNotEmpty;
      final drags = orbits.isNotEmpty;
      if (taps == _listensForTaps && drags == _listensForDrags) return;
      setState(() {
        _listensForTaps = taps;
        _listensForDrags = drags;
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _tapped(TapUpDetails details) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final hit =
        (Raycaster()..setFromScreen(
              _drawnThrough,
              details.localPosition.dx,
              details.localPosition.dy,
              width: box.size.width,
              height: box.size.height,
            ))
            .intersectScene(scene);
    // The nearest surface answers, or nothing does: a mesh that does not
    // listen still stands in front of one that does.
    final node = hit?.node;
    if (hit == null || node == null) return;
    tappable[node]?.call(
      Tap3D(
        hit: hit,
        localPosition: details.localPosition,
        kind: details.kind,
      ),
    );
  }

  Widget _withGestures(Widget view) => Listener(
    onPointerSignal: (PointerSignalEvent event) {
      if (event is PointerScrollEvent && orbits.isNotEmpty) {
        orbits.last.scroll(event.scrollDelta.dy);
      }
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _listensForTaps ? _tapped : null,
      onScaleStart: _listensForDrags
          ? (ScaleStartDetails details) {
              _lastScale = 1.0;
              _pointers = details.pointerCount;
            }
          : null,
      onScaleUpdate: _listensForDrags
          ? (ScaleUpdateDetails details) {
              if (orbits.isEmpty) return;
              _pointers = details.pointerCount;
              if (details.pointerCount < 2) {
                orbits.last.turn(details.focalPointDelta);
              } else if (details.scale > 0.0) {
                // Fingers apart is closer: the distance shrinks by what the
                // span grew since the last update.
                orbits.last.zoom(_lastScale / details.scale);
                _lastScale = details.scale;
              }
            }
          : null,
      onScaleEnd: _listensForDrags
          ? (ScaleEndDetails details) {
              if (orbits.isNotEmpty && _pointers < 2) {
                orbits.last.fling(details.velocity.pixelsPerSecond);
              }
            }
          : null,
      child: view,
    ),
  );
}
