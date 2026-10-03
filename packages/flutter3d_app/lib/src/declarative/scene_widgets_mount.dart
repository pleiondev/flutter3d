part of 'scene_widgets.dart';

/// Widgets built into a scene somebody else draws — `P10`.
///
/// [Scene3D] opens a device, makes a renderer and draws a frame each vsync;
/// a game with a loop of its own — a golden runner, a test, an engine
/// embedded in another — has all of that already and wants only the graph.
/// This builds [children] into [scene]'s root, on [device], with [renderer]
/// for what a widget adds to the frame (particles, a contributor), and keeps
/// them there until [SceneWidgetsMount.dispose]: the same widgets, the same
/// reconciliation, the same nodes.
///
///     final mount = SceneWidgets.mount(
///       scene: scene,
///       renderer: renderer,
///       device: device,
///       children: <Widget>[Camera3D(...), Mesh3D(...)],
///     );
///     // each frame:
///     mount.advance(seconds);
///     renderer.render(..., views: [RenderView(camera: mount.camera!)]);
///
/// **No screen, and no binding of its own.** The widgets paint nothing — a
/// [Scene3D] builds them under an `Offstage` for the same reason — so they
/// are built by a [BuildOwner] of this mount's and never laid out. A widget
/// that rebuilds itself, a [Model3D] whose asset arrived, is rebuilt on the
/// next microtask.
abstract final class SceneWidgets {
  static SceneWidgetsMount mount({
    required Scene scene,
    required Renderer renderer,
    required GraphicsDevice device,
    List<Widget> children = const <Widget>[],
  }) => SceneWidgetsMount._(scene, renderer, device)..update(children);
}

/// What [SceneWidgets.mount] built, kept until [dispose].
final class SceneWidgetsMount {
  SceneWidgetsMount._(this.scene, this.renderer, this.device)
    : _host = _MountHost(scene, renderer) {
    _owner = BuildOwner(
      focusManager: FocusManager(),
      onBuildScheduled: _scheduleBuild,
    );
  }

  final Scene scene;
  final Renderer renderer;
  final GraphicsDevice device;
  final _MountHost _host;

  late final BuildOwner _owner;
  final RenderPositionedBox _root = RenderPositionedBox();
  RenderObjectToWidgetElement<RenderBox>? _element;
  bool _buildScheduled = false;
  bool _disposed = false;

  /// The [Camera3D] built last, or null when there is none.
  CameraNode? get camera =>
      _host.cameras.isEmpty ? null : _host.cameras.last;

  /// Builds [children] in place of what was built before, keeping by key and
  /// type what Flutter keeps.
  void update(List<Widget> children) {
    if (_disposed) throw StateError('this mount was disposed');
    final adapter = RenderObjectToWidgetAdapter<RenderBox>(
      container: _root,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: _Scene3DScope(
          host: _host,
          device: device,
          parent: scene.root,
          child: _Children(children),
        ),
      ),
    );
    _element = adapter.attachToRenderTree(_owner, _element);
    _build();
  }

  /// Advances what the widgets animate — models' clips, particles — by
  /// [seconds], as a [Scene3D] does before each frame.
  void advance(double seconds) {
    for (final it in List<_Animated>.of(_host.animated)) {
      it.advance(seconds);
    }
  }

  /// Takes every node the widgets made out of the scene, and every
  /// contributor out of the renderer.
  void dispose() {
    if (_disposed) return;
    update(const <Widget>[]);
    _disposed = true;
  }

  void _scheduleBuild() {
    if (_buildScheduled || _disposed) return;
    _buildScheduled = true;
    scheduleMicrotask(() {
      _buildScheduled = false;
      if (!_disposed) _build();
    });
  }

  void _build() {
    final element = _element;
    if (element == null) return;
    _owner
      ..buildScope(element)
      ..finalizeTree();
  }
}

final class _MountHost implements _SceneHost {
  _MountHost(this.scene, this.renderer);

  @override
  final Scene scene;

  @override
  final Renderer renderer;

  @override
  final List<CameraNode> cameras = <CameraNode>[];

  @override
  final Set<_Animated> animated = <_Animated>{};
}
