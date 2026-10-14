/// Where a compute step runs, and the rule that decides it.
///
/// **Compute everywhere, by placement.** A frame's compute step has three
/// places it can run: on the device that draws the frame, on a compute-only
/// device beside it (`flutter3d_wgpu`'s sidecar over wgpu-native), or on the
/// CPU. Each is a [GraphicsDevice] with `DeviceFeature.compute`, so a step
/// is encoded the same way wherever it lands, and its kernel, written once
/// in the kernel language (`kernel <N>`; a material's `compute` block is
/// lowered to it), is loaded on whichever it is through the bundle's
/// kernel section. This file names the three and decides between them; the
/// frame graph's `ComputeStep` asks it.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException;
import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'graphics_device.dart';

/// Where a compute step runs: on the device that draws the frame, on a
/// compute-only device beside it, or on the CPU.
///
/// **An open set** (S0): a class with constants, never an enum, so a
/// placement a later minor adds (a second queue on the same device, a
/// remote device) does not break a `switch` written against these three.
/// [name] is what a frame's report and a file write; [byName] reads it.
///
/// [values] is also the order a step is placed in when it demands nothing:
/// the device's own compute first, because nothing has to cross between
/// devices; then the sidecar, a GPU still; then the CPU, which every
/// machine has.
@immutable
final class ComputePlacement {
  const ComputePlacement._(this.name);

  /// The compute of the device the frame is drawn on: WebGPU's now, and
  /// Impeller's when flutter_gpu has compute (flutter/flutter#188474). The
  /// software rasteriser's, when it is the device that draws.
  static const ComputePlacement device = ComputePlacement._('device');

  /// A compute-only device beside the one that draws: `flutter3d_wgpu`'s,
  /// over wgpu-native, on every native target. A step's buffers and
  /// textures cross to the drawing device through `SharedBuffer` and
  /// `SharedTexture`.
  static const ComputePlacement sidecar = ComputePlacement._('sidecar');

  /// The kernel translated to Dart and run on the CPU: the software
  /// rasteriser's compute as a device of its own, which every machine has.
  static const ComputePlacement cpu = ComputePlacement._('cpu');

  /// Every placement this version names, in the order a step that demands
  /// none is placed. A later version appends.
  static const List<ComputePlacement> values = <ComputePlacement>[
    device,
    sidecar,
    cpu,
  ];

