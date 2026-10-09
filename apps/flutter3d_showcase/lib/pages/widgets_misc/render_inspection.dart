/// What a tool attached to a running game sees of its frame: the passes,
/// the draws, one pixel, the totals, and which node drew the pixel under a
/// point — worked out of one captured frame by the plain functions the VM
/// service extensions answer with.
///
/// Quoted by `render_inspection.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// What one look at a frame found.
final class _Look {
  const _Look(this.capture, this.node, this.x, this.y);

  final FrameCapture capture;

  /// The node drawn at ([x], [y]), or null for the clear colour.
  final MeshNode? node;
  final int x;
  final int y;
}

final class RenderInspectionDemo extends ShowcaseDemo {
  late final Scene _scene;

  /// The probe frame [verify] reads, taken before the page is shown.
  late final _Look _probe;

  /// The latest look at the page's own frames, refreshed while it runs.
  _Look? _live;
  bool _looking = false;
  double _sinceLook = 0.0;

  static const int _probeWidth = 96;
  static const int _probeHeight = 64;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.35
      ..yaw = 0.0;
  }

  Scene _build(GraphicsDevice device) {
    MeshNode mesh(String name, MeshData data, Vector4 color) => MeshNode(
      DeviceMesh.upload(device, data),
      RenderMaterial(
        name: '$name paint',
        baseColor: _fromSrgb(color),
        roughness: 0.6,
      ),
      name: name,
    );
    return Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.8, -0.4)),
      )
      ..add(
        mesh(
          'floor',
          CuboidShape(size: Vector3(5.0, 0.2, 3.0)).build(),
          Vector4(0.4, 0.42, 0.45, 1.0),
        )..setPosition(0.0, -0.6, 0.0),
      )
      ..add(
        mesh(
          'crate',
          CuboidShape(size: Vector3.all(1.0)).build(),
          Vector4(0.85, 0.45, 0.15, 1.0),
        ),
      )
      ..add(
        mesh(
          'barrel',
          SphereShape(radius: 0.45, segments: 32, rings: 16).build(),
          Vector4(0.2, 0.45, 0.85, 1.0),
        )..setPosition(1.5, -0.05, 0.3),
      );
  }

  // #region look
  /// Asks the renderer for the next frame twice over: its passes and its
  /// draws, journaled, and the node drawn at ([u], [v]), fractions of the
  /// frame from the top left. Both are answered by the same frame, so a draw
  /// index means the frame the pixel is from.
  static Future<_Look> _lookAt(Renderer renderer, double u, double v) async {
    final Future<FrameCapture> captured = renderer.captureNextFrame(
      draws: true,
    );
    final Future<MeshNode?> node = renderer.pickPixel(u, v);
    final FrameCapture capture = await captured;
    return _Look(
      capture,
      await node,
      (u * capture.width).floor(),
      (v * capture.height).floor(),
    );
  }
  // #endregion look

  @override
  Future<void> prepare(DemoContext context) async {
    _scene = _build(context.device);
    // #region probe
    final CameraNode eye =
        CameraNode(projection: const PerspectiveProjection(fovY: 0.8))
          ..setPosition(0.0, 0.8, 4.0)
          ..lookAt(Vector3.zero());
    _scene.add(eye);
    // The middle of the pixel in the middle, so the pick and the pixel read
    // are the same one.
    final Future<_Look> look = _lookAt(
      context.renderer,
      (_probeWidth ~/ 2 + 0.5) / _probeWidth,
      (_probeHeight ~/ 2 + 0.5) / _probeHeight,
    );
    context.renderer.render(
      width: _probeWidth,
      height: _probeHeight,
      scene: _scene,
      views: <RenderView>[RenderView(camera: eye)],
    );
    _probe = await look;
    eye.removeFromParent();
    // #endregion probe
  }

  @override
  Scene build(DemoContext context) => _scene;

  @override
  void update(DemoContext context, double dt) {
    // Once a second, ask about the frame the viewport is about to draw, at
    // its middle.
    _sinceLook += dt;
    if (_looking || _sinceLook < 1.0) return;
    _looking = true;
    _sinceLook = 0.0;
    _lookAt(context.renderer, 0.5, 0.5).then((_Look look) {
      _live = look;
      _looking = false;
    });
  }

  // #region report
  /// What an agent reads back: the passes in order with their draw counts,
  /// and the node under the middle with the draws it made.
  static String _report(_Look look) {
    final List<Object?> passes =
        renderPasses(look.capture)['passes']! as List<Object?>;
    final String ran = <String>[
      for (final Object? pass in passes)
        if (pass case {'name': final String name, 'drawCalls': final int n})
          '$name ($n)',
    ].join(', ');
    final Map<String, Object?> picked = renderPicked(
      look.capture,
      look.node,
      x: look.x,
      y: look.y,
    );
    final Map<String, Object?> stats = renderStats(look.capture);
    return 'passes: $ran. Under the middle: ${picked['node'] ?? 'nothing'}, '
        'draws ${picked['draws']}. ${stats['drawCalls']} draws, '
        '${stats['triangles']} triangles in all';
  }
  // #endregion report

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      _report(_live ?? _probe),
      value: () => false,
      onChanged: (bool v) => _sinceLook = 1.0,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final FrameCapture capture = _probe.capture;
    final Map<String, Object?> picked = renderPicked(
      capture,
      _probe.node,
      x: _probe.x,
      y: _probe.y,
    );
    if (picked['node'] != 'crate') {
      throw StateError('the middle of the frame is ${picked['node']}');
    }
    final List<int> draws = picked['draws']! as List<int>;
    if (draws.isEmpty) throw StateError('the crate made no draw that frame');
    // The draw it made, opened as a tool opens one, names the crate and the
    // pass it ran in; that pass's output, read at the same pixel, is the
    // crate's orange and not the barrel's blue.
    final Map<String, Object?> draw = renderDraw(capture, <String, String>{
      'index': '${draws.first}',
    });
    if (isRefusal(draw) || draw['mesh'] != 'crate') {
      throw StateError('draw ${draws.first} is not the crate: $draw');
    }
    final Map<String, Object?> pixel = renderReadPixel(
      capture,
      <String, String>{
        'pass': '${draw['pass']}',
        'x': '${_probe.x}',
        'y': '${_probe.y}',
      },
    );
    final List<Object?>? value =
        (pixel['float'] ?? pixel['unorm']) as List<Object?>?;
    if (isRefusal(pixel) || value == null) {
      throw StateError('the pixel could not be read: $pixel');
    }
    final double red = (value[0]! as num).toDouble();
    final double blue = (value[2]! as num).toDouble();
    if (red <= blue) {
      throw StateError('the pixel the crate drew reads $value');
    }
    if ((renderStats(capture)['describedDraws']! as int) < 3) {
      throw StateError('the journal missed some of the three meshes');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
