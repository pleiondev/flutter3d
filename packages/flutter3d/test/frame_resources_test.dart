/// The half of the frame graph where the release bugs live.
///
/// `frame_graph.dart` — the ordering, the culling, the lifetimes — has had
/// thirty-one tests since it was written, because it is arithmetic. This file
/// had none and could not have had any: every method below took or returned a
/// `gpu.Texture`, which cannot be constructed without a device, so the rules
/// about who hands a texture back and when were checked by reading them, or by
/// a golden image noticing something a frame later. Both of the defects this
/// layer has actually had — releasing straight to the pool while the GPU was
/// still reading, and the bloom chain going back a level at a time — were found
/// that way.
///
/// [TextureHandle] is what made these reachable. A fake handle costs an
/// `Object`, a counting source costs twenty lines, and a real
/// [RenderTargetPool] driven by a fake allocator turns "handed back twice" from
/// something to reason about into a `StateError` with a stack.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d/src/engine/render/frame_graph.dart';
import 'package:flutter3d/src/engine/render/frame_resources.dart';

const ResourceId colour = ResourceId('colour');
const ResourceId atlas = ResourceId('atlas');
const ResourceId bloom = ResourceId('bloom');
const ResourceId frame = ResourceId('frame');

/// A node with nothing but declarations, which is all this layer ever reads.
///
/// [FrameGraphNode] rather than `RenderNode`: [FrameResources] is handed a
/// compiled graph and asks it about versions and lifetimes. It never runs
/// anything, so a node with a body would be a body no test could reach.
final class _Pass extends FrameGraphNode {
  const _Pass(
    this.name, {
    this.reads = const <ResourceId>[],
    this.optionalReads = const <ResourceId>[],
    this.writes = const <ResourceId>[],
    this.keeps = const <ResourceId>[],
    this.isActive = true,
  });

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> optionalReads;
  @override
  final List<ResourceId> writes;
  @override
  final List<ResourceId> keeps;
  @override
  final bool isActive;
}

/// Hands out distinct handles and remembers every acquire and every release.
///
/// The releases are a *list* and not a set, deliberately: half of what is
/// tested here is that a texture goes back exactly once, and a set would
/// swallow the second one — which is the bug.
final class _CountingSource implements FrameTextureSource {
  final List<TextureHandle> acquired = <TextureHandle>[];
  final List<TextureHandle> released = <TextureHandle>[];

  int _serial = 0;

  @override
  TextureHandle acquire(RenderTargetSpec spec) {
    final texture = fakeTexture(
      'acquired ${_serial++}',
      width: spec.width,
      height: spec.height,
      format: spec.format,
      sampleCount: spec.sampleCount,
      storageMode: spec.storageMode,
    );
    acquired.add(texture);
    return texture;
  }

  @override
  void release(TextureHandle texture) => released.add(texture);

  /// How many times [texture] was handed back. Two is a bug; zero is a leak.
  int releaseCountOf(TextureHandle texture) =>
      released.where((other) => identical(other, texture)).length;
}

/// A [TextureAllocator] that makes handles over nothing.
///
/// This is the whole trick. The pool's job is bookkeeping; the only line in it
/// that ever needed a device was `createTexture`, and with that injected the
/// real pool runs in a unit test unchanged.
final class _FakeAllocator implements TextureAllocator {
  int created = 0;

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => fakeTexture(
        'created ${created++}',
        width: spec.width,
        height: spec.height,
        format: spec.format,
        sampleCount: spec.sampleCount,
        storageMode: spec.storageMode,
      );
}

/// A texture handle over an ordinary object.
///
/// [label] is only ever read by a failing expectation. Nothing off-device looks
/// inside a handle, which is the point of `backend` being an `Object`.
TextureHandle fakeTexture(
  String label, {
  int width = 640,
  int height = 480,
  TextureFormat format = TextureFormat.r16g16b16a16Float,
  int sampleCount = 1,
  StorageMode storageMode = StorageMode.devicePrivate,
}) =>
    TextureHandle(
      backend: label,
      width: width,
      height: height,
      format: format,
      sampleCount: sampleCount,
      storageMode: storageMode,
    );

