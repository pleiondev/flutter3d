/// `gfx-23n`: frames that must be the same frame, and the one that is not.
///
///     flutter test test/anchor_identity_test.dart
///
/// **An anchor is a pair of configurations that describe one picture.** Say
/// the same thing two ways — leave a setting at its default or pass the
/// default, switch an effect off by its own flag or by name, register a node
/// and disable it or never register it — and the bytes have to match. Each of
/// those is a way somebody will actually write the same frame, and each is a
/// way the engine could quietly draw two different ones.
///
/// **The fifth anchor is here because it does not hold, and that is the
/// finding.** A node that merely *declares* an optional read of the surface
/// buffer changes the picture: declaring it is what attaches the second colour
/// attachment, and attachments in one target must agree on sample count, so
/// the whole scene pass stops multisampling. Nothing is read, nothing is
/// drawn, and every edge in the frame gets worse. The row that predicted this
/// asked for a fixture holding it; what the fixture actually holds is that the
/// engine *reports* it — `gfx-20n`'s `msaaDeclined` names the cause — because
/// an anchor that failed silently would be the defect rather than the test.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// A node that declares an optional surface-buffer read and draws nothing.
///
/// The shape `gfx-43n`, `gfx-44n` and `gfx-45n` will each have: a viewport
/// shading pass that wants the buffer when the frame has one and works
/// without it. Drawing nothing is deliberate — the claim under test is about
/// the *declaration*.
final class _DeclaresSurface extends RenderNode {
  @override
  String get name => 'declares surface';

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  void execute(NodeFrame frame) {
    // The version it read, handed back untouched: a link in the chain that
    // changes no pixel, so anything the frame does differently is the
    // declaration's doing and not this node's.
    frame.resources.provide(
      FrameResourceIds.hdrColour,
      frame.resources.texture(FrameResourceIds.hdrColour),
    );
  }
}

/// A lit ball with a hard edge against the background, so multisampling has
/// something to show, and the frame's own report beside its pixels.
Future<({List<int> pixels, FrameResult result})> _frame(
  RenderSettings settings, {
  List<RenderNode> nodes = const <RenderNode>[],
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  for (final node in nodes) {
    renderer.nodes.add(node);
  }

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.6).build()),
        Material(name: 'ball', baseColor: Vector4(0.9, 0.3, 0.2, 1.0)),
      ),
    )
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 3.0));

  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.05, 0.05, 0.08, 1.0),
      ),
    ],
    settings: settings,
  );
  final bytes = await device.readPixels(result.frame);
  return (
    pixels: <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ],
    result: result,
  );
}

/// The same frame on a device that *can* multisample, which is the only place
/// the fifth anchor's reason is visible: the software rasteriser multisamples
/// nothing, so it reports the device as the cause whatever a pass declares —
/// and it is right to, because there the device is the cause.
FrameResult _recorded({List<RenderNode> nodes = const <RenderNode>[]}) {
  final renderer = Renderer.create(device: FakeBackend());
  for (final node in nodes) {
    renderer.nodes.add(node);
  }
  final scene = Scene()
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 3.0));
  return renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: const RenderSettings(),
  );
}

