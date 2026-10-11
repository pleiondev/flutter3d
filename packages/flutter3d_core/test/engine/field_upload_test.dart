// A field in the frame graph: a resource under its own id, put on a device
// where its declaration says, refused by name where the device cannot hold
// it, and whatever only read it culled with it.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException, Unit;
import 'package:flutter3d_hardware/backend.dart' show wrapTexture;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:test/test.dart';

const _frame = ResourceId('frame');

FieldDeclaration _heat({int components = 1}) => FieldDeclaration(
  id: 'acme.heat',
  quantity: 'f3d.temperature',
  unit: Unit.kelvin,
  grid: FieldGrid(4, 3, 2, components: components),
  writer: const FieldAccess.simulation('acme.diffuse'),
  readers: const <FieldAccess>[FieldAccess.frame('acme.shimmer')],
);

/// A node that draws from the field: what a volume is.
final class _Shimmer extends RenderNode {
  _Shimmer();

  FieldStorage? seen;

  @override
  String get name => 'acme.shimmer';

  @override
  List<ResourceId> get reads => const <ResourceId>[ResourceId('acme.heat')];

  @override
  List<ResourceId> get writes => const <ResourceId>[_frame];

  @override
  void execute(RenderFrame frame) =>
      seen = frame.resources.field(const ResourceId('acme.heat'));
}

final class _Source with FrameTextureSource {
  @override
  TextureHandle acquire(RenderTargetDescriptor spec) => wrapTexture(
    backend: 'frame',
    width: spec.width,
    height: spec.height,
    format: spec.format,
  );

  @override
  void release(TextureHandle texture) {}
}

final class _Services with RenderServices {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('a field upload draws nothing');
}

CompiledFrameGraph _compile(FieldUpload upload, _Shimmer shimmer) =>
    (FrameGraph()
          ..addNode(upload)
          ..addNode(shimmer))
        .compile(outputs: const <ResourceId>[_frame]);

/// Runs [graph]'s nodes in order on [device].
void _run(CompiledFrameGraph graph, GraphicsDevice device) {
  final resources = FrameResources(
    source: _Source(),
    graph: graph,
    frameWidth: 8,
    frameHeight: 8,
  );
  final frame = RenderFrame(
    device: device,
    resources: resources,
    services: _Services(),
    settings: const RenderSettings(),
    width: 8,
    height: 8,
  );
  for (var i = 0; i < graph.order.length; i++) {
    resources.beginNode(i);
    (graph.order[i] as RenderNode).execute(frame);
    resources.endNode(i);
  }
}

