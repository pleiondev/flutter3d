/// A scene written as widgets — `P10`.
///
///     Scene3D(
///       children: <Widget>[
///         const Camera3D(position: ..., target: ...),
///         const Light3D.directional(direction: ...),
///         Mesh3D(
///           key: const ValueKey<String>('crate'),
///           shape: const CuboidShape(),
///           material: crate,
///           position: Vector3(0.0, 0.5, 0.0),
///         ),
///         Model3D(source: 'assets_src/robot.glb', animation: 'Walk'),
///       ],
///     )
///
/// **Over the imperative graph, not beside it.** Every widget here owns one
/// node of an ordinary [Scene] — a [SceneNode], a [MeshNode], a [LightNode],
/// a [CameraNode] — made when the widget is first built, given the widget's
/// properties on every rebuild, and taken out of the scene when the widget
/// goes. Flutter's own reconciliation decides which is which, so a widget
/// that keeps its key across a rebuild keeps its node: its transform, its
/// animation's place, everything a game set on it imperatively. A game that
/// wants the graph itself reaches it through [Scene3DController] and keeps
/// every imperative call it had; nothing here is a second engine.
///
/// **Three layers, one engine.** [Scene3D] is sugar: a [Flutter3dView] —
/// the widget that owns a device, a renderer, a loop, focus and the
/// lifecycle — with these widgets built into its scene. Anything the view
/// can do, a scene of widgets does through [Scene3DController.engine], and a
/// game that outgrows the widgets moves to the view without moving engines.
/// Under both is `SceneSurface`, which only hands a frame a caller rendered
/// to Flutter, for a caller that owns everything else itself.
///
/// **The reconciliation contract**, held by
/// `test/scene3d_reconciliation_test.dart`:
///
/// * **Identity is the key.** A widget that keeps its key — moved among its
///   siblings, or under another parent with a `GlobalKey` — keeps its node.
/// * **A rebuild loads nothing.** A rebuild hands the node the widget's
///   properties; a [Model3D] is not loaded again and a [Mesh3D] whose shape
///   builds the same vertices is not uploaded again.
/// * **Gone is released.** A widget gone takes its node out of the scene,
///   and what it made on the device — a [Mesh3D]'s upload, a [Model3D]'s
///   asset — goes back to it. What the caller handed in (a geometry, a
///   material) stays the caller's.
///
/// **Named with a `3D` suffix.** The plan called them `SceneNode` and
/// `SceneMesh`; `SceneNode` is the engine's own class, exported beside these
/// from the same import, and two classes of one name there is a compile
/// error in every file that uses both.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/rendering.dart' show RenderPositionedBox;
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_core/flutter3d_core.dart'
    show SceneBinding, SceneBindingContext;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        BindingInterpolation,
        BindingLifetime,
        Entity,
        PublishedState,
        Registration;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show LocalSimulation, SimulationHandle, TimeSource;

import '../surface/scene_surface.dart' show FramePresenter;
import '../view/flutter3d_view.dart';
import '../view/frame_info.dart';
import '../view/view_settings.dart';

part 'scene_widgets_bindings.dart';
part 'scene_widgets_features.dart';
part 'scene_widgets_input.dart';
part 'scene_widgets_mount.dart';

/// What the widgets of one scene share, whoever is drawing it: a [Scene3D],
/// or a [SceneWidgetsMount] over a scene a game draws itself.
abstract interface class _SceneHost {
  Scene get scene;
  Renderer get renderer;

  /// The [Camera3D]s built, in order; the last is the one drawn through.
  List<CameraNode> get cameras;

  /// What advances between frames: models' animations, particles.
  Set<_Animated> get animated;

  /// The meshes a tap reaches, and what each does with the hit: a
  /// [Mesh3D.onTap], a [Model3D.onTap] for each of its parts.
  Map<MeshNode, void Function(HitResult hit)> get tappable;

  /// The [OrbitCamera3D]s built, in order; the last is the one gestures
  /// turn.
  List<_Orbit> get orbits;

  /// The simulation the scene shows, for a [Binding3D] that names none:
  /// the view's, under a [Scene3D]; null under a mount, which has no loop.
  SimulationHandle? get simulation;

  /// How far the frame is between the last two steps of [simulation],
  /// nought to one: the loop's own under a [Scene3D] whose simulation runs
  /// inline, and one (the newest step, unblended) where it is elsewhere.
  double get alpha;

