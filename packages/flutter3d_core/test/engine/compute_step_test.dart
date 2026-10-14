// A compute step in the frame graph: unplaced it is not in the frame, a
// step nothing can run is refused by type and reported as unsupported, and
// what only read its output is culled with it.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';

const _particles = ResourceId('particles');
const _frame = ResourceId('frame');

final class _Step extends ComputeStep {
  @override
  String get name => 'particles';

  @override
  List<ResourceId> get writes => const <ResourceId>[_particles];

  @override
  List<ComputeKernel> get kernels => ComputeKernel.parseAll('''
compute Step {
  buffer p: f32[] read_write;
  kernel { }
}
''');

  @override
  void record(ComputeContext context) {}
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

CompiledFrameGraph _frameWith(ComputeStep step) =>
    (FrameGraph()
          ..addNode(step)
          ..addNode(const _Draw()))
        .compile(outputs: const <ResourceId>[_frame]);

void main() {
  test('a step nothing placed is not in the frame, and says so', () {
    // Mutation: answer isSupported true before a placement, and the frame
    // runs a step with no executor and throws from execute.
    final step = _Step();
    expect(step.isSupported, isFalse);
    expect(step.refusal!.reason, ComputeRefusalReason.notPlaced);
    expect(step.refusal!.step, 'particles');
    final frame = _frameWith(step);
    expect(frame.skipReason('particles'), PassSkip.unsupported);
    // What only read its output starves with it.
    expect(frame.skipReason('draw'), PassSkip.starved);
  });

  test('a step with no executor anywhere is refused by type', () async {
    // Mutation: place it on the drawing device regardless, and a device
    // without compute is handed a compute pass.
    final step = _Step();
    final refused = await step.prepare(FakeBackend());
    expect(refused!.reason, ComputeRefusalReason.noExecutor);
    expect(step.refusal, same(refused));
    expect(step.site, isNull);
    expect(_frameWith(step).skipReason('particles'), PassSkip.unsupported);
  });

  test('compute goes before the opaque scene unless the step says', () {
    expect(_Step().defaultAnchor, RenderAnchor.beforeOpaque);
  });
}