void main() {
  group('four anchors that hold', () {
    test('the same settings twice are the same frame', () async {
      // The anchor everything else rests on: without determinism, a
      // difference between two configurations says nothing about either.
      const settings = RenderSettings(bloom: BloomSettings(intensity: 0.7));
      final a = await _frame(settings);
      final b = await _frame(settings);

      expect(a.pixels, b.pixels);
      expect(
        a.pixels,
        isNotEmpty,
        reason: 'an anchor comparing two empty readbacks holds vacuously',
      );
    });

    test(
      'a default left alone and a default passed are the same frame',
      () async {
        // Somebody will write both, and a default that meant something
        // different from itself is the kind of thing nothing would catch.
        final implicit = await _frame(const RenderSettings());
        final explicit = await _frame(const RenderSettings(renderScale: 1.0));

        expect(implicit.pixels, explicit.pixels);
      },
    );

    test('off by its own flag and off by name are the same frame', () async {
      // `gfx-37n`'s claim as an anchor: two ways to say "no bloom", one
      // picture. A toggle that was almost-off would make every golden
      // recorded against the flag stop describing the frame a caller gets
      // from the name.
      final byFlag = await _frame(
        const RenderSettings(bloom: BloomSettings(enabled: false)),
      );
      final byName = await _frame(
        const RenderSettings(disabledPasses: <String>{'bloom'}),
      );

      expect(byFlag.pixels, byName.pixels);
    });

    test('a node registered and disabled is a node never registered', () async {
      // `gfx-28n`'s key space as an anchor: registering an effect and
      // switching it off by name has to leave the frame a caller would get
      // without the effect at all. A node that changed the frame by existing
      // would make every toggle a guess — and this node is the one most able
      // to, because what it costs is paid by declaring rather than by
      // drawing.
      final disabled = await _frame(
        const RenderSettings(disabledPasses: <String>{'declares surface'}),
        nodes: <RenderNode>[_DeclaresSurface()],
      );
      final absent = await _frame(const RenderSettings());

      expect(disabled.pixels, absent.pixels);
      expect(
        disabled.result.antiAliasing.msaaDeclined,
        absent.result.antiAliasing.msaaDeclined,
        reason:
            'a disabled node still declaring its reads would take the '
            'multisampling with it and the pixels would not say so here',
      );
    });
  });

  group('the fifth anchor, which does not hold', () {
    test(
      'declaring an optional surface read changes how the scene is sampled',
      () {
        // **The prediction the row was written from.** The node draws nothing.
        // It declares that it would like the surface buffer if the frame has
        // one — and that declaration attaches the second colour attachment,
        // which takes multisampling away from the whole scene pass.
        //
        // On a device that can multisample, because that is the only place
        // this is visible: the rasteriser reports the device as the cause
        // whatever a pass declares, and is right to.
        final plain = _recorded();
        final declared = _recorded(nodes: <RenderNode>[_DeclaresSurface()]);

        expect(plain.antiAliasing.msaaSamples, greaterThan(1));
        expect(plain.antiAliasing.msaaDeclined, isNull);
        expect(declared.antiAliasing.msaaSamples, 1);
        expect(
          declared.antiAliasing.msaaDeclined,
          contains('surface buffer'),
          reason:
              'a pass that draws nothing changed how the scene was sampled, '
              'so the frame has to say which cause and not merely that it did',
        );
      },
    );

    test(
      'the difference is invisible on this backend, and reported anyway',
      () async {
        // Said plainly rather than left for somebody to discover: the software
        // rasteriser multisamples nothing, so its pixels are the same either
        // way and this anchor cannot be checked here by looking. The report is
        // what carries it, which is the argument for `gfx-20n` having been a
        // field rather than a note in a document.
        final plain = await _frame(const RenderSettings());
        final declared = await _frame(
          const RenderSettings(),
          nodes: <RenderNode>[_DeclaresSurface()],
        );

        expect(plain.result.antiAliasing.msaaSamples, 1);
        expect(declared.result.antiAliasing.msaaSamples, 1);
        expect(declared.pixels, plain.pixels);
        // And both blame the device rather than the declaration, which is the
        // ordering that keeps the report useful: the cause nobody can act on
        // is named ahead of the one they can.
        expect(plain.result.antiAliasing.msaaDeclined, contains('device'));
        expect(declared.result.antiAliasing.msaaDeclined, contains('device'));
      },
    );

    test('and the pass is in the frame, so the trade can be refused', () async {
      // The other half of the finding: a declaration this costly has to be
      // addressable. It is a registered name, so a caller who does not want
      // the trade can take it out — which is what makes the anchor above a
      // documented cost rather than a trap.
      final declared = await _frame(
        const RenderSettings(),
        nodes: <RenderNode>[_DeclaresSurface()],
      );

      expect(
        declared.result.passes.map((p) => p.name),
        contains('declares surface'),
      );
    });
  });
}