void main() {
  test('a field nothing placed is not in the frame, and neither is its '
      'reader', () {
    final upload = FieldUpload(HostField(_heat()));
    // Mutation: answer isSupported before a placement. The frame would run
    // an upload with no device to hold the field and throw from execute.
    expect(upload.isSupported, isFalse);
    expect(upload.refusal!.reason, FieldRefusal.notPlaced);
    expect(upload.refusal!.field, 'acme.heat');
    final graph = _compile(upload, _Shimmer());
    expect(graph.skipReason('acme.heat upload'), PassSkip.unsupported);
    expect(graph.skipReason('acme.shimmer'), PassSkip.starved);
  });

  test('a device without 3D textures refuses the field by name', () {
    final upload = FieldUpload(HostField(_heat()));
    final refused = upload.place(
      ComputeExecutors(
        device: FakeBackend(
          extraFeatures: const <DeviceFeature>[DeviceFeature.textureWrites],
        ),
      ),
    );
    // Mutation: allocate the texture and let the device throw mid-frame.
    expect(refused, isA<CapabilityException>());
    expect(refused!.reason, FieldRefusal.missingFeature);
    expect(refused.capability, DeviceFeature.texture3D);
    expect(
      refused.message,
      'field "acme.heat" cannot be held in texture3D on FakeBackend: the device '
      'has no 3d-textures',
    );
    expect(upload.refusal, same(refused));
    expect(
      _compile(upload, _Shimmer()).skipReason('acme.heat upload'),
      PassSkip.unsupported,
    );
  });

  test('a 3D texture field is made once and written every frame, and its '
      'reader takes it under the field\'s id', () {
    final device = FakeBackend(
      extraFeatures: const <DeviceFeature>[
        DeviceFeature.texture3D,
        DeviceFeature.textureWrites,
      ],
    );
    final source = HostField(_heat())..setValueAt(3, 2, 1, 300);
    final upload = FieldUpload(source);
    expect(upload.place(ComputeExecutors(device: device)), isNull);
    expect(upload.executor!.placement, ComputePlacement.device);
    final shimmer = _Shimmer();
    final graph = _compile(upload, shimmer);
    expect(graph.order.map((n) => n.name), <String>[
      'acme.heat upload',
      'acme.shimmer',
    ]);
    _run(graph, device);
    _run(graph, device);

    final made = device.calls.where((c) => c.name == 'createTexture').toList();
    // Mutation: make the texture every frame. A field stepped at sixty
    // frames a second would allocate sixty textures a second.
    expect(made, hasLength(1));
    final descriptor = made.single.arguments! as TextureDescriptor;
    expect(descriptor.dimension, TextureDimension.d3);
    expect(
      (descriptor.width, descriptor.height, descriptor.depthOrArrayLayers),
      (4, 3, 2),
    );
    expect(descriptor.format, TextureFormat.r32Float);
    expect(device.calls.where((c) => c.name == 'writeTexture'), hasLength(2));
    final seen = shimmer.seen! as Texture3DField;
    expect(seen.declaration.id, 'acme.heat');
    expect(seen.residence, FieldResidence.texture3D);

    upload.release();
    expect(upload.isSupported, isFalse);
  });

  test('a cell of three values has no texel format, and says so', () {
    final upload = FieldUpload(HostField(_heat(components: 3)));
    final refused = upload.place(
      ComputeExecutors(
        device: FakeBackend(
          extraFeatures: const <DeviceFeature>[
            DeviceFeature.texture3D,
            DeviceFeature.textureWrites,
          ],
        ),
      ),
    );
    expect(refused!.reason, FieldRefusal.missingFeature);
    expect('${refused.cause}', contains('1, 2 or 4 floats'));
  });

  test('a buffer field goes where compute is placed, and is refused where '
      'no executor has it', () {
    final upload = FieldUpload(
      HostField(_heat()),
      residence: FieldResidence.buffer,
    );
    final refused = upload.place(ComputeExecutors(device: FakeBackend()));
    // Mutation: hold it on the drawing device whatever it has. A fake with
    // no compute would be handed a storage buffer it cannot make.
    expect(refused!.reason, FieldRefusal.noPlacement);
    expect(refused.cause, isA<ComputePlacementException>());
    expect(upload.isSupported, isFalse);
  });

  test('a field is provided under its own id and no other', () {
    final graph = _compile(FieldUpload(HostField(_heat())), _Shimmer());
    final resources = FrameResources(
      source: _Source(),
      graph: graph,
      frameWidth: 8,
      frameHeight: 8,
    );
    expect(
      () => resources.provideField(
        const ResourceId('acme.cold'),
        HostField(_heat()),
      ),
      throwsA(isA<FrameGraphError>()),
    );
    expect(
      () => FieldUpload(HostField(_heat()), residence: FieldResidence.host),
      throwsArgumentError,
    );
  });

  group('through the renderer', () {
    test('one call places the upload and puts it in the frame, and its '
        'registration takes it out and lets the storage go', () {
      // Mutation: add the node without placing it. The frame reports the
      // field unsupported on a device that holds 3D textures, and every
      // volume that reads it is culled.
      final device = FakeBackend(
        extraFeatures: const <DeviceFeature>[
          DeviceFeature.texture3D,
          DeviceFeature.textureWrites,
        ],
      );
      final renderer = Renderer.create(device: device);
      final upload = FieldUpload(HostField(_heat()));
      final added = renderer.renderSteps.addFieldUpload(
        upload,
        ComputeExecutors(device: device),
      );
      expect(upload.isSupported, isTrue);
      expect(
        renderer.renderSteps.nodesAt(RenderAnchor.beforeOpaque),
        contains('acme.heat upload'),
      );
      added.cancel();
      expect(
        renderer.renderSteps.nodesAt(RenderAnchor.beforeOpaque),
        isNot(contains('acme.heat upload')),
      );
      expect(upload.isSupported, isFalse);
    });

    test('an upload nothing can hold is added all the same, with its '
        'refusal', () {
      final device = FakeBackend();
      final renderer = Renderer.create(device: device);
      final upload = FieldUpload(HostField(_heat()));
      renderer.renderSteps.addFieldUpload(
        upload,
        ComputeExecutors(device: device),
      );
      expect(upload.refusal!.capability, DeviceFeature.texture3D);
      expect(
        renderer.renderSteps.nodesAt(RenderAnchor.beforeOpaque),
        contains('acme.heat upload'),
      );
    });
  });
}