CompiledFrameGraph compile(
  List<FrameGraphNode> passes, {
  required List<ResourceId> outputs,
}) {
  final graph = FrameGraph();
  for (final pass in passes) {
    graph.addNode(pass);
  }
  return graph.compile(outputs: outputs);
}

FrameResources resourcesFor(
  CompiledFrameGraph graph,
  FrameTextureSource source, {
  List<ResourceDesc> declare = const <ResourceDesc>[],
}) {
  final resources = FrameResources(
    source: source,
    graph: graph,
    frameWidth: 640,
    frameHeight: 480,
  );
  for (final desc in declare) {
    resources.declare(desc);
  }
  return resources;
}

const ResourceDesc colourDesc = ResourceDesc(
  id: colour,
  format: TextureFormat.r16g16b16a16Float,
);
const ResourceDesc bloomDesc = ResourceDesc(
  id: bloom,
  format: TextureFormat.r16g16b16a16Float,
  size: FrameFraction(2),
);

void main() {
  group('a transient resource may not be read', () {
    test('declaring one something reads is refused', () {
      // Tile memory does not survive the pass that wrote it, so the reader
      // would sample whatever is left in the tile. On a tiler that is a wrong
      // picture with nothing logged; on a desktop backend that ignores the
      // storage mode it might even work, which is worse — it would then pass
      // every test run here and fail on the hardware the mode exists for.
      final graph = compile(
        <FrameGraphNode>[
          const _Pass('writer', writes: <ResourceId>[colour]),
          // The reader must produce something the frame asks for, or the
          // graph culls it and there is no reader left to protect.
          const _Pass('reader',
              reads: <ResourceId>[colour], writes: <ResourceId>[bloom]),
        ],
        outputs: <ResourceId>[bloom],
      );
      final resources = FrameResources(
        source: _CountingSource(),
        graph: graph,
        frameWidth: 640,
        frameHeight: 480,
      );

      expect(
        () => resources.declare(const ResourceDesc(
          id: colour,
          format: TextureFormat.r16g16b16a16Float,
          storageMode: StorageMode.deviceTransient,
        )),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('colour'))),
      );
    });

    test('one nobody reads is allowed', () {
      // The case the mode exists for: a depth attachment a pass writes and
      // nothing else ever looks at. Refusing this would make the check useless.
      final graph = compile(
        <FrameGraphNode>[const _Pass('writer', writes: <ResourceId>[colour])],
        outputs: <ResourceId>[colour],
      );
      final resources = FrameResources(
        source: _CountingSource(),
        graph: graph,
        frameWidth: 640,
        frameHeight: 480,
      );

      expect(
        () => resources.declare(const ResourceDesc(
          id: colour,
          format: TextureFormat.r16g16b16a16Float,
          storageMode: StorageMode.deviceTransient,
        )),
        returnsNormally,
      );
    });
  });

  group('a node is held to its keeps', () {
    // The promise `keeps` makes is the one thing about it a schedule cannot
    // enforce: a maintained resource is bound on every frame the node runs,
    // drawn into or not, because "a frame that drew nothing still has something
    // worth sampling" is the whole of what keeping means. A node that provides
    // it only on the frames it drew has quietly turned it back into a write,
    // and nothing downstream can tell — the reader simply finds nothing and
    // does without, which for the point-light atlas means the shadows blink
    // off for one frame out of every few and come back.

    const maintainer = _Pass('cube shadow', keeps: <ResourceId>[atlas]);
    const reader = _Pass(
      'scene',
      reads: <ResourceId>[atlas],
      writes: <ResourceId>[frame],
    );

    test('a node that declares keeps and binds nothing throws, naming itself',
        () {
      final graph = compile(
        const <FrameGraphNode>[maintainer, reader],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(graph, source);

      resources.beginNode(0);
      // The node ran and drew nothing — the ordinary case for the atlas, and
      // exactly when the mistake is made.
      expect(
        () => resources.endNode(0),
        throwsA(
          isA<FrameGraphError>().having(
            (e) => e.message,
            'message',
            allOf(contains('cube shadow'), contains('atlas')),
          ),
        ),
      );
    });

    test('a node that binds it every frame is fine', () {
      final graph = compile(
        const <FrameGraphNode>[maintainer, reader],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(graph, source);

      final kept = fakeTexture('the atlas');
      resources.beginNode(0);
      resources.provide(atlas, kept);
      resources.endNode(0);

      resources.beginNode(1);
      expect(resources.tryTexture(atlas), same(kept));
    });

    test('a plain write left unbound is not an error', () {
      // The other side of the distinction, and it has to stay legal: the
      // directional shadow map is redrawn from nothing every frame, so a frame
      // whose shadow pass gave up honestly has no map, and the reader is meant
      // to find null and light everything unoccluded.
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('shadow map', writes: <ResourceId>[atlas]),
          reader,
        ],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(graph, _CountingSource());

      resources.beginNode(0);
      resources.endNode(0);

      resources.beginNode(1);
      expect(resources.tryTexture(atlas), isNull);
    });
  });

  group('releasing by identity', () {
    // Writing in place is the default: a pass that reads a resource and writes
    // it back drew *into the texture it was given*, so the new version starts
    // out standing on the same one. Two versions, one texture — and it goes
    // back to the pool exactly once. Guard on the version instead of on the
    // texture and the pool is told it has two of something it has one of; the
    // next two acquirers of that shape are handed the same texture and draw
    // over each other.

    const scene = _Pass('scene', writes: <ResourceId>[colour]);
    const overlay = _Pass(
      'overlay',
      reads: <ResourceId>[colour],
      writes: <ResourceId>[colour],
    );

    test('an in-place write draws into the texture it was handed', () {
      final graph = compile(
        const <FrameGraphNode>[scene, overlay],
        outputs: const <ResourceId>[colour],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final drawn = resources.texture(colour);
      resources.endNode(0);

      resources.beginNode(1);
      // Not a second allocation. If this were one, the overlay would be drawing
      // onto a blank texture and the scene would vanish behind it.
      expect(resources.texture(colour), same(drawn));
      expect(source.acquired, hasLength(1));
    });

    test('a later reader gets what the in-place pass drew into', () {
      // Where the aliasing is actually load-bearing, and it took a deliberately
      // broken copy of this class to find that the two tests above do not need
      // it: the overlay is handed the right texture by its own *read* binding
      // whether or not the write version was ever bound. It is the pass after
      // it that binds to `colour@2` — and with nothing behind that version the
      // frame does not fail, it allocates a second, blank texture and composites
      // that. Everything the frame drew is gone and nothing reports an error.
      final graph = compile(
        const <FrameGraphNode>[
          scene,
          overlay,
          _Pass(
            'composite',
            reads: <ResourceId>[colour],
            writes: <ResourceId>[frame],
          ),
        ],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final drawn = resources.texture(colour);
      resources.endNode(0);
      resources.beginNode(1);
      resources.texture(colour);
      resources.endNode(1);

      resources.beginNode(2);
      expect(resources.texture(colour), same(drawn));
      expect(source.acquired, hasLength(1));
    });

    test('two versions standing on one texture go back once', () {
      final graph = compile(
        const <FrameGraphNode>[scene, overlay],
        outputs: const <ResourceId>[colour],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final drawn = resources.texture(colour);
      resources.endNode(0);
      // Nothing yet: the overlay still reads this version.
      expect(source.released, isEmpty);

      resources.beginNode(1);
      resources.texture(colour);
      resources.endNode(1);

      // Both `colour@1` and `colour@2` retire here, and they are one texture.
      expect(source.releaseCountOf(drawn), 1);
    });

    test('the pool itself rejects the double release', () {
      // The same fact where it actually bites. `RenderTargetPool.release`
      // throws for a texture it does not have lent out, so a second hand-back
      // is an exception here rather than a corrupted free list that surfaces
      // two frames later as a texture drawn over by somebody else.
      final pool = RenderTargetPool(_FakeAllocator());
      final graph = compile(
        const <FrameGraphNode>[scene, overlay],
        outputs: const <ResourceId>[colour],
      );
      final resources = resourcesFor(
        graph,
        ImmediateTextureSource(pool),
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      resources.texture(colour);
      resources.endNode(0);
      resources.beginNode(1);
      resources.texture(colour);
      resources.endNode(1);

      expect(pool.lentCount, 0);
      expect(pool.pooledCount, 1);
      expect(pool.createdCount, 1);
    });

    test('a pass that provides its own output frees the one it read', () {
      // Reflections. It samples the scene while it writes, and a texture cannot
      // be both, so it produces a second one and says so — at which point the
      // version it read is nobody's and goes back, while the one it provided is
      // its own and must not.
      final graph = compile(
        const <FrameGraphNode>[scene, overlay],
        outputs: const <ResourceId>[colour],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final drawn = resources.texture(colour);
      resources.endNode(0);

      final own = fakeTexture("the reflection pass's own target");
      resources.beginNode(1);
      resources.provide(colour, own);
      expect(resources.tryTexture(colour), same(drawn),
          reason: 'a read still sees what it reads, not what it provided');
      resources.endNode(1);

      expect(source.releaseCountOf(drawn), 1);
      // Provided, therefore never acquired here, therefore never handed back.
      // Losing this is how the renderer's own colour target — which outlives the
      // frame and becomes the ui.Image — would end up in the pool.
      expect(source.releaseCountOf(own), 0);
    });
  });

  group('where the pixels came from', () {
    // `tryTexture` answers "is there a texture", which is not the same question
    // as "did this frame draw one". A shadow map that was not drawn and an
    // atlas deliberately holding an earlier frame's pixels both come back as a
    // texture and they mean opposite things.

    test('a resource this frame drew is drawn', () {
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('scene', writes: <ResourceId>[colour]),
          _Pass('composite',
              reads: <ResourceId>[colour], writes: <ResourceId>[frame]),
        ],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(
        graph,
        _CountingSource(),
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      resources.texture(colour);
      resources.endNode(0);

      resources.beginNode(1);
      expect(resources.originOf(colour), ResourceOrigin.drawn);
    });

    test('a resource a node maintains is kept', () {
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('cube shadow', keeps: <ResourceId>[atlas]),
          _Pass('scene', reads: <ResourceId>[atlas], writes: <ResourceId>[
            frame,
          ]),
        ],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(graph, _CountingSource());

      resources.beginNode(0);
      resources.provide(atlas, fakeTexture('the atlas'));
      resources.endNode(0);

      resources.beginNode(1);
      // Same texture, opposite meaning to the case above: some of these pixels
      // predate this frame and sampling them is exactly right. A consumer that
      // could not tell the two apart would either refuse a valid atlas or
      // sample a stale map.
      expect(resources.originOf(atlas), ResourceOrigin.kept);
    });

    test('a resource nobody produced has no origin at all', () {
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('bloom', writes: <ResourceId>[bloom], isActive: false),
          _Pass('composite',
              optionalReads: <ResourceId>[bloom],
              writes: <ResourceId>[frame]),
        ],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(
        graph,
        _CountingSource(),
        declare: const <ResourceDesc>[bloomDesc],
      );

      resources.beginNode(0);
      expect(resources.originOf(bloom), isNull);
      // And null without allocating: a culled effect must cost nothing, which
      // is the whole reason `tryTexture` is a separate call from `texture`.
      expect(resources.tryTexture(bloom), isNull);
    });
  });

  group('scratch', () {
    // Everything below the top of a bloom chain: real memory no other pass will
    // ever name. It has to come from the frame's source and not from the pool
    // directly, because the command buffers reading it are still in flight when
    // the pass returns — the defect that was fixed once in this class and lived
    // on in `_renderBloom` for months afterwards.

    const scene = _Pass('scene', writes: <ResourceId>[colour]);
    const composite = _Pass(
      'composite',
      reads: <ResourceId>[colour],
      writes: <ResourceId>[frame],
    );

    RenderTargetSpec spec(int divisor) => RenderTargetSpec(
          width: 640 ~/ divisor,
          height: 480 ~/ divisor,
          format: TextureFormat.r16g16b16a16Float,
        );

    test('a node frees its own scratch when it ends', () {
      final graph = compile(
        const <FrameGraphNode>[scene, composite],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(graph, source);

      resources.beginNode(0);
      final levels = <TextureHandle>[
        for (var i = 2; i <= 16; i *= 2) resources.transient(spec(i)),
      ];
      expect(source.released, isEmpty, reason: 'not while the pass is running');
      resources.endNode(0);

      for (final level in levels) {
        expect(source.releaseCountOf(level), 1);
      }
    });

    test("one node's scratch is not handed back again by the next", () {
      // The list is cleared, not merely walked. Left standing, every later node
      // in the frame would release the same chain again, and by the composite
      // the pool would be holding one texture in four places.
      final graph = compile(
        const <FrameGraphNode>[scene, composite],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(graph, source);

      resources.beginNode(0);
      final scratch = resources.transient(spec(2));
      resources.endNode(0);

      resources.beginNode(1);
      resources.endNode(1);

      expect(source.releaseCountOf(scratch), 1);
    });

    test('scratch is never confused with a named resource', () {
      // It is keyed on nothing, because nothing names it. Asking the frame for
      // a resource must not find a scratch texture lying about.
      final graph = compile(
        const <FrameGraphNode>[scene, composite],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(graph, _CountingSource());

      resources.beginNode(0);
      resources.transient(spec(2));
      expect(resources.tryTexture(colour), isNull);
    });
  });

  group('a frame that ends early', () {
    // A pass that throws leaves textures lent out and the pool has no other way
    // to learn they are free — one set of targets per attempt, and a frame that
    // fails tends to fail again next frame. `releaseAll` was written for this
    // and, until recently, had no caller at all.

    const scene = _Pass('scene', writes: <ResourceId>[colour]);
    const bloomPass = _Pass(
      'bloom',
      reads: <ResourceId>[colour],
      writes: <ResourceId>[bloom],
    );
    const composite = _Pass(
      'composite',
      reads: <ResourceId>[colour, bloom],
      writes: <ResourceId>[frame],
    );

    test('everything still held goes back, once each', () {
      final graph = compile(
        const <FrameGraphNode>[scene, bloomPass, composite],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc, bloomDesc],
      );

      resources.beginNode(0);
      final lit = resources.texture(colour);
      resources.endNode(0);

      resources.beginNode(1);
      final glow = resources.texture(bloom);
      final scratch = resources.transient(
        const RenderTargetSpec(
          width: 160,
          height: 120,
          format: TextureFormat.r16g16b16a16Float,
        ),
      );
      // Here the pass throws, so `endNode` never runs.
      resources.releaseAll();

      expect(source.releaseCountOf(lit), 1);
      expect(source.releaseCountOf(glow), 1);
      expect(source.releaseCountOf(scratch), 1);
      expect(source.released, hasLength(3));
    });

    test('it holds back what the frame does not own', () {
      final graph = compile(
        const <FrameGraphNode>[scene, bloomPass, composite],
        outputs: const <ResourceId>[frame],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[bloomDesc],
      );

      final own = fakeTexture("the renderer's own HDR target");
      resources.beginNode(0);
      resources.provide(colour, own);
      resources.releaseAll();

      expect(source.releaseCountOf(own), 0);
    });

    test('an in-place write over a provided texture is still not the pool’s',
        () {
      // Ownership travels with the aliasing. The overlay draws into the
      // renderer's own HDR target and produces a second version of the name
      // standing on it; if that version were treated as the frame's own
      // allocation, the texture that outlives the frame and becomes the
      // `ui.Image` would be handed to the pool and lent to the next acquirer.
      final graph = compile(
        const <FrameGraphNode>[
          scene,
          _Pass(
            'overlay',
            reads: <ResourceId>[colour],
            writes: <ResourceId>[colour],
          ),
        ],
        outputs: const <ResourceId>[colour],
      );
      final source = _CountingSource();
      final resources = resourcesFor(graph, source);

      final own = fakeTexture("the renderer's own HDR target");
      resources.beginNode(0);
      resources.provide(colour, own);
      resources.endNode(0);

      resources.beginNode(1);
      expect(resources.texture(colour), same(own));
      resources.releaseAll();

      expect(source.releaseCountOf(own), 0);
    });

    test('an in-place chain still goes back once', () {
      // The same identity guard as on the ordinary path, on the path taken
      // exactly when something has already gone wrong — which is where a second
      // release would be hardest to attribute.
      final graph = compile(
        const <FrameGraphNode>[
          scene,
          _Pass(
            'overlay',
            reads: <ResourceId>[colour],
            writes: <ResourceId>[colour],
          ),
        ],
        outputs: const <ResourceId>[colour],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final lit = resources.texture(colour);
      resources.endNode(0);
      resources.beginNode(1);
      resources.texture(colour);
      resources.releaseAll();

      expect(source.releaseCountOf(lit), 1);
    });

    test('a broken keeps promise is a frame that ends early', () {
      // The two halves together, which is how the renderer wires them: the
      // resource layer throws, the frame's catch calls `releaseAll`, and the
      // targets acquired before the failure come back rather than being lost
      // one set per attempt.
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('cube shadow', keeps: <ResourceId>[atlas]),
          _Pass(
            'scene',
            reads: <ResourceId>[atlas],
            writes: <ResourceId>[colour],
          ),
        ],
        outputs: const <ResourceId>[colour],
      );
      final source = _CountingSource();
      final resources = resourcesFor(
        graph,
        source,
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final scratch = resources.transient(
        const RenderTargetSpec(
          width: 1024,
          height: 1024,
          format: TextureFormat.r16g16b16a16Float,
        ),
      );
      expect(() => resources.endNode(0), throwsA(isA<FrameGraphError>()));
      // Nothing was released by the throw itself — `endNode` gives up before it
      // gets that far, which is precisely why the caller has to.
      expect(source.released, isEmpty);

      resources.releaseAll();
      expect(source.releaseCountOf(scratch), 1);
    });
  });

  group('asking for something nobody described', () {
    test('a resource neither declared nor provided names itself', () {
      // The graph accepted the read because some node writes the name; this is
      // the other half of that promise, and the two are made in different
      // places. Without the message the failure is a null texture bound to a
      // sampler, which on this backend is a native crash with no Dart frame.
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('scene', writes: <ResourceId>[colour]),
          _Pass('composite',
              reads: <ResourceId>[colour], writes: <ResourceId>[frame]),
        ],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(graph, _CountingSource());

      resources.beginNode(0);
      expect(
        () => resources.texture(colour),
        throwsA(
          isA<FrameGraphError>()
              .having((e) => e.message, 'message', contains('colour')),
        ),
      );
    });

    test('a node reading a resource it never declared is refused', () {
      // The scene writes the colour and the composite declares a read of it.
      // A third node that declares nothing would once have been handed the
      // latest version anything had put a texture behind — ordered after
      // nobody, and correct only by the accident of running late enough.
      //
      // The frame itself still gets that fallback, and must: its own reads
      // have no node to declare them. Breaking the path on purpose showed
      // exactly one caller and it was the frame, which is why the rule is
      // "not from inside a node" rather than "never".
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('scene', writes: <ResourceId>[colour]),
          // Writes something the frame asks for, so the graph keeps it. A node
          // writing nothing is culled, and a culled node's index belongs to
          // whoever took its place — which is how the first draft of this test
          // ended up asserting about the composite.
          _Pass('nosy', writes: <ResourceId>[bloom]),
          _Pass('composite',
              reads: <ResourceId>[colour], writes: <ResourceId>[frame]),
        ],
        outputs: const <ResourceId>[frame, bloom],
      );
      final resources = resourcesFor(
        graph,
        _CountingSource(),
        declare: const <ResourceDesc>[colourDesc],
      );

      resources.beginNode(0);
      final drawn = resources.texture(colour);
      resources.endNode(0);

      // Reading from outside any node is refused too, and used not to be.
      // The exception existed for "the frame's own reads" — and breaking it on
      // purpose named only tests that had built a node's frame without
      // entering the node. The engine enters one before every read, so the
      // exception was open for the convenience of tests, which is the wrong way
      // round. `drawn` is what the node saw; nothing outside can ask for it.
      expect(drawn, isNotNull);
      expect(
        () => resources.tryTexture(colour),
        throwsA(isA<FrameGraphError>().having(
            (e) => e.message, 'message', contains('outside any node'))),
      );

      resources.beginNode(1);
      expect(
        () => resources.tryTexture(colour),
        throwsA(
          isA<FrameGraphError>().having(
              (e) => e.message, 'message', contains('without declaring')),
        ),
        reason: 'the nosy node declared neither a read nor a write',
      );
      resources.endNode(1);
    });

    test('an optional read whose producer was culled answers null, not an error',
        () {
      // The distinction the first version of the rule got wrong. A node that
      // declared the read is entitled to ask, and when nothing surviving writes
      // the name the honest answer is "nothing" — that is what optionalReads is
      // for. Asking the node's declarations rather than its resolved bindings
      // is what tells the two apart, because a culled producer is precisely
      // what leaves the binding missing.
      final graph = compile(
        const <FrameGraphNode>[
          _Pass('atlas', keeps: <ResourceId>[atlas], isActive: false),
          _Pass('scene',
              optionalReads: <ResourceId>[atlas],
              writes: <ResourceId>[frame]),
        ],
        outputs: const <ResourceId>[frame],
      );
      final resources = resourcesFor(graph, _CountingSource());

      final scene = graph.order.indexWhere((node) => node.name == 'scene');
      resources.beginNode(scene);
      expect(resources.tryTexture(atlas), isNull);
      resources.endNode(scene);
    });
  });

  group('the pool, now that it can be run without a device', () {
    test('two targets of one shape are two textures', () {
      // The property everything above rests on. Interchangeable targets have
      // equal descriptions by definition, so a handle with value equality would
      // make the pool believe it had lent one texture twice.
      final pool = RenderTargetPool(_FakeAllocator());
      const spec = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );

      final first = pool.acquire(spec);
      final second = pool.acquire(spec);
      expect(identical(first, second), isFalse);
      expect(pool.lentCount, 2);
      expect(pool.createdCount, 2);
    });

    test('a released target is the next one lent out', () {
      final pool = RenderTargetPool(_FakeAllocator());
      const spec = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );

      final first = pool.acquire(spec);
      pool.release(first);
      expect(pool.acquire(spec), same(first));
      expect(pool.createdCount, 1);
    });

    test('a target goes back into the list its own description names', () {
      // The spec is read off the texture rather than remembered beside it, so
      // there is no second copy to disagree with the first. A mismatch here
      // hands the next acquirer the wrong size with nothing to say so.
      final pool = RenderTargetPool(_FakeAllocator());
      const big = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );
      const small = RenderTargetSpec(
        width: 320,
        height: 240,
        format: TextureFormat.r16g16b16a16Float,
      );

      pool.release(pool.acquire(big));
      final reused = pool.acquire(small);
      expect(reused.width, 320);
      expect(pool.createdCount, 2, reason: 'the 640x480 one does not fit');
    });

    test('handing back something it never lent is an error, not a shrug', () {
      final pool = RenderTargetPool(_FakeAllocator());
      expect(
        () => pool.release(fakeTexture('somebody else’s')),
        throwsStateError,
      );
    });

    test('a resize drops what is free and keeps what is out', () {
      final pool = RenderTargetPool(_FakeAllocator());
      const spec = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );

      final lent = pool.acquire(spec);
      pool.release(pool.acquire(spec));
      pool.trim();

      expect(pool.pooledCount, 0);
      expect(pool.lentCount, 1);
      // Still returnable: trimming forgets the free list, not the loans.
      pool.release(lent);
      expect(pool.pooledCount, 1);
    });
  });
}