  /// Told when [tappable] or [orbits] gained their first entry or lost
  /// their last: a [Scene3D] listens for gestures only while something
  /// answers them, so a scene with none never takes a drag from a list it
  /// sits in.
  void gesturesChanged();
}

/// What a [Scene3D] has made, for a game that wants the graph underneath.
final class Scene3DController {
  Scene3DController._(this.engine, this._owner);

  /// The engine the scene is drawn by — its device, renderer and loop — as
  /// the [Flutter3dView] underneath made it.
  final Flutter3dEngine engine;

  final _Scene3DState _owner;

  /// The device the scene's meshes are uploaded to. After a device loss it
  /// is the one the scene was rebuilt on; read it where it is used.
  GraphicsDevice get device => engine.device;

  /// The renderer; see [device] on keeping it.
  Renderer get renderer => engine.renderer;

  /// The scene the widgets build.
  Scene get scene => _owner._scene;

  /// The camera the frame is drawn through: the [Camera3D] built last, or a
  /// default one five metres back looking at the origin when there is none.
  CameraNode get camera => _owner._camera;
}

/// The root of a scene written as widgets — `P10`.
///
/// **Sugar on [Flutter3dView], since 1.0, not a second engine.** The view
/// opens a device (unless [device] is given), makes the renderer and the
/// loop, and owns the frame clock, focus, lifecycle and teardown as it does
/// for any engine. What this adds is the scene: [children] built into it,
/// the [Camera3D] built last drawn through, models and particles advanced
/// before each frame. [placeholder] is shown while the device opens. The
/// engine underneath is [Scene3DController.engine]; `SceneSurface` is the
/// layer under the view, for a caller that draws the frame itself. The
/// library's documentation states how the widgets reconcile with the scene.
///
/// **One frame per vsync while [continuous]**, which a scene with an
/// animation needs; with it off a frame is drawn when this widget is built
/// again, which is enough for a scene that changes only when its parent's
/// state does, and nothing is advanced between.
///
/// **A device lost and recovered** (a browser's WebGL context) has the
/// children built again on the device that came back, so every mesh is
/// uploaded again; [materials] went with the old device and is the
/// application's to load again in [onCreated]'s controller's place.
final class Scene3D extends StatefulWidget {
  const Scene3D({
    super.key,
    this.children = const <Widget>[],
    this.settings = const RenderSettings(),
    this.clearColor,
    this.device,
    this.materials,
    this.continuous = true,
    this.placeholder = const SizedBox.expand(),
    this.onCreated,
    this.onFrame,
    this.presenter,
    this.frameRateCap,
    this.time,
  });

  /// Where the scene's time comes from: `Flutter3dView.time`, which this
  /// hands to the view underneath. Null is the display's own clock. The
  /// loop, the models' clips, the particles and [onFrame] all run on it, so
  /// `TimeSource.scaled(0.1)` slows the whole scene to a tenth.
  final TimeSource? time;

  /// Frames a second this scene is drawn at most, held to a whole number of
  /// the display's refreshes — `A1.5`: sixty on a 120 Hz screen is every
  /// other refresh, thirty on sixty every other. Null, the default, draws on
  /// every refresh while [continuous]. See `FrameCadence`.
  final double? frameRateCap;

  /// The scene's contents: [Node3D], [Mesh3D], [Model3D], [Light3D] and
  /// [Camera3D], nested as the graph is.
  final List<Widget> children;

  /// What every frame is drawn with.
  final RenderSettings settings;

  /// The colour behind everything, in linear light; the view's default if
  /// null.
  final LinearColor? clearColor;

  /// The device to draw on, borrowed; one the view opens if null.
  final GraphicsDevice? device;

  /// A loaded shader library layered over the engine's, for materials whose
  /// lighting model names a stage only it has — `HotMaterials.library`.
  final ShaderLibrary? materials;

  final bool continuous;

  final Widget placeholder;

  /// Called once, when the scene exists and before its first frame.
  final void Function(Scene3DController controller)? onCreated;

  /// Called before every frame — after the animations have advanced and
  /// before the frame is drawn — with the seconds since the last one and
  /// what the renderer answered for it, as one [FrameInfo].
  final void Function(FrameInfo frame)? onFrame;

  /// `presentFrame`, normally; a test without a backend passes its own.
  final FramePresenter? presenter;

