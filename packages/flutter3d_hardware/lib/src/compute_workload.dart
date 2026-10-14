/// A simulation's compute, handed to the engine as kernels and buffers
/// rather than as code that knows where it runs — 1.0.0-rc.1+1.
///
/// **The simulation says what, the engine says where.** A physics core that
/// wants its step on a GPU does not open a device, test which backend it was
/// given, or keep an `if (webgpu)` of its own. It describes the step once as
/// a [ComputeWorkload]: its kernels in the kernel language (`kernel 1`, the
/// language `flutter3d_shaders` reads), the buffers they bind, and what one
/// frame records in terms of those names. The engine places it by
/// [ComputeExecutors.placeWorkload] — the drawing device's compute, then a
/// sidecar beside it, then the workload's own host implementation where it
/// has one, then the CPU executor that runs the kernels translated to Dart —
/// allocates the buffers there and tells the workload where it landed
/// ([ComputeWorkload.placed]). The workload only ever learns the outcome.
///
/// **Its own host implementation** ([ComputeWorkload.hasHost]) is the
/// simulation's CPU code for the same step, a C core's say. The placement
/// rule puts it ahead of the CPU executor because it was written for the
/// CPU, while the CPU executor interprets kernels written for a GPU; a
/// workload without one falls through to the CPU executor as any compute
/// step does.
///
/// **Drawn without a trip through the host.** A buffer declared
/// [WorkloadBuffer.drawn] is one the frame draws as vertices: on the drawing
/// device it is the very buffer the kernels wrote
/// (`StorageBuffer.asVertices`); from a sidecar or the CPU executor the
/// engine hands it across with a `SharedBuffer` after each frame's work.
/// [WorkloadBinding.vertices] is the drawing device's view either way.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'compute_placement.dart';
import 'geometry_buffer.dart';

/// One buffer a [ComputeWorkload]'s kernels bind, by the name its kernels
/// declare it under.
@immutable
final class WorkloadBuffer {
  /// A buffer called [name], [lengthInBytes] long, zeroed when made.
  /// [drawn] makes it one the frame draws as vertices; [readable] one the
  /// workload may read back to the host ([WorkloadRecorder.readBack]).
  const WorkloadBuffer(
    this.name,
    this.lengthInBytes, {
    this.drawn = false,
    this.readable = false,
  });

  /// What the kernels and the recorder call it.
  final String name;

  /// How long it is, in bytes: a whole number of four.
  final int lengthInBytes;

  /// Whether the frame draws it as a vertex buffer.
  final bool drawn;

  /// Whether the host may read it back.
  final bool readable;

  @override
  bool operator ==(Object other) =>
      other is WorkloadBuffer &&
      other.name == name &&
      other.lengthInBytes == lengthInBytes &&
      other.drawn == drawn &&
      other.readable == readable;

  @override
  int get hashCode => Object.hash(name, lengthInBytes, drawn, readable);

  @override
  String toString() =>
      'WorkloadBuffer($name, $lengthInBytes bytes'
      '${drawn ? ', drawn' : ''}${readable ? ', readable' : ''})';
}

/// Where a [ComputeWorkload] was placed, as the engine tells it: an
/// executor's placement, or its own host implementation; and the drawing
/// device's view of each buffer it declared [WorkloadBuffer.drawn].
///
/// **The outcome, never the choice.** A workload reads this to know whether
/// its host code steps it ([isOnHost]) and what to draw from; which executor
/// was tried and why is the engine's.
final class WorkloadBinding {
  /// On [placement]'s executor, its drawn buffers as [drawn] has them.
  WorkloadBinding.placed(
    ComputePlacement this.placement, {
    Map<String, GeometryBuffer> drawn = const <String, GeometryBuffer>{},
  }) : _drawn = Map<String, GeometryBuffer>.unmodifiable(drawn);

  /// On the workload's own host implementation: no executor, nothing drawn
  /// from its buffers.
  WorkloadBinding.host()
    : placement = null,
      _drawn = const <String, GeometryBuffer>{};

  /// The placement of the executor it runs on, or null on the host.
  final ComputePlacement? placement;

  final Map<String, GeometryBuffer> _drawn;

  /// Whether its own host implementation steps it.
  bool get isOnHost => placement == null;

  /// The drawing device's vertex buffer over the drawn buffer [name], or
  /// null on the host and for a buffer not declared drawn.
  GeometryBuffer? vertices(String name) => _drawn[name];

  @override
  String toString() =>
      'WorkloadBinding(${placement?.name ?? 'host'}'
      '${_drawn.isEmpty ? '' : ', drawn: ${_drawn.keys.join(', ')}'})';
}

/// What a [ComputeWorkload] records one frame's work with, on whichever
/// executor it was placed: writes, dispatches and reads back, each by name.
///
/// **Every write lands before the frame's first dispatch.** A GPU queue
/// takes a write ahead of the pass it is recorded beside, so a workload
/// writes what the frame needs first and then dispatches; the CPU executor
/// keeps the same order.
///
/// **Implemented by the engine**, and grows by members with a default body.
abstract base class WorkloadRecorder {
  /// A recorder; the engine makes one a frame.
  WorkloadRecorder();

  /// Where this frame's work runs.
  ComputePlacement get placement;

  /// Writes [bytes] into the buffer [buffer] at [offsetInBytes], ahead of
  /// this frame's dispatches.
  void write(String buffer, ByteData bytes, {int offsetInBytes = 0});

  /// Runs the kernel called [kernel] over `x × y × z` workgroups, each of
  /// its buffer bindings bound to the workload buffer of the same name.
  /// Dispatches run in the order they are recorded, each after the last
  /// has written everything it writes.
  void dispatch(String kernel, int x, {int y = 1, int z = 1});

  /// Asks for the buffer [buffer], declared [WorkloadBuffer.readable], as
  /// it stands once this frame's dispatches are done: [done] is called
  /// with its bytes, later, on the host's own turn. False, and [done] never
  /// called, while a read of it asked for earlier has not arrived yet: one
  /// read a buffer is in flight at a time.
  bool readBack(String buffer, void Function(ByteData bytes) done);
}

/// A simulation's step as kernels and buffers, for the engine to place and
/// run — see the library comment.
///
/// **Implementable outside this package, and stays so through 1.x**: a
/// member added later arrives with a default body.
abstract base class ComputeWorkload {
  /// A workload; a subclass says what it computes.
  ComputeWorkload();

  /// What a frame and a refusal call it.
  String get name;

  /// The kernel language source of every kernel [record] dispatches, one
  /// `compute` block each.
  String get kernelSource;

  /// The buffers its kernels bind, allocated on the executor it is placed
  /// on, zeroed.
  List<WorkloadBuffer> get buffers;

  /// Whether it has an implementation of its own on the host, which the
  /// placement rule prefers to the CPU executor
  /// ([ComputeExecutors.placeWorkload]).
  bool get hasHost => false;

  /// The placement it must run at, or null for wherever the rule puts it.
  /// A demand nothing meets is refused, never moved, as a compute step's
  /// is; most workloads demand nothing.
  ComputePlacement? get demand => null;

  /// Told where it runs, before the first [record] there; told again with
  /// [WorkloadBinding.host] when it falls back. The buffers are zeroed at
  /// the first [record] after a placement: a workload whose state lives on
  /// the host writes it then.
  void placed(WorkloadBinding binding) {}

  /// Records one frame's work. Called once a frame while placed on an
  /// executor; never on the host.
  void record(WorkloadRecorder recorder);

  /// Its buffers were let go, the step taken out of the frame: whatever
  /// the host keeps is its own again.
  void released() {}
}
