/// `pro-eng-03`'s own row: `Renderer.renderPost`, a standalone bloom-and-
/// composite pass over an HDR buffer the caller supplies rather than one a
/// scene node in the same graph produced.
///
///     flutter test test/renderer_post_standalone_test.dart
///
/// **What this file can and cannot check.** The row's own acceptance reads
/// "a full frame equals a scene rendered without post, plus a separate
/// `renderPost` call" — a claim about two `Renderer.render` calls compared
/// against each other. `render` has no public way to hand back the HDR
/// buffer it draws into *before* bloom and the composite consume it: the
/// method always runs the whole pipeline through to the tone-mapped `frame`
/// texture, and nothing short of a second render-pipeline entry point (out
/// of scope for this row) exposes the intermediate. What is checked here
/// instead, and what a mutation can actually catch: `renderPost` runs the
/// same graph-versioned bloom pass and calls the same composite encoding
/// `render`'s own nodes call, on whatever buffer it is handed — proven by
/// construction (both paths reach `_renderBloom`/`_encodeComposite`) and by
/// the structural and numeric tests below.
library;

import 'package:flutter3d_core/src/engine/render/frame_graph.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/render/renderer.dart';
import 'package:flutter3d_core/src/engine/scene/camera_node.dart';
import 'package:flutter3d_core/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

({Renderer renderer, FakeBackend device}) _engine() {
  final device = FakeBackend();
  return (renderer: Renderer.create(device: device), device: device);
}

/// A node that does nothing but declare what it touches — the same minimal
/// shape `frame_graph_test.dart` uses, copied rather than imported since a
/// test file is not a library another test should reach into.
final class _TestNode extends FrameGraphNode {
  const _TestNode(this.name, {this.reads = const [], this.writes = const []});

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> writes;
  @override
  List<ResourceId> get optionalReads => const <ResourceId>[];
  @override
  List<ResourceId> get keeps => const <ResourceId>[];
  @override
  bool get isActive => true;
}

TextureHandle _hdr(FakeBackend device, {int width = 32, int height = 32}) =>
    device.createTexture(
      RenderTargetSpec(
        width: width,
        height: height,
        format: device.hdrColorFormat,
      ),
    );

