/// The two reasons a pass is left out that are about the pass itself: it is
/// still loading (`PassSkip.pending`), or it threw (`PassSkip.failed`); and
/// the placer that answers `FrameGraphBuilder.place`.
///
///     dart test test/engine/frame_graph_pending_test.dart
///
/// Mutation: treat a placer's `FramePlacer.pending` as a placement, and the
/// loading node runs with no site; drop `isReady` from the compile's key,
/// and a graph compiled while a node loaded keeps it out after it is ready.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

const _particles = ResourceId('particles');
const _frame = ResourceId('frame');

final class _Producer extends FrameGraphNode {
  _Producer({this.request});

  final PlacementRequest? request;
  bool ready = true;

  @override
  String get name => 'producer';

  @override
  bool get isReady => ready;

  @override
  void setup(FrameGraphBuilder builder) {
    super.setup(builder);
    builder.write(_particles);
    if (request case final request?) builder.place(request);
  }
}

final class _Draw extends FrameGraphNode {
  const _Draw();

  @override
  String get name => 'draw';

  @override
  List<ResourceId> get reads => const <ResourceId>[_particles];

  @override
  List<ResourceId> get writes => const <ResourceId>[_frame];
}

final class _Ask extends PlacementRequest {
  const _Ask();

  @override
  String get name => 'ask';
}

/// Answers whatever it is told to.
final class _Placer extends FramePlacer {
  _Placer(this.answer);

  final Object? answer;
  int asked = 0;

  @override
  Object? place(FramePlacementContext context) {
    asked++;
    return answer;
  }
}

FrameGraph _graph(_Producer producer) => FrameGraph()
  ..addNode(producer)
  ..addNode(const _Draw());

void main() {
  test('a node that is not ready is pending, and what reads it starves', () {
    final producer = _Producer()..ready = false;
    final graph = _graph(producer);
    final waiting = graph.compile(outputs: const <ResourceId>[_frame]);
    expect(waiting.skipReason('producer'), PassSkip.pending);
    expect(waiting.skipReason('draw'), PassSkip.starved);

    producer.ready = true;
    final ready = graph.compile(outputs: const <ResourceId>[_frame]);
    expect(ready.skipReason('producer'), isNull);
    expect(ready.order.map((n) => n.name), <String>['producer', 'draw']);
  });

  test('a placer that is still working answers pending; one that placed '
      'hands the placement on; none is unsupported', () {
    final graph = _graph(_Producer(request: const _Ask()));
    expect(
      graph
          .compile(
            outputs: const <ResourceId>[_frame],
            placer: _Placer(FramePlacer.pending),
          )
          .skipReason('producer'),
      PassSkip.pending,
    );
    final placed = graph.compile(
      outputs: const <ResourceId>[_frame],
      placer: _Placer('the cpu'),
    );
    expect(placed.skipReason('producer'), isNull);
    expect(placed.placementOf<String>('producer'), 'the cpu');
    expect(
      graph
          .compile(outputs: const <ResourceId>[_frame], placer: _Placer(null))
          .skipReason('producer'),
      PassSkip.unsupported,
    );
    // And with no placer at all, nothing is placed.
    expect(
      graph.compile(outputs: const <ResourceId>[_frame]).skipReason('producer'),
      PassSkip.unsupported,
    );
  });

  test('a failed node is left out as failed, ahead of every other reason', () {
    final producer = _Producer()..ready = false;
    final graph = _graph(producer);
    final compiled = graph.compile(
      outputs: const <ResourceId>[_frame],
      failed: const <String>{'producer'},
    );
    expect(compiled.skipReason('producer'), PassSkip.failed);
    expect(compiled.skipReason('draw'), PassSkip.starved);
    // A failed node is not asked where it runs.
    final placer = _Placer('the cpu');
    _graph(_Producer(request: const _Ask())).compile(
      outputs: const <ResourceId>[_frame],
      failed: const <String>{'producer'},
      placer: placer,
    );
    expect(placer.asked, 0);
  });

  test('the two reasons are named and listed', () {
    expect(
      PassSkip.values,
      containsAll(<PassSkip>[PassSkip.pending, PassSkip.failed]),
    );
    expect(PassSkip.byName('pending'), PassSkip.pending);
    expect(PassSkip.byName('failed'), PassSkip.failed);
    expect(PassSkip.byName('later'), isNull);
  });
}
