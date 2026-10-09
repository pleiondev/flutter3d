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
/// **Named with a `3D` suffix.** The plan called them `SceneNode` and
/// `SceneMesh`; `SceneNode` is the engine's own class, exported beside these
/// from the same import, and two classes of one name there is a compile
/// error in every file that uses both.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart' show RenderPositionedBox;
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show OriginShifted, Registration;

import '../surface/scene_surface.dart' show FramePresenter;
import '../view/flutter3d_view.dart';
import '../view/frame_info.dart';

part 'scene_widgets_features.dart';
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
/// **A [Flutter3dView] underneath, since 1.0**: it opens a device (unless
/// [device] is given), makes the renderer and the loop, and owns the frame
/// clock, focus, lifecycle and teardown as it does for any engine. What this
/// adds is the scene: [children] built into it, the [Camera3D] built last
/// drawn through, models and particles advanced before each frame.
/// [placeholder] is shown while the device opens.
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
class Scene3D extends StatefulWidget {
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
  });

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
  /// null. Encoded to sRGB once, for the view's `clearColorSrgb`.
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

class _Scene3DState extends State<Scene3D> implements _SceneHost {
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
  Scene get scene => _scene;

  @override
  Renderer get renderer => _controller!.renderer;

  @override
  List<CameraNode> get cameras => _cameras;

  @override
  Set<_Animated> get animated => _animated;

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
    final srgb = clear?.toSrgb();
    return _view = RenderView(
      camera: camera,
      clearColorSrgb: srgb == null
          ? null
          : Vector4(srgb.r, srgb.g, srgb.b, srgb.a),
    );
  }

  @override
  void dispose() {
    _view?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
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
          device: widget.device,
          settings: widget.settings,
          views: controller == null ? null : <RenderView>[_viewFor(_camera)],
          continuous: widget.continuous,
          frameRateCap: widget.frameRateCap,
          presenter: widget.presenter,
          placeholder: widget.placeholder,
          failure: (Object error) =>
              ErrorWidget('the scene could not open a device: $error'),
          onCreated: _created,
          onFrame: (Flutter3dEngine engine, FrameInfo frame) =>
              _beforeFrame(frame),
          onDeviceRestored: (Flutter3dEngine engine) =>
              setState(() => _generation++),
        ),
      ],
    );
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
abstract class Spatial3D extends StatefulWidget {
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
class Node3D extends Spatial3D {
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
class Mesh3D extends Spatial3D {
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

  @override
  State<Mesh3D> createState() => _Mesh3DState();
}

class _Mesh3DState extends _SpatialState<Mesh3D, MeshNode> {
  /// The shape object last built, and what it built: a rebuild handed a new
  /// object is built again and uploaded only when its vertices or its
  /// indices are not the ones on the device.
  Shape? _built;
  MeshData? _data;

  MeshGeometry _geometry(_Scene3DScope scope) {
    final given = widget.geometry;
    if (given != null) return given;
    final shape = widget.shape!;
    final data = shape.build();
    _built = shape;
    _data = data;
    return DeviceMesh.upload(scope.device, data);
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
    if (_node case final node?) _reflector?.surfaces.remove(node);
    super.dispose();
  }

  @override
  void apply(MeshNode node, _Scene3DScope scope) {
    if (widget.geometry case final given?) {
      if (!identical(node.mesh, given)) node.mesh = given;
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
        node.mesh = DeviceMesh.upload(scope.device, data);
      }
    }
    node
      ..material = _material()
      ..castsShadow = widget.castsShadow
      ..drawOrder = widget.drawOrder;
    _joinMirror(node);
  }
}

/// A light: directional by default, or a point or a spot.
class Light3D extends Spatial3D {
  const Light3D({
    super.key,
    this.type = LightType.directional,
    this.direction,
    this.color,
    this.intensity = Photometric.legacyUnit,
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
    this.intensity = Photometric.legacyUnit,
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
    this.intensity = Photometric.legacyUnit,
    this.range = 0.0,
    this.castsShadow,
  }) : type = LightType.point,
       direction = null,
       outerConeAngle = null;

  final LightType type;

  /// Which way the light shines; applied to directional and spot lights.
  final Vector3? direction;

  /// Linear RGB; white if null.
  final LinearColor? color;

  /// How bright the light is: lux for a directional light, candela for a
  /// point or spot (since 1.0). The default is the light a default
  /// `LightNode` is.
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
  LightNode createNode(_Scene3DScope scope) =>
      LightNode(type: widget.type, castsShadow: widget.castsShadow);

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
class Camera3D extends Spatial3D {
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
class Model3D extends Spatial3D {
  const Model3D({
    super.key,
    this.source,
    this.load,
    this.placeholder,
    this.animation,
    this.playing = true,
    this.speed = 1.0,
    this.onLoaded,
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

  @override
  State<Model3D> createState() => _Model3DState();
}

class _Model3DState extends _SpatialState<Model3D, SceneNode>
    implements _Animated {
  ModelInstance? _instance;
  String? _playingClip;

  @override
  SceneNode createNode(_Scene3DScope scope) {
    unawaited(_loadInto(scope));
    scope.host.animated.add(this);
    return SceneNode(name: widget.source ?? 'model');
  }

  Future<void> _loadInto(_Scene3DScope scope) async {
    final asset = switch (widget.load) {
      final load? => await load(scope.device),
      null => await ModelAsset.fromDocument(
        await loadModelAsset(widget.source!),
        device: scope.device,
      ),
    };
    if (!mounted) return;
    final instance = asset.instantiate(scope.host.scene, parent: node);
    setState(() => _instance = instance);
    _applyAnimation();
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
  void apply(SceneNode node, _Scene3DScope scope) => _applyAnimation();

  @override
  void dispose() {
    _scope?.host.animated.remove(this);
    super.dispose();
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
