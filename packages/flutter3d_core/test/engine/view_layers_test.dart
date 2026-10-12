/// What an XR runtime takes from a frame and gives it, as frame-graph
/// nodes: each view copied into its layer of the runtime's image, and the
/// real world's depth as a resource an occluding node reads.
///
///     dart test test/engine/view_layers_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:test/test.dart';

/// Two eyes a runtime posed, side by side in one target.
List<RenderView> _eyes(Scene scene) => <RenderView>[
  for (final (index, x) in <(int, double)>[(0, -0.032), (1, 0.032)])
    RenderView(
      camera: (CameraNode()
        ..setPosition(x, 1.6, 0.0)
        ..projection = OffAxisProjection.fromAngles(
          left: index == 0 ? -0.9 : -0.7,
          right: index == 0 ? 0.7 : 0.9,
          down: -0.8,
          up: 0.75,
        )),
      viewportFraction: ViewportRect(index * 0.5, 0.0, 0.5, 1.0),
    ),
]..forEach((view) => scene.add(view.camera));

/// What a node at the anchor before ours sees of the finished picture.
final class _Peek extends RenderNode {
  TextureFormat? format;
  List<int> viewIndices = <int>[];

  @override
  String get name => 'acme.peek';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforePresent;

  @override
  void execute(RenderFrame frame) {
    final picture = frame.resources.texture(FrameResourceIds.frame);
    format = picture.format;
    viewIndices = <int>[for (final view in frame.views) view.index];
    frame.resources.provide(FrameResourceIds.frame, picture);
  }
}

/// A plugin's occlusion node: reads the real world's depth.
final class _Occluder extends RenderNode {
  final List<TextureHandle> seen = <TextureHandle>[];

  @override
  String get name => 'acme.occlude';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    EnvironmentDepthNode.id,
    FrameResourceIds.hdrColor,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.afterOpaque;

  @override
  void execute(RenderFrame frame) {
    seen.add(frame.resources.texture(EnvironmentDepthNode.id));
    frame.resources.provide(
      FrameResourceIds.hdrColor,
      frame.resources.texture(FrameResourceIds.hdrColor),
    );
  }
}

const RenderSettings _plain = RenderSettings();

void main() {
  test('each view lands in its own layer of the runtime\'s image', () {
    final device = FakeBackend(
      extraFeatures: <DeviceFeature>[
        DeviceFeature.textureCopy,
        DeviceFeature.textureArrays,
        DeviceFeature.textureWrites,
      ],
    );
    final scene = Scene();
    final views = _eyes(scene);
    final renderer = Renderer.create(device: device);
    final peek = _Peek();
    final layer = ProjectionLayerNode();
    renderer.renderSteps
      ..addNode(peek)
      ..addNode(layer);
    // A first frame with no image: the picture is untouched and nothing is
    // copied.
    renderer.render(width: 64, height: 32, scene: scene, views: views);
    expect(layer.copied, 0);
    expect(peek.viewIndices, <int>[0, 1]);

    final image = device.createTexture(
      TextureDescriptor(
        width: 32,
        height: 32,
        format: peek.format!,
        dimension: TextureDimension.d2Array,
        depthOrArrayLayers: 2,
      ),
    );
    layer.target = image;
    device.calls.clear();
    final result = renderer.render(
      width: 64,
      height: 32,
      scene: scene,
      views: views,
      settings: _plain,
    );
    // Mutation: copy every view into layer 0, or from the left half twice.
    final copies = <Object?>[
      for (final call in device.calls)
        if (call.name == 'copyTextureToTexture') call.arguments,
    ];
    expect(copies, hasLength(2));
    final placed = <(int, int, int)>[
      for (final copy in copies)
        if (copy case (
          source: final TextureCopyLocation from,
          destination: final TextureCopyLocation to,
          width: final int width,
          height: _,
          depthOrArrayLayers: _,
        ))
          (from.x, to.z, width),
    ];
    expect(placed, <(int, int, int)>[(0, 0, 32), (32, 1, 32)]);
    expect(layer.copied, 2);
    expect(layer.frames, 1);
    // The picture shown is the one drawn: the node gives it back.
    expect(result.passes.map((p) => p.name), contains('projection layer'));
  });

  test('a device that copies nothing is refused by name, before a frame', () {
    final device = FakeBackend(
      extraFeatures: <DeviceFeature>[
        DeviceFeature.textureArrays,
        DeviceFeature.textureWrites,
      ],
    );
    final image = device.createTexture(
      const TextureDescriptor(
        width: 8,
        height: 8,
        format: TextureFormat.r8g8b8a8UNormInt,
        dimension: TextureDimension.d2Array,
        depthOrArrayLayers: 2,
      ),
    );
    expect(
      () => ProjectionLayerNode.check(
        device,
        image,
        views: 2,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
      throwsA(
        isA<UnsupportedCapabilityException>().having(
          (e) => e.feature,
          'feature',
          DeviceFeature.textureCopy,
        ),
      ),
    );
    final copying = FakeBackend(
      extraFeatures: <DeviceFeature>[DeviceFeature.textureCopy],
    );
    expect(
      () => ProjectionLayerNode.check(
        copying,
        image,
        views: 3,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
      throwsArgumentError,
      reason: 'three views, two layers',
    );
    expect(
      () => ProjectionLayerNode.check(
        copying,
        image,
        views: 2,
        format: TextureFormat.r16g16b16a16Float,
      ),
      throwsArgumentError,
      reason: 'a copy keeps the format',
    );
  });

  test('the real world\'s depth reaches a node that occludes with it', () {
    final device = FakeBackend();
    final scene = Scene();
    final camera = CameraNode()..setPosition(0.0, 1.0, 3.0);
    scene
      ..add(camera)
      ..add(
        MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          RenderMaterial(),
        ),
      );
    final renderer = Renderer.create(device: device);
    final depth = EnvironmentDepthNode();
    final occluder = _Occluder();
    renderer.renderSteps
      ..addNode(depth)
      ..addNode(occluder);
    void draw() => renderer.render(
      width: 16,
      height: 16,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );

    draw();
    // Mutation: provide nothing without a depth and the occluder is culled.
    expect(occluder.seen.single.width, 1, reason: 'nothing measured yet');
    expect(occluder.seen.single.format, TextureFormat.r32Float);

    depth.depth = EnvironmentDepth(
      width: 4,
      height: 2,
      meters: Float32List.fromList(<double>[1, 2, 3, 4, 5, 6, 7, 8]),
    );
    draw();
    expect(occluder.seen.last.width, 4);
    expect(occluder.seen.last.height, 2);
    expect(
      () => EnvironmentDepth(width: 2, height: 2, meters: Float32List(3)),
      throwsArgumentError,
    );
    for (var i = 0; i < 6; i++) {
      draw();
    }
    // Uploads are given back once no frame in flight can read them.
    bool held(TextureHandle t) =>
        !device.releasedTextures.any((r) => identical(r, t));
    expect(occluder.seen.where(held).length, lessThanOrEqualTo(4));
    depth.release();
    expect(occluder.seen.where(held), isEmpty);
  });
}