  /// The placement called [name], or null for one this version does not
  /// know.
  static ComputePlacement? byName(String name) {
    for (final placement in values) {
      if (placement.name == name) return placement;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'ComputePlacement.$name';
}

/// A device that runs compute, and where it stands relative to the frame.
@immutable
final class ComputeExecutor {
  const ComputeExecutor(this.placement, this.device);

  /// Where this is.
  final ComputePlacement placement;

  /// The device a step's kernels load on and its passes are encoded with:
  /// `device.beginComputePass()` is the executor's `ComputeEncoder`, which a
  /// render node or a plugin may take directly.
  final GraphicsDevice device;

  @override
  bool operator ==(Object other) =>
      other is ComputeExecutor &&
      other.placement == placement &&
      identical(other.device, device);

  @override
  int get hashCode => Object.hash(placement, identityHashCode(device));

  @override
  String toString() =>
      'ComputeExecutor(${placement.name}, ${device.backendName})';
}

/// Why a compute step could not be placed.
///
/// **An open set**, as [ComputePlacement] is.
@immutable
final class ComputeRefusalReason {
  const ComputeRefusalReason._(this.name);

  /// No executor of the frame has compute at all: the device draws without
  /// it, and neither a sidecar nor a CPU executor was given.
  static const ComputeRefusalReason noExecutor = ComputeRefusalReason._(
    'noExecutor',
  );

  /// The step demanded a placement, and the executor for it is missing or
  /// has no compute.
  static const ComputeRefusalReason placementUnavailable =
      ComputeRefusalReason._('placementUnavailable');

  /// Every executor that has compute refused the step's kernel: its bundle
  /// did not load there.
  static const ComputeRefusalReason kernelRefused = ComputeRefusalReason._(
    'kernelRefused',
  );

  /// Nothing has placed the step yet: a frame-graph step is placed before
  /// the frame (`ComputeStep.prepare`), because loading a kernel waits on
  /// the device and a frame does not.
  static const ComputeRefusalReason notPlaced = ComputeRefusalReason._(
    'notPlaced',
  );

  /// Every reason this version names. A later version appends.
  static const List<ComputeRefusalReason> values = <ComputeRefusalReason>[
    noExecutor,
    placementUnavailable,
    kernelRefused,
    notPlaced,
  ];

  /// The reason called [name], or null for one this version does not know.
  static ComputeRefusalReason? byName(String name) {
    for (final reason in values) {
      if (reason.name == name) return reason;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'ComputeRefusalReason.$name';
}

/// The typed refusal of a compute step nothing can run: what it demanded,
/// why, and what each executor said.
///
/// A [CapabilityException]: the machine, not the program, decides it. A
/// frame reports the step as unsupported and goes on; a caller that asked
/// [ComputeExecutors.place] directly catches this.
final class ComputePlacementException extends CapabilityException {
  const ComputePlacementException({
    required this.step,
    required this.reason,
    this.demand,
    this.tried = const <String>[],
    this.cause,
  });

  /// The step, by its name in the frame.
  final String step;

  /// Why.
  final ComputeRefusalReason reason;

  /// The placement the step demanded, or null when it demanded none.
  final ComputePlacement? demand;

  /// One line per executor considered, in placement order: which it was
  /// and why it did not run the step.
  final List<String> tried;

  /// What the executor that refused the kernel threw, when one did.
  @override
  final Object? cause;

  @override
  String get message {
    final what = switch (demand) {
      null => '"$step" has nowhere to run',
      final demanded =>
        '"$step" demands ${demanded.name} compute and cannot have it',
    };
    final why = switch (reason) {
      ComputeRefusalReason.noExecutor =>
        'no executor of this frame has compute',
      ComputeRefusalReason.placementUnavailable =>
        'that executor is missing or has no compute',
      ComputeRefusalReason.kernelRefused => 'its kernel did not load there',
      ComputeRefusalReason.notPlaced => 'nothing has placed it yet',
      _ => reason.name,
    };
    return '$what: $why${tried.isEmpty ? '' : ' (${tried.join('; ')})'}';
  }

  @override
  String toString() => 'ComputePlacementException: $message';
}

/// The executors one frame may place compute steps on, and the order it
/// tries them in.
///
/// **The placement rule, written once.** A step that demands nothing runs
/// on the first of [ComputePlacement.values] whose executor has
/// `DeviceFeature.compute`: the drawing [device]'s own, then the [sidecar],
/// then the [cpu]. One that demands a placement runs there or is refused
/// with [ComputePlacementException], never quietly moved.
final class ComputeExecutors {
  /// The executors of a frame drawn on [device], with a [sidecar] and a
  /// [cpu] device where the application has them.
  ComputeExecutors({required this.device, this.sidecar, this.cpu});

  /// The device the frame is drawn on.
  final GraphicsDevice device;

  /// A compute-only device beside it, or null.
  final GraphicsDevice? sidecar;

  /// A device that runs kernels on the CPU, or null.
  final GraphicsDevice? cpu;

  GraphicsDevice? _deviceFor(ComputePlacement placement) => switch (placement) {
    ComputePlacement.device => device,
    ComputePlacement.sidecar => sidecar,
    ComputePlacement.cpu => cpu,
    // A placement a later version names has no device in this one.
    _ => null,
  };

  /// The executor for [placement], or null when there is none with
  /// compute.
  ComputeExecutor? executorFor(ComputePlacement placement) {
    final at = _deviceFor(placement);
    if (at == null || !at.features.has(DeviceFeature.compute)) return null;
    return ComputeExecutor(placement, at);
  }

  /// Every executor with compute, in placement order.
  List<ComputeExecutor> get available => <ComputeExecutor>[
    for (final placement in ComputePlacement.values) ?executorFor(placement),
  ];

  /// Why [placement] has no executor, as one line of a refusal.
  String _why(ComputePlacement placement) => switch (_deviceFor(placement)) {
    null => '${placement.name}: none given',
    final at => '${placement.name}: ${at.backendName} has no compute',
  };

  /// Where the step called [step] runs: at [demand] when it names one,
  /// otherwise the first executor in placement order. [accepts] narrows the
  /// choice further (a step whose kernel one executor refused asks again
  /// without it) and is asked in placement order.
  ///
  /// Throws [ComputePlacementException] when nothing fits.
  ComputeExecutor place({
    required String step,
    ComputePlacement? demand,
    bool Function(ComputeExecutor executor)? accepts,
  }) {
    if (demand != null) {
      final executor = executorFor(demand);
      if (executor != null && (accepts == null || accepts(executor))) {
        return executor;
      }
      throw ComputePlacementException(
        step: step,
        demand: demand,
        reason: executor == null
            ? ComputeRefusalReason.placementUnavailable
            : ComputeRefusalReason.kernelRefused,
        tried: <String>[
          if (executor == null)
            _why(demand)
          else
            '${demand.name}: ${executor.device.backendName} refused it',
        ],
      );
    }
    final tried = <String>[];
    for (final placement in ComputePlacement.values) {
      final executor = executorFor(placement);
      if (executor == null) {
        tried.add(_why(placement));
      } else if (accepts == null || accepts(executor)) {
        return executor;
      } else {
        tried.add(
          '${placement.name}: ${executor.device.backendName} refused it',
        );
      }
    }
    throw ComputePlacementException(
      step: step,
      reason: available.isEmpty
          ? ComputeRefusalReason.noExecutor
          : ComputeRefusalReason.kernelRefused,
      tried: tried,
    );
  }

  /// The placements a `ComputeWorkload` with an implementation of its own
  /// on the host is tried at before that implementation, in order: the GPUs
  /// only. Since 1.0.0-rc.1+1.
  static const List<ComputePlacement> aheadOfHost = <ComputePlacement>[
    ComputePlacement.device,
    ComputePlacement.sidecar,
  ];

  /// Where the workload called [step] runs: an executor, or null for its
  /// own host implementation — since 1.0.0-rc.1+1.
  ///
  /// **The workload rule, written once.** At its [demand] when it names
  /// one, as [place]. Otherwise the drawing device's compute, then the
  /// sidecar ([aheadOfHost]); then, when it [hasHost], its own host code,
  /// which was written for the CPU, ahead of the CPU executor, which
  /// interprets kernels written for a GPU; and the CPU executor only for a
  /// workload with nothing of its own there. [accepts] narrows the choice
  /// as it does for [place].
  ///
  /// Throws [ComputePlacementException] when nothing fits: a demand that
  /// cannot be met, or a workload with no host code and no executor.
  ComputeExecutor? placeWorkload({
    required String step,
    required bool hasHost,
    ComputePlacement? demand,
    bool Function(ComputeExecutor executor)? accepts,
  }) {
    if (demand != null) {
      return place(step: step, demand: demand, accepts: accepts);
    }
    for (final placement in aheadOfHost) {
      final executor = executorFor(placement);
      if (executor != null && (accepts == null || accepts(executor))) {
        return executor;
      }
    }
    if (hasHost) return null;
    return place(step: step, accepts: accepts);
  }
}