  @override
  State<Scene3D> createState() => _Scene3DState();
}

class _Scene3DState extends State<Scene3D>
    with _SceneGestures
    implements _SceneHost {
  Scene3DController? _controller;
  late final Scene _scene = Scene();
  late final CameraNode _defaultCamera = CameraNode()
    ..setPosition(0.0, 0.0, 5.0)
    ..lookAt(Vector3.zero());
  final List<CameraNode> _cameras = <CameraNode>[];
  final Set<_Animated> _animated = <_Animated>{};

  /// The view the frame is drawn through, kept across frames so the
  /// temporal history it carries is this scene's; made again when the
  /// camera or the clear colour changes.
  RenderView? _view;
  LinearColor? _viewClear;

  /// Bumped when the device comes back from a loss: the children are built
  /// again, and each uploads again to the device that is there now.
  int _generation = 0;

  CameraNode get _camera => _cameras.isEmpty ? _defaultCamera : _cameras.last;

  @override
  CameraNode get _drawnThrough => _camera;

  @override
  Scene get scene => _scene;

  @override
  Renderer get renderer => _controller!.renderer;

  @override
  List<CameraNode> get cameras => _cameras;

  @override
  Set<_Animated> get animated => _animated;

  @override
  SimulationHandle? get simulation => _controller?.engine.simulation;

  /// A fraction, nought to one: the loop's own when the simulation runs
  /// in it, one otherwise.
  @override
  double get alpha {
    final view = _controller?.engine;
    if (view == null) return 1.0;
    final inline =
        view.simulation is LocalSimulation &&
        identical((view.simulation as LocalSimulation).loop, view.loop);
    return inline ? view.loop.alpha : 1.0;
  }

  @override
  void initState() {
    super.initState();
    _scene.add(_defaultCamera);
  }

  void _created(Flutter3dEngine engine) {
    if (widget.materials case final materials?) {
      engine.renderer.renderSteps.addMaterials(materials);
    }
    final controller = Scene3DController._(engine, this);
    setState(() => _controller = controller);
    widget.onCreated?.call(controller);
  }

  /// The animations advance by what passed since the last frame, then the
  /// game's own [Scene3D.onFrame]: one place for "before the frame".
  void _beforeFrame(FrameInfo frame) {
    for (final animated in List<_Animated>.of(_animated)) {
      animated.advance(frame.seconds);
    }
    widget.onFrame?.call(frame);
  }

  RenderView _viewFor(CameraNode camera) {
    final view = _view;
    final clear = widget.clearColor;
    if (view != null && identical(view.camera, camera) && _viewClear == clear) {
      return view;
    }
    view?.dispose();
    _viewClear = clear;
    return _view = RenderView(camera: camera, clearColor: clear);
  }

  @override
  void dispose() {
    _view?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final stack = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Built first and never painted: the children's whole job is the
        // nodes they keep in the scene. The view draws in layout, after
        // every one of them has been built for this frame.
        if (controller != null)
          Offstage(
            child: KeyedSubtree(
              key: ValueKey<int>(_generation),
              child: _Scene3DScope(
                host: this,
                device: controller.device,
                parent: _scene.root,
                child: _Children(widget.children),
              ),
            ),
          ),
        Flutter3dView(
          scene: _scene,
          camera: _defaultCamera,
          device: DeviceSettings(
            device: widget.device,
            presenter: widget.presenter,
            onDeviceRestored: (Flutter3dEngine engine) =>
                setState(() => _generation++),
          ),
          view: ViewSettings(
            settings: widget.settings,
            views: controller == null ? null : <RenderView>[_viewFor(_camera)],
            continuous: widget.continuous,
            frameRateCap: widget.frameRateCap,
            placeholder: widget.placeholder,
            failure: (Object error) =>
                ErrorWidget('the scene could not open a device: $error'),
          ),
          onCreated: _created,
          onFrame: (Flutter3dEngine engine, FrameInfo frame) =>
              _beforeFrame(frame),
          time: widget.time,
        ),
      ],
    );
    return _withGestures(stack);
  }
}

/// Children laid out nowhere: they paint nothing and take no space.
class _Children extends StatelessWidget {
  const _Children(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => switch (children.length) {
    0 => const SizedBox.shrink(),
    _ => Stack(children: children),
  };
}

/// What a widget below a [Scene3D] needs: the scene's host, the device its
/// meshes upload to, and the node it hangs its own from.
class _Scene3DScope extends InheritedWidget {
  const _Scene3DScope({
    required this.host,
    required this.device,
    required this.parent,
    required super.child,
  });

