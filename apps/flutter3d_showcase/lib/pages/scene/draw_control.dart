/// Three controls over a single draw: which of two meshes in the same place
/// is drawn first, how a masked surface's edge is cut, and which part of an
/// index buffer a draw reads.
///
/// Quoted by `draw_control.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
// The page shows the engine's own draw list, which is not its API.
// ignore: implementation_imports
import 'package:flutter3d_core/src/engine/render/render_list.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DrawControlDemo extends ShowcaseDemo {
  /// Whether the red panel is drawn first, and so keeps the shared pixels.
  bool redFirst = true;
  bool coverage = true;

  late final MeshNode _red;
  late final MeshNode _blue;
  late final RenderMaterial _grille;
  late final DeviceMesh _panel;
  late final CameraNode _camera;
  late final GraphicsDevice _device;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.5
      ..pitch = 0.2
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _camera = context.camera;
    _device = context.device;
    _panel = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(1.4, 1.4, 0.04)).build(),
    );

    // #region panels
    // Two panels of one mesh at one place: every pixel of one is a pixel of
    // the other, at exactly the same depth. The depth test keeps the first
    // fragment and refuses an equal one after it, so whichever is drawn first
    // is the one seen.
    _red = MeshNode(
      _panel,
      RenderMaterial(
        name: 'red',
        baseColor: LinearColor.fromSrgb(0.85, 0.2, 0.15, 1.0),
      ),
      name: 'red panel',
    )..setPosition(-0.9, 1.0, 0.0);
    _blue = MeshNode(
      _panel,
      RenderMaterial(
        name: 'blue',
        baseColor: LinearColor.fromSrgb(0.15, 0.35, 0.9, 1.0),
      ),
      name: 'blue panel',
    )..setPosition(-0.9, 1.0, 0.0);
    // #endregion panels

    // #region grille
    // A grille: a small texture whose alpha is a grid of round holes, cut at
    // a half and turned into multisample coverage where the device can.
    const int size = 16;
    final Uint8List texels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final double dx = (x % 4) - 1.5;
        final double dy = (y % 4) - 1.5;
        final int i = (y * size + x) * 4;
        texels.setAll(i, <int>[230, 230, 220, 255]);
        texels[i + 3] = math.sqrt(dx * dx + dy * dy) < 1.4 ? 0 : 255;
      }
    }
    _grille = RenderMaterial(
      name: 'grille',
      albedo: context.device.createTextureFromPixels(
        width: size,
        height: size,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(texels),
      ),
      alphaMode: MaterialAlphaMode.mask,
      alphaCutoff: 0.5,
      alphaToCoverage: coverage,
      doubleSided: true,
    );
    // #endregion grille

    return Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.8)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 8.0, depth: 6.0).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.55, 0.55, 0.5, 1.0),
          ),
          name: 'floor',
        ),
      )
      ..add(_red)
      ..add(_blue)
      ..add(
        MeshNode(_panel, _grille, name: 'grille')..setPosition(0.9, 1.0, 0.0),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region order
    // Lower draws first. The order is added to the material's `drawBucket`
    // and outranks every other term of the sort, depth included.
    _red.drawOrder = redFirst ? -1 : 0;
    _blue.drawOrder = redFirst ? 0 : -1;
    // #endregion order
    _grille.alphaToCoverage = coverage;
  }

  /// The six faces of the panel's cube as windows of its one index buffer,
  /// six indices each.
  // #region windows
  List<({int first, int count})> _faces() => <({int first, int count})>[
    for (var face = 0; face < 6; face++)
      indexWindow(_panel.indexCount, firstIndex: face * 6, indexCount: 6),
  ];
  // #endregion windows

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Drawn first, and so seen',
      options: const <String>['Red', 'Blue'],
      index: () => redFirst ? 0 : 1,
      onChanged: (int i) => redFirst = i == 0,
    ),
    ToggleControl(
      'Alpha to coverage on the grille',
      value: () => coverage,
      onChanged: (bool v) => coverage = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The sorted list puts the panel with the lower order first.
    final RenderView view = RenderView(camera: _camera);
    final RenderList list = RenderList()
      ..build(
        scene,
        view,
        viewMatrix: _camera.viewMatrix,
        frustum: Frustum.matrix(
          _camera.viewProjection(frame.frame.width / frame.frame.height),
        ),
      )
      ..sort(view);
    final List<MeshNode> drawn = <MeshNode>[
      for (final int i in list.opaque) list.itemAt(i).requireNode,
    ];
    final MeshNode first = redFirst ? _red : _blue;
    final MeshNode second = redFirst ? _blue : _red;
    if (!drawn.contains(first) ||
        !drawn.contains(second) ||
        drawn.indexOf(first) > drawn.indexOf(second)) {
      throw StateError('${first.name} is not drawn before ${second.name}');
    }

    // A device without coverage draws the hard cutoff and says so.
    if (coverage && !_device.features.has(DeviceFeature.alphaToCoverage)) {
      if (!frame.alphaToCoverageDeclined) {
        throw StateError('coverage was declined and the frame did not say so');
      }
    }

    // Six windows tile the cube's 36 indices; one past the end is refused.
    final List<({int first, int count})> faces = _faces();
    if (faces.last.first + faces.last.count != _panel.indexCount) {
      throw StateError('the faces do not cover the index buffer');
    }
    try {
      indexWindow(_panel.indexCount, firstIndex: 30, indexCount: 12);
      throw StateError('a window past the binding was accepted');
    } on RangeError {
      // Refused before any driver sees it, which is the claim.
    }
    // #endregion check
  }
}