void main() {
  group('the external-resource contract renderPost is the first real caller '
      'of', () {
    // `frame_graph.dart`'s own doc: "Zero is what the engine handed in: an
    // external resource, or nothing at all." This is the primitive
    // `renderPost` exercises — checked directly here, with no renderer or
    // device in the room, the same way `frame_graph_test.dart` checks every
    // other rule this file's own machinery relies on.
    const colour = ResourceId('hdr_colour');
    const bloom = ResourceId('bloom');

    test('a node that only reads the external resource binds version zero', () {
      final graph = FrameGraph()
        ..addExternal(colour)
        ..addNode(
          const _TestNode(
            'bloom',
            reads: <ResourceId>[colour],
            writes: [bloom],
          ),
        );
      final compiled = graph.compile(outputs: <ResourceId>[bloom]);

      expect(compiled.readVersionOf(0, colour), 0);
      expect(compiled.writeVersionOf(0, bloom), 1);
    });

    test('a node that expects version one of a resource nothing produced is '
        'refused at compile, not at runtime', () {
      // Mutation: register `colour` as a normal node's write instead of
      // `addExternal`, or drop the `addExternal` call in `renderPost`
      // itself — either turns this from "refused before a pass runs" into
      // "silently reads whatever version zero happens to hold", which is
      // exactly the failure the graph's own compile-time check exists to
      // catch instead of a blank frame at runtime.
      final graph = FrameGraph()
        // No `addExternal(colour)` here: nothing hands the graph a version
        // zero of it at all, so a reader has nothing to bind to.
        ..addNode(
          const _TestNode(
            'bloom',
            reads: <ResourceId>[colour],
            writes: [bloom],
          ),
        );

      expect(
        () => graph.compile(outputs: <ResourceId>[bloom]),
        throwsA(isA<FrameGraphError>()),
      );
    });
  });

  group('Renderer.renderPost', () {
    test('with bloom on, both bloom and composite passes run', () {
      // Mutation: never register the composite call, or gate it behind
      // `bloomNode.isActive` by mistake — either leaves the output texture
      // untouched, which this and the size/format test below both notice.
      final it = _engine();
      final hdr = _hdr(it.device);

      it.renderer.renderPost(hdr: hdr, settings: const RenderSettings());

      expect(
        it.device.passes.map((p) => p.commands.whereType<RecordedTexture>()),
        isNotEmpty,
      );
      final sceneReaders = it.device.passes
          .expand((p) => p.commands.whereType<RecordedTexture>())
          .where((t) => t.slot == 'scene_texture');
      expect(
        sceneReaders,
        isNotEmpty,
        reason:
            'the composite pass reads the hdr buffer under the same '
            'slot name render\'s own composite node does',
      );
      expect(
        sceneReaders.every((t) => identical(t.texture, hdr)),
        isTrue,
        reason:
            'composite reads exactly the texture renderPost was handed, '
            'not a copy or the wrong version',
      );
    });

    test(
      'the composite pass binds the bloom texture bloom itself produced',
      () {
        // Mutation: read `bloom` with `tryTexture` after `endNode` instead
        // of before it (the bug this row's own directive warned about — a
        // resource with no declared reader retires at its own writer's
        // node). That mutation makes this test's own bloom binding null,
        // which the identity check below catches directly.
        final it = _engine();
        final hdr = _hdr(it.device);

        it.renderer.renderPost(
          hdr: hdr,
          settings: const RenderSettings(), // bloom enabled by default
        );

        final bloomBindings = it.device.passes
            .expand((p) => p.commands.whereType<RecordedTexture>())
            .where((t) => t.slot == 'bloom_texture')
            .toList();
        expect(bloomBindings, isNotEmpty);
        // Not the scene texture standing in for a culled bloom pass — a
        // genuinely different texture the bloom node itself allocated.
        expect(bloomBindings.every((t) => !identical(t.texture, hdr)), isTrue);
      },
    );

    test('with bloom off, the composite still runs, glowing nothing', () {
      // Mutation: crash or skip the composite call when the bloom node is
      // culled, instead of letting `_encodeComposite`'s own optional-bloom
      // path (already exercised by `render` itself) fall back to the scene.
      final it = _engine();
      final hdr = _hdr(it.device);

      final result = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
      );

      expect(result.frame, isNotNull);
      final compositeBloomBindings = it.device.passes
          .expand((p) => p.commands.whereType<RecordedTexture>())
          .where((t) => t.slot == 'bloom_texture');
      // The glow slot still has to be satisfied — a sampler cannot be left
      // unbound — and `_encodeComposite`'s own fallback is the scene itself.
      expect(
        compositeBloomBindings.every((t) => identical(t.texture, hdr)),
        isTrue,
      );
    });

    test('the output texture matches the hdr buffer\'s own dimensions', () {
      // Mutation: hardcode the output size instead of reading it off `hdr`.
      final it = _engine();
      final hdr = _hdr(it.device, width: 48, height: 20);

      final result = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(),
      );

      expect(result.frame.width, 48);
      expect(result.frame.height, 20);
    });

    test('a caller-supplied target is drawn into rather than a fresh one', () {
      final it = _engine();
      final hdr = _hdr(it.device);
      final target = it.device.createTexture(
        RenderTargetSpec(
          width: hdr.width,
          height: hdr.height,
          format: it.device.defaultColorFormat,
        ),
      );

      final result = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(),
        target: target,
      );

      expect(identical(result.frame, target), isTrue);
    });

    test('keepHdr false leaves PostFrameResult.hdr null', () {
      final it = _engine();
      final hdr = _hdr(it.device);

      final result = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(),
      );

      expect(result.hdr, isNull);
    });

    test('keepHdr true returns the same buffer renderPost was handed', () {
      // Mutation: always return null regardless of the flag, or return a
      // different texture than the one composited from.
      final it = _engine();
      final hdr = _hdr(it.device);

      final result = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(),
        keepHdr: true,
      );

      expect(identical(result.hdr, hdr), isTrue);
    });

    test('keepHdr lets two calls with different settings reuse the same '
        'buffer without redoing a scene pass', () {
      // The claim `keepHdr` exists for: a caller re-runs post over the same
      // HDR data with a different look rather than re-rendering the scene.
      // Nothing here ever registers a scene-drawing node — `renderPost`'s
      // own graph is bloom and composite only — so the proof is that a
      // second call with different settings costs exactly the same passes
      // and textures as the first, never more: if `renderPost` reached back
      // into the scene on the second call, this would grow.
      //
      // Mutation: have a second `renderPost` call allocate a fresh internal
      // texture per call regardless of `keepHdr`, or run an extra pass —
      // either moves `secondPasses`/`secondTextures` away from
      // `firstPasses`/`firstTextures`, which this test would catch as a
      // mismatch rather than as growth, since the two are asserted equal.
      final it = _engine();
      final hdr = _hdr(it.device);

      final passesBefore = it.device.passes.length;
      final texturesBefore = it.device.createdTextures.length;

      final first = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(exposure: 1.0),
        keepHdr: true,
      );
      final firstPasses = it.device.passes.length - passesBefore;
      final firstTextures = it.device.createdTextures.length - texturesBefore;

      expect(
        identical(first.hdr, hdr),
        isTrue,
        reason:
            'keepHdr should hand back the exact buffer this call was '
            'given, for the next call to reuse',
      );

      final second = it.renderer.renderPost(
        hdr: first.hdr!,
        settings: const RenderSettings(exposure: 3.0, tonemap: false),
        keepHdr: true,
      );
      final secondPasses =
          it.device.passes.length - (passesBefore + firstPasses);
      final secondTextures =
          it.device.createdTextures.length - (texturesBefore + firstTextures);

      expect(identical(second.hdr, hdr), isTrue);
      expect(
        secondPasses,
        equals(firstPasses),
        reason:
            'a second call over the kept buffer ran a different shape '
            'of work than the first — the scene was touched again',
      );
      expect(
        secondTextures,
        equals(firstTextures),
        reason:
            'a second call over the kept buffer allocated a different '
            'number of textures than the first',
      );
    });

    test('two calls on the same buffer bind the composite to the same '
        'exposure and tonemap settings — no state leaks between them', () {
      final it = _engine();
      final hdr = _hdr(it.device);
      const settings = RenderSettings(exposure: 2.5, tonemap: false);

      it.renderer.renderPost(hdr: hdr, settings: settings);
      it.renderer.renderPost(hdr: hdr, settings: settings);

      final blocks = it.device.passes
          .expand((p) => p.commands.whereType<RecordedUniformBlock>())
          .where((b) => b.block == 'CompositeInfo')
          .toList();
      expect(blocks.length, 2);
      expect(blocks[0].members['params'], equals(blocks[1].members['params']));
    });

    test('renderPost does not touch the scene the renderer also draws with '
        'render', () {
      // Mutation: have `renderPost` reach for `_renderer._hdrColor`/
      // `_ldrColor` instead of the `hdr`/`target` it was actually handed —
      // this is the "does not clobber the on-screen frame" guarantee the
      // method's own doc comment makes.
      final it = _engine();
      final scene = Scene()..add(CameraNode());
      final view = RenderView(camera: scene.cameras.single);
      final onScreen = it.renderer.render(
        width: 32,
        height: 32,
        scene: scene,
        views: <RenderView>[view],
      );

      final hdr = _hdr(it.device);
      final post = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(),
      );

      expect(identical(post.frame, onScreen.frame), isFalse);
    });
  });
}