  final _SceneHost host;
  final GraphicsDevice device;
  final SceneNode parent;

  static _Scene3DScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Scene3DScope>();
    if (scope == null) {
      throw FlutterError(
        'A 3D widget was built outside a Scene3D. Mesh3D, Node3D, Model3D, '
        'Light3D and Camera3D belong in Scene3D.children or below one.',
      );
    }
    return scope;
  }

  @override
  bool updateShouldNotify(_Scene3DScope oldWidget) =>
      !identical(parent, oldWidget.parent) ||
      !identical(device, oldWidget.device);
}

/// A node with a transform, and children hung from it.
///
/// [position], [rotation] and [scale] are applied on every build, and a
/// property left null is left as the node has it, so a game may move a node
/// imperatively and the widget will not put it back unless it says where.
abstract base class Spatial3D extends StatefulWidget {
  const Spatial3D({
    super.key,
    this.position,
    this.rotation,
    this.scale,
    this.visible = true,
    this.children = const <Widget>[],
  });

  final Vector3? position;
  final Quaternion? rotation;
  final Vector3? scale;
  final bool visible;
  final List<Widget> children;
}

abstract class _SpatialState<W extends Spatial3D, N extends SceneNode>
    extends State<W> {
  N? _node;
  SceneNode? _parent;
  _Scene3DScope? _scope;

  N get node => _node!;

  /// Makes this widget's node, once.
  N createNode(_Scene3DScope scope);

  /// What this widget's own properties say about its node, past the
  /// transform. Called on every build.
  void apply(N node, _Scene3DScope scope) {}

  /// Told the node now hangs from another parent, after a keyed reparent.
  void reparented(N node) {}

  void _applyAll() {
    final node = _node!;
    final widget = this.widget;
    if (widget.position case final p?) node.setPositionFrom(p);
    if (widget.rotation case final r?) node.setRotation(r);
    if (widget.scale case final s?) node.setScale(s.x, s.y, s.z);
    node.isVisible = widget.visible;
    apply(node, _scope!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _Scene3DScope.of(context);
    _scope = scope;
    if (_node == null) {
      _node = createNode(scope);
      scope.parent.add(_node!);
      _parent = scope.parent;
      _applyAll();
    } else if (!identical(_parent, scope.parent)) {
      // Moved to another parent by a keyed reparent: the node follows,
      // keeping everything it had.
      _node!.removeFromParent();
      scope.parent.add(_node!);
      _parent = scope.parent;
      reparented(_node!);
    }
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyAll();
  }

  @override
  void dispose() {
    _node?.removeFromParent();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Scene3DScope(
    host: _scope!.host,
    device: _scope!.device,
    parent: node,
    child: _Children(widget.children),
  );
}

/// A node with nothing of its own to draw: a group, a pivot.
final class Node3D extends Spatial3D {
  const Node3D({
    super.key,
    super.position,
    super.rotation,
    super.scale,
    super.visible,
    super.children,
    this.name,
  });

  final String? name;

  @override
  State<Node3D> createState() => _Node3DState();
}

class _Node3DState extends _SpatialState<Node3D, SceneNode> {
  @override
  SceneNode createNode(_Scene3DScope scope) => SceneNode(name: widget.name);
}

/// A mesh drawn with a material.
///
/// [shape] is built and uploaded to the scene's device when the widget is
/// first built. A rebuild handed another shape object builds it again and
/// uploads it only when its vertices or indices differ, so a shape made
/// fresh in `build` costs a build, not an upload. [geometry], when given, is
/// used as it is and [shape] is not read. [material] is the engine's own, so a game that
/// keeps it may change it in place between frames; with none, the mesh is
/// drawn with the nearest [Material3D] above it — `P10`.
///
/// Directly below a [Mirror3D], the mesh is one of its reflecting surfaces.
///
/// **What it uploaded it gives back.** The mesh built from [shape] is this
/// widget's: replaced by another upload, or with the widget gone, it goes
/// back to the device once no frame in flight still draws it. A [geometry]
/// handed in is the caller's and is left alone.
final class Mesh3D extends Spatial3D {
  const Mesh3D({
    super.key,
    this.shape,
    this.geometry,
    this.material,
    super.position,
    super.rotation,
    super.scale,
    super.visible,
    super.children,
    this.castsShadow = true,
    this.drawOrder = 0,
    this.name,
    this.onTap,
  }) : assert(
         shape != null || geometry != null,
         'a Mesh3D draws a shape or a geometry',
       );

  final Shape? shape;
  final MeshGeometry? geometry;
  final engine.RenderMaterial? material;
  final bool castsShadow;

  /// See `MeshNode.drawOrder`.
  final int drawOrder;
  final String? name;

  /// Called when a tap on the [Scene3D] lands on this mesh first — the
  /// nearest surface under the finger, through the camera drawn through —
  /// with where it landed ([HitResult.point], [HitResult.normal]).
  ///
  /// A ray cast through the scene's `Raycaster`, so a mesh in front that
  /// does not listen still hides one behind that does. Null listens for
  /// nothing, and a scene where nothing listens takes no tap at all.
  final void Function(HitResult hit)? onTap;

  @override
  State<Mesh3D> createState() => _Mesh3DState();
}

class _Mesh3DState extends _SpatialState<Mesh3D, MeshNode> {
  /// The shape object last built, and what it built: a rebuild handed a new
  /// object is built again and uploaded only when its vertices or its
  /// indices are not the ones on the device.
  Shape? _built;
  MeshData? _data;

  /// The mesh this widget uploaded, and the renderer it goes back through
  /// once no frame in flight still draws it: the one drawing when it was
  /// uploaded, so a mesh of a device lost since goes with that renderer
  /// rather than to the device that replaced it. A [Mesh3D.geometry] handed
  /// in is the caller's and is never here.
  DeviceMesh? _owned;
  Renderer? _ownedBy;

  DeviceMesh _upload(_Scene3DScope scope, MeshData data) {
    _release();
    final mesh = DeviceMesh.upload(scope.device, data);
    _owned = mesh;
    _ownedBy = scope.host.renderer;
    return mesh;
  }

  void _release() {
    final mesh = _owned;
    if (mesh == null) return;
    _owned = null;
    _ownedBy?.releaseMeshAfterFrame(mesh);
    _ownedBy = null;
  }

  MeshGeometry _geometry(_Scene3DScope scope) {
    final given = widget.geometry;
    if (given != null) return given;
    final shape = widget.shape!;
    final data = shape.build();
    _built = shape;
    _data = data;
    return _upload(scope, data);
  }

  /// The mirror this mesh is a surface of, while it hangs directly from one.
  PlanarReflectorNode? _reflector;

  engine.RenderMaterial _material() =>
      widget.material ??
      _MaterialScope.maybeOf(context) ??
      (throw FlutterError(
        'A Mesh3D was given no material and has no Material3D above it.',
      ));

  @override
  MeshNode createNode(_Scene3DScope scope) =>
      MeshNode(_geometry(scope), _material(), name: widget.name);

  void _joinMirror(MeshNode node) {
    final now = switch (node.parent) {
      final PlanarReflectorNode mirror => mirror,
      _ => null,
    };
    if (identical(now, _reflector)) return;
    _reflector?.surfaces.remove(node);
    now?.surfaces.add(node);
    _reflector = now;
  }

  @override
  void reparented(MeshNode node) => _joinMirror(node);

  @override
  void dispose() {
    if (_node case final node?) {
      _reflector?.surfaces.remove(node);
      if (_scope case final scope?) {
        _answerTaps(scope.host, <MeshNode>[node], null);
      }
    }
    super.dispose();
    _release();
  }

  @override
  void apply(MeshNode node, _Scene3DScope scope) {
    if (widget.geometry case final given?) {
      if (!identical(node.mesh, given)) {
        node.mesh = given;
        _release();
      }
      _built = null;
      _data = null;
    } else if (!identical(_built, widget.shape)) {
      final shape = widget.shape!;
      final data = shape.build();
      final previous = _data;
      _built = shape;
      if (previous == null ||
          !listEquals(previous.vertices, data.vertices) ||
          !listEquals(previous.indices, data.indices)) {
        _data = data;
        node.mesh = _upload(scope, data);
      }
    }
    node
      ..material = _material()
      ..castsShadow = widget.castsShadow
      ..drawOrder = widget.drawOrder;
    _joinMirror(node);
    _answerTaps(
      scope.host,
      <MeshNode>[node],
      widget.onTap == null ? null : (HitResult hit) => widget.onTap?.call(hit),
    );
  }
}

/// A light: directional by default, or a point or a spot.
///
/// **Brightness in photometric units** (docs/CONTRACTS.md): [intensity] is
/// lux for a directional light and candela for the others. The defaults are
/// lights the default camera (f/4, 1/60 s, ISO 100) shows well:
/// [sunIlluminance] for a sun, [lampIntensity] — an ordinary 800-lumen bulb —
/// for a lamp. [Light3D.sun] and [Light3D.lamp] say which one a light is.
final class Light3D extends Spatial3D {
  const Light3D({
    super.key,
    this.type = LightType.directional,
    this.direction,
    this.color,
    this.intensity = sunIlluminance,
    this.range = 0.0,
    this.castsShadow,
    this.outerConeAngle,
    super.position,
    super.children,
  });

  /// A light from infinitely far along [direction], the way it shines.
  const Light3D.directional({
    super.key,
    required this.direction,
    this.color,
    this.intensity = sunIlluminance,
    this.castsShadow,
  }) : type = LightType.directional,
       range = 0.0,
       outerConeAngle = null,
       super(position: null);

  /// A light at [position] reaching [range] metres; nought is unbounded.
  const Light3D.point({
    super.key,
    required super.position,
    this.color,
    this.intensity = lampIntensity,
    this.range = 0.0,
    this.castsShadow,
  }) : type = LightType.point,
       direction = null,
       outerConeAngle = null;

  /// The sun: a directional light shining along [direction] (null shines
  /// down and a little across, [sunDirection]), [intensity] lux on a
  /// surface facing it, casting shadows, slightly warm.
  ///
  /// [sunIlluminance] by default, the sun through a thin haze, which the
  /// default camera exposes as daylight. A clear noon sun is about
  /// 100 000 lux; give that and expose for it (`PhysicalCamera` at f/16,
  /// 1/125 s — the sunny-sixteen rule — or `autoExposure`).
  const Light3D.sun({
    super.key,
    this.direction,
    this.color = sunColor,
    this.intensity = sunIlluminance,
    this.castsShadow = true,
  }) : type = LightType.directional,
       range = 0.0,
       outerConeAngle = null,
       super(position: null);

  /// A lamp: a point light at [position], [intensity] candela in every
  /// direction, reaching [range] metres (nought is unbounded), warm white.
  ///
  /// [lampIntensity] by default, an 800-lumen household bulb. A room lit by
  /// bulbs is about a hundredth as bright as daylight: open the camera up
  /// (`PhysicalCamera` at f/2, 1/30 s, ISO 800) or turn `autoExposure` on, as
  /// a photographer would indoors. `Photometric.fromLumens` gives the candela
  /// for what another bulb's box says.
  const Light3D.lamp({
    super.key,
    required super.position,
    this.color = lampColor,
    this.intensity = lampIntensity,
    this.range = 0.0,
    this.castsShadow,
  }) : type = LightType.point,
       direction = null,
       outerConeAngle = null;

  /// What [Light3D.sun] and a directional light shine with by default, in
  /// lux: 15 000, the sun through a thin haze.
  static const double sunIlluminance = 15000.0;

  /// What [Light3D.lamp] and a point light shine with by default, in
  /// candela: an 800-lumen bulb, `800 / 4π`.
  static const double lampIntensity = 63.66197723675813;

  /// Which way a directional light — [Light3D.sun] among them — first
  /// shines when it is given no [direction]: down from high up, from behind
  /// and to the right of a camera looking down −Z. Left as it is after, so a
  /// game may turn the node itself.
  static Vector3 get sunDirection => Vector3(-0.4, -1.0, -0.3);

  /// The colour of [Light3D.sun]: daylight, a little warm (about 5 500 K).
  static const LinearColor sunColor = LinearColor(1.0, 0.94, 0.86);

  /// The colour of [Light3D.lamp]: a warm-white bulb (about 2 700 K).
  static const LinearColor lampColor = LinearColor(1.0, 0.72, 0.42);

  final LightType type;

  /// Which way the light shines; applied to directional and spot lights.
  final Vector3? direction;

  /// Linear RGB; white if null.
  final LinearColor? color;

  /// How bright the light is: lux for a directional light, candela for a
  /// point or spot (since 1.0). [sunIlluminance] by default for a
  /// directional light, [lampIntensity] for a point.
  final double intensity;

  /// How far the light reaches, in metres; nought is unbounded.
  final double range;

  /// Null leaves the engine's default: a directional light casts, others not.
  final bool? castsShadow;

  /// A spot's cone, in radians.
  final double? outerConeAngle;

  @override
  State<Light3D> createState() => _Light3DState();
}

class _Light3DState extends _SpatialState<Light3D, LightNode> {
  @override
  LightNode createNode(_Scene3DScope scope) {
    final node = LightNode(type: widget.type, castsShadow: widget.castsShadow);
    if (widget.direction == null && widget.type == LightType.directional) {
      node.setLocalForward(Light3D.sunDirection.normalized());
    }
    return node;
  }

  @override
  void apply(LightNode node, _Scene3DScope scope) {
    node
      ..type = widget.type
      ..intensity = widget.intensity
      ..range = widget.range;
    node.color = widget.color ?? LinearColor.white;
    if (widget.castsShadow case final casts?) node.castsShadow = casts;
    if (widget.outerConeAngle case final cone?) node.outerConeAngle = cone;
    if (widget.direction case final direction?) {
      node.setLocalForward(direction.normalized());
    }
  }
}

/// A camera the frame is drawn through.
///
/// The [Camera3D] built last is the one drawn through; with none, the scene
/// has a default five metres back looking at the origin. [target], when
/// given, is looked at after [position] is applied.
final class Camera3D extends Spatial3D {
  const Camera3D({
    super.key,
    super.position,
    super.rotation,
    this.target,
    this.projection = const PerspectiveProjection(),
    super.children,
  });

  final Vector3? target;
  final Projection projection;

  @override
  State<Camera3D> createState() => _Camera3DState();
}

class _Camera3DState extends _SpatialState<Camera3D, CameraNode> {
  @override
  CameraNode createNode(_Scene3DScope scope) {
    final camera = CameraNode(projection: widget.projection);
    scope.host.cameras.add(camera);
    return camera;
  }

  @override
  void apply(CameraNode node, _Scene3DScope scope) {
    node.projection = widget.projection;
    if (widget.target case final target?) node.lookAt(target);
  }

  @override
  void dispose() {
    _scope?.host.cameras.remove(_node);
    super.dispose();
  }
}

/// Something the scene advances by the seconds between frames.
abstract interface class _Animated {
  void advance(double seconds);
}

/// A model loaded from where the build hook converted [source] — or from
/// [load], when given — and instantiated into the scene.
///
/// [placeholder], a 3D widget, stands in until the model has loaded, and is
/// taken out when it has; with none, nothing does. [animation] names the
/// clip to play — null plays none — at [speed], paused while [playing] is
/// false; changing either changes the clip in place, where it is.
///
/// **Loaded once, owned, and released.** The asset is read when the widget
/// is first built; a rebuild — a new position, another clip — changes the
/// instance it became and loads nothing. A widget with another [source]
/// is another model: give it another key. The asset is the widget's, from
/// [source] or from [load] alike, and is disposed when the widget goes, or as
/// it arrives when the widget went while it loaded; a loader that hands out
/// an asset something else keeps instantiates it itself, under a [Node3D].
final class Model3D extends Spatial3D {
  const Model3D({
    super.key,
    this.source,
    this.load,
    this.placeholder,
    this.animation,
    this.playing = true,
    this.speed = 1.0,
    this.onLoaded,
    this.onTap,
    super.position,
    super.rotation,
    super.scale,
    super.visible,
    super.children,
  }) : assert(
         source != null || load != null,
         'a Model3D loads a source path or calls a loader',
       );

  /// A path under `assets_src/`, read as `loadModelAsset` reads it.
  final String? source;

  /// Makes the asset on the scene's device, in place of reading [source].
  final Future<ModelAsset> Function(GraphicsDevice device)? load;

  final Widget? placeholder;
  final String? animation;
  final bool playing;

  /// How fast the clip plays, a multiplier on its own speed.
  final double speed;

  /// Called once with the instance the model became.
  final void Function(ModelInstance instance)? onLoaded;

  /// Called when a tap on the [Scene3D] lands on the model first, with the
  /// [part] it landed on — one of the instance's meshes, named as the file
  /// names it (`MeshNode.name`) — and where ([HitResult.point]). See
  /// [Mesh3D.onTap] on what a tap reaches. A model still loading answers
  /// nothing.
  final void Function(MeshNode part, HitResult hit)? onTap;

  @override
  State<Model3D> createState() => _Model3DState();
}

class _Model3DState extends _SpatialState<Model3D, SceneNode>
    implements _Animated {
  ModelInstance? _instance;
  String? _playingClip;

  @override
  SceneNode createNode(_Scene3DScope scope) {
    // Its turn taken now, in the order the models are built, rather than
    // when its file arrives — see [_loadInto].
    unawaited(_loadInto(scope, scope.host.scene.reserveTurn()));
    scope.host.animated.add(this);
    return SceneNode(name: widget.source ?? 'model');
  }

  /// The asset this widget loaded, disposed with it.
  ModelAsset? _asset;

  /// Loads the model and puts it in the scene once [turn] is ready — once
  /// everything asked of the same scene before it is in — then releases it
  /// for the next.
  ///
  /// **In the order the models were built, not the order their files
  /// arrive in** — see [Scene.reserveTurn]. The node stands in its place
  /// from the start, but the scene registers meshes as they are attached,
  /// and that registry is what the renderer works from.
  Future<void> _loadInto(_Scene3DScope scope, SceneTurn turn) async {
    _turns.add(turn);
    try {
      final asset = switch (widget.load) {
        final load? => await load(scope.device),
        null => await ModelAsset.fromDocument(
          await loadModelAsset(widget.source!),
          device: scope.device,
        ),
      };
      await turn.ready;
      _place(scope, asset);
    } finally {
      _turns.remove(turn);
      turn.release();
    }
  }

  /// The turns this widget's loads hold, released by [dispose]: a widget
  /// gone while its file is still loading must not keep the models built
  /// after it out of the scene until the file comes back, or for ever if it
  /// never does.
  final Set<SceneTurn> _turns = <SceneTurn>{};

  void _place(_Scene3DScope scope, ModelAsset asset) {
    if (!mounted) {
      // Arrived for a widget that went while it loaded: nothing will draw
      // it, and nobody else holds it.
      asset.dispose();
      return;
    }
    _asset = asset;
    final instance = asset.instantiate(scope.host.scene, parent: node);
    setState(() => _instance = instance);
    _applyAnimation();
    _applyTaps(scope.host);
    widget.onLoaded?.call(instance);
  }

  void _applyAnimation() {
    final player = _instance?.player;
    if (player == null) return;
    final clip = widget.animation;
    if (clip == null) {
      if (player.isPlaying) player.stop();
      _playingClip = null;
      return;
    }
    if (clip != _playingClip) {
      final index = player.clipNames.indexOf(clip);
      if (index < 0) {
        throw ArgumentError.value(
          clip,
          'animation',
          'the model has the clips ${player.clipNames.join(', ')}',
        );
      }
      player.play(index);
      _playingClip = clip;
    }
    player.speed = widget.speed;
  }

  @override
  void advance(double seconds) {
    final player = _instance?.player;
    if (player == null || !widget.playing || _playingClip == null) return;
    player.update(seconds);
  }

  @override
  void apply(SceneNode node, _Scene3DScope scope) {
    _applyAnimation();
    _applyTaps(scope.host);
  }

  /// Every part of the instance answers a tap while [Model3D.onTap] is set.
  void _applyTaps(_SceneHost host) {
    final meshes = _instance?.meshes;
    if (meshes == null) return;
    _answerTaps(
      host,
      meshes,
      widget.onTap == null
          ? null
          : (HitResult hit) => widget.onTap?.call(hit.requireNode, hit),
    );
  }

  @override
  void dispose() {
    final host = _scope?.host;
    if (host != null) {
      host.animated.remove(this);
      if (_instance?.meshes case final meshes?) {
        _answerTaps(host, meshes, null);
      }
    }
    for (final turn in _turns) {
      turn.release();
    }
    _turns.clear();
    super.dispose();
    // The instance went out of the scene with the node it hangs from.
    _asset?.dispose();
    _asset = null;
  }

  @override
  Widget build(BuildContext context) => _Scene3DScope(
    host: _scope!.host,
    device: _scope!.device,
    parent: node,
    child: _Children(<Widget>[
      if (_instance == null) ?widget.placeholder,
      ...widget.children,
    ]),
  );
}
