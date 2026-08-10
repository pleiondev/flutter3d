import 'dart:developer' as developer;

import 'package:vector_math/vector_math.dart' as vm;

import '../graphics/command_encoder.dart';
import '../graphics/formats.dart';
import '../graphics/graphics_device.dart';
import '../graphics/render_target_pool.dart';
import '../graphics/texture.dart';
import '../scene/camera_node.dart';
import '../scene/scene.dart';
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'pass_contributor.dart';
import 'render_node.dart';

/// Draws the first-person view model over the finished scene.
///
/// Its own command buffer, because Metal allows one open encoder per buffer
/// and flutter_gpu offers no way to end a pass — the same rule that already
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
    encoder
      ..setViewport(full)
      ..setScissor(full)
      ..setDepthWrite(true)
      ..setDepthCompare(CompareFunction.less)
      ..setPrimitiveType(PrimitiveType.triangle);

    // Nothing is bound in a new pass, so the state has to forget what the
    // scene pass left it believing.
    frame.state.invalidatePipeline();

    final aspect = height == 0 ? 1.0 : width / height;
    camera.readWorldPosition(_cameraPosition);

    frame.services.encodeScene(
      encoder: encoder,
      scene: scene,
      viewProjection: camera.viewProjection(aspect),
      cameraPosition: _cameraPosition,
      settings: frame.settings,
      state: frame.state,
      // Answered here, from this node's own view of the frame, which is what
      // the declaration above is for. `tryTexture` resolves against what this
      // node reads, so an atlas it had not declared would come back as nothing
      // to sample rather than as a texture found lying about.
      shadows: SceneShadows(
        point: frame.resources.tryTexture(FrameResourceIds.cubeShadow),
        pointStatic:
            frame.resources.tryTexture(FrameResourceIds.cubeShadowStatic),
      ),
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
