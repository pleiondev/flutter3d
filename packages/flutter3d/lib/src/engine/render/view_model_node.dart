import 'dart:developer' as developer;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/camera_node.dart';
import '../scene/scene.dart';
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'render_node.dart';

/// Draws the first-person view model over the finished scene.
///
/// Its own command buffer, because Metal allows one open encoder per buffer
/// and the encoder offers no way to end a pass — the same rule that already
/// governs the shadow and post passes.
///
/// its own pass rather than the scene pass, and that is the
/// whole reason the stage exists: a weapon held at arm's length shares no
/// depth with the world, or every doorway would slice the barrel off.
final class ViewModelNode extends RenderNode {
  ViewModelNode({required this.scene, required this.camera});

  /// Holds only what is in the player's hands. Kept apart from the world so
  /// culling, picking and the shadow pass never see it.
  Scene scene;

  /// Usually around 55 degrees against the world camera's 90.
  CameraNode camera;

  @override
  String get name => 'view model';

  /// Reads the finished scene and draws over it, which is a read and a write of
  /// the same resource — a link in the chain rather than a consumer of one.
  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  /// The point-light atlases, because a weapon held in a shadowed room is in
  /// shadow, and this pass draws through the same mesh encoder as the world.
  ///
  /// Undeclared until now, and it still worked — which is precisely the
  /// problem. The encoder reached into a renderer field for the atlas, so this
  /// node sampled a resource it had never asked for, was never ordered against
  /// its producer, and would have kept "working" if that producer had moved.
  /// Optional rather than hard for the reason the scene's are: a hard read
  /// would take the weapon off the screen the moment shadows were switched off.
  ///
  /// The directional map is deliberately absent. A view model is drawn with its
  /// own camera and its own near volume, and the world's shadow matrix would
  /// shadow it with things it is nowhere near.
  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
        FrameResourceIds.cubeShadow,
        FrameResourceIds.cubeShadowStatic,
      ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  bool get isActive => scene.meshes.isNotEmpty;

  /// Its own pass, so nothing the scene left is believed.
  ///
  /// The weapon is drawn over a finished scene with its own depth buffer, which
  /// is what stops the world clipping through a model held a few centimetres
  /// from the camera.
  static const PassState _kViewModelState = PassState(
    primitiveType: PrimitiveType.triangle,
    depthWrite: true,
    depthCompare: CompareFunction.less,
  );

  @override
  void execute(NodeFrame frame) {
    final hdr = frame.sceneColor;
    if (hdr == null) return;
    developer.Timeline.startSync('ViewModelNode.encode');

    final width = frame.width;
    final height = frame.height;

    // Straight into the resolved target, without MSAA, whatever the scene
    // used. Loading a multisampled attachment would mean loading the resolved
    // image back into it, which the API does not offer — and a weapon is a
    // handful of large, close triangles whose silhouette is mostly off screen,
    // the one case where the resolve buys least.
    final encoder = frame.device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: hdr, loadAction: LoadAction.load),
        ],
        // Its own depth, not the scene's: attachments in one target must agree
        // on sample count, and the scene's is four-sample whenever MSAA is on.
        // Cleared, so nothing in the world can occlude what is in the player's
        // hands.
        depth: DepthTarget(texture: _depthFor(frame.device, width, height)),
      ),
    );

    final full = ScreenRect(width: width, height: height);
    encoder.setState(_kViewModelState.copyWith(viewport: full, scissor: full));

    // Nothing is bound in a new pass, so the state has to forget what the
    // scene pass left it believing.
    frame.state.invalidatePipeline();

    final aspect = height == 0 ? 1.0 : width / height;
    camera.readWorldPosition(_cameraPosition);

    frame.services.encodeScene(
      frame: frame,
      encoder: encoder,
      scene: scene,
      // Through toDepthRange, like every other projection in the frame. This
      // was the one that was not, so the weapon was drawn in the engine's
      // depth convention on a backend that does not use it — right on one and
      // silently compressed into half the depth buffer on the other.
      viewProjection:
          toDepthRange(camera.viewProjection(aspect), frame.device.depthRange),
      cameraPosition: _cameraPosition,
    );

    encoder.submit();
    developer.Timeline.finishSync();
  }

  /// The pass's own depth buffer, made on demand and kept until the size
  /// changes.
  ///
  /// From the device it was handed rather than from a global, which is what
  /// lets this node run against a fake.
  TextureHandle _depthFor(GraphicsDevice device, int width, int height) {
    if (_depth != null && _depthWidth == width && _depthHeight == height) {
      return _depth!;
    }
    _depth = device.createTexture(RenderTargetSpec(
      width: width,
      height: height,
      format: device.defaultDepthStencilFormat,
      storageMode: StorageMode.deviceTransient,
    ));
    _depthWidth = width;
    _depthHeight = height;
    return _depth!;
  }

  TextureHandle? _depth;
  int _depthWidth = 0;
  int _depthHeight = 0;
  final vm.Vector3 _cameraPosition = vm.Vector3.zero();
}
