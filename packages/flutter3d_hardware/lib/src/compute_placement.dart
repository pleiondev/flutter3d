/// Where a compute step runs, and the rule that decides it.
///
/// **Compute everywhere, by placement.** A frame's compute step has three
/// places it can run: on the device that draws the frame, on a compute-only
/// device beside it (`flutter3d_wgpu`'s sidecar over wgpu-native), or on the
/// CPU. Each is a [GraphicsDevice] with `DeviceFeature.compute`, so a step
/// is encoded the same way wherever it lands, and its kernel, written once
/// in the kernel language (`kernel <N>`; a material's `compute` block is
/// lowered to it), is loaded on whichever it is through the bundle's
/// kernel section.
///
/// **Decided here and nowhere else.** This file names the three, decides
/// between them, and is the only place that does: since 1.0.0-rc.1 the
/// engine above asks [FrameCompute] for a [ComputeSite] and is told a
/// device to encode on, never a placement, and nothing above this layer
/// may ask for one. Which devices a frame has is the backends' to say,
/// through the [DeviceRegistry] that opened its device. What a piece of
/// compute may say is what it requires (`ComputeRequirement`, in
/// [ComputeNeeds]), which the rule here meets — since 1.0.0-rc.1.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException;
import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'compute.dart';
import 'compute_requirement.dart';
import 'device_registry.dart';
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

  /// The work's own native code on the running processor's vector lanes
  /// (NEON, AVX2, AVX-512): an executor on the CPU beside the kernels, and
  /// no device — since 1.0.0-rc.1.
  ///
  /// Only work that brings such code reaches it, saying so with a
  /// [NativeLanes] to [FrameCompute.placeHosted], and the rule puts it
  /// there after the GPUs and ahead of the CPU executor. It is **refused
  /// under [ComputeRequirement.bitExact]**: the lanes add in another order
  /// than the kernel, so their bytes are not the CPU kernel's, only within
  /// the tolerance the work states ([NativeLanes.tolerance]) and holds its
  /// tests to. A step placed by [ComputeExecutors.place] never lands here.
  static const ComputePlacement nativeSimd = ComputePlacement._('nativeSimd');

  /// Every placement this version names. A later version appends. The
  /// first three, the devices, are also the order a step is placed in;
  /// [nativeSimd] is reached only by work with native lanes.
  static const List<ComputePlacement> values = <ComputePlacement>[
    device,
    sidecar,
    cpu,
    nativeSimd,
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

  /// A placement asked for is missing or has no compute. Nothing asks for
  /// one since 1.0.0-rc.1, so no refusal gives this reason; it stays so a
  /// `switch` written against 1.0.0-rc.1 compiles.
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

/// The typed refusal of a compute step nothing can run: why, and what each
/// executor said.
///
/// A [CapabilityException]: the machine, not the program, decides it. A
/// frame reports the step as unsupported and goes on; a caller that asked
/// [FrameCompute] directly catches this.
///
/// **Breaking in 1.0.0-rc.1: no `demand`.** A step no longer asks where
/// it runs, so there is no demand to report.
final class ComputePlacementException extends CapabilityException {
  const ComputePlacementException({
    required this.step,
    required this.reason,
    this.tried = const <String>[],
    this.cause,
  });

  /// The step, by its name in the frame.
  final String step;

  /// Why.
  final ComputeRefusalReason reason;

  /// One line per executor considered, in placement order: which it was
  /// and why it did not run the step.
  final List<String> tried;

  /// What the executor that refused the kernel threw, when one did.
  @override
  final Object? cause;

  @override
  String get message {
    final what = '"$step" has nowhere to run';
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
/// **The placement rule, written once.** A step runs on the first of
/// [ComputePlacement.values] whose executor has `DeviceFeature.compute`:
/// the drawing [device]'s own, then the [sidecar], then the [cpu].
///
/// **The hardware layer's and the backends'.** The engine above asks
/// [FrameCompute], which keeps one of these for the device a frame is drawn
/// on; a backend that adds a compute device names its placement here.
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

  /// Where the step called [step] runs: the first executor in placement
  /// order. [accepts] narrows the choice further (a step whose kernel one
  /// executor refused asks again without it) and is asked in placement
  /// order.
  ///
  /// Throws [ComputePlacementException] when nothing fits.
  ///
  /// **Breaking in 1.0.0-rc.1: no `demand`.** Where a step runs is this
  /// rule's to say, never the step's.
  ComputeExecutor place({
    required String step,
    bool Function(ComputeExecutor executor)? accepts,
  }) {
    final tried = <String>[];
    for (final placement in _devicePlacements) {
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
  /// only. Since 1.0.0-rc.1.
  static const List<ComputePlacement> aheadOfHost = <ComputePlacement>[
    ComputePlacement.device,
    ComputePlacement.sidecar,
  ];

  /// The placements that are devices, in the order a step is placed on
  /// them: what [place] tries. `nativeSimd` is no device.
  static const List<ComputePlacement> _devicePlacements = <ComputePlacement>[
    ComputePlacement.device,
    ComputePlacement.sidecar,
    ComputePlacement.cpu,
  ];

  /// Where the workload called [step] runs: an executor, or null for its
  /// own host implementation — since 1.0.0-rc.1.
  ///
  /// **The workload rule, written once.** The drawing device's compute,
  /// then the sidecar ([aheadOfHost]); then, when it [hasHost], its own
  /// host code, which was written for the CPU, ahead of the CPU executor,
  /// which interprets kernels written for a GPU; and the CPU executor only
  /// for a workload with nothing of its own there. A workload with host
  /// code is never put on a device that does its work on the CPU
  /// (`GraphicsDevice.isSoftware`) — a software rasteriser drawing the
  /// frame, say — for the same reason. [accepts] narrows the choice as it
  /// does for [place].
  ///
  /// Throws [ComputePlacementException] when nothing fits: a workload with
  /// no host code and no executor.
  ComputeExecutor? placeWorkload({
    required String step,
    required bool hasHost,
    bool Function(ComputeExecutor executor)? accepts,
  }) {
    for (final executor in workloadCandidates(hasHost: hasHost)) {
      if (executor.placement == ComputePlacement.cpu) break;
      if (accepts == null || accepts(executor)) return executor;
    }
    if (hasHost) return null;
    return place(step: step, accepts: accepts);
  }

  /// The executors [placeWorkload] may put a workload on, in the order it
  /// tries them: the GPUs ahead of the host, and, for a workload with no
  /// host code of its own, the CPU executor after them. What a step loads
  /// its kernels on before it asks the rule.
  List<ComputeExecutor> workloadCandidates({required bool hasHost}) =>
      <ComputeExecutor>[
        for (final placement in aheadOfHost)
          if (executorFor(placement) case final executor?
              when !hasHost || !executor.device.isSoftware)
            executor,
        if (!hasHost) ?executorFor(ComputePlacement.cpu),
      ];

  /// These executors less the sidecar: for work the frame draws from the
  /// same frame, which from a device beside it would arrive only through
  /// the host.
  ComputeExecutors get _withoutSidecar =>
      ComputeExecutors(device: device, cpu: cpu);
}

/// Where one piece of a frame's compute runs, as the hardware layer chose
/// it: the device its work is encoded on — since 1.0.0-rc.1.
///
/// **The outcome, never the choice.** The engine above records on
/// [device], binds the frame's own buffers there when [isOnFrameDevice],
/// and otherwise hands results across with a `SharedBuffer`; it never
/// learns which of the placements this is, and never asks for one.
@immutable
final class ComputeSite {
  const ComputeSite._(this._executor, this.frameDevice);

  final ComputeExecutor _executor;

  /// The device the frame is drawn on.
  final GraphicsDevice frameDevice;

  /// The device the work is encoded on: `device.beginComputePass()` is the
  /// encoder.
  GraphicsDevice get device => _executor.device;

  /// Whether that is the device drawing the frame, so the frame's own
  /// buffers and textures can be bound as they are.
  bool get isOnFrameDevice => identical(device, frameDevice);

  /// Opens a compute pass on [device], labelled [label]: the site's own
  /// encoder, which the caller binds, dispatches and submits — since
  /// 1.0.0-rc.1. **The one door to a compute pass above this layer**: a
  /// structure rule holds every `lib/` but the hardware layer's and the
  /// backends' to opening passes here, on a site the rule placed.
  ComputeEncoder beginPass({String? label}) =>
      device.beginComputePass(label: label);

  @override
  bool operator ==(Object other) =>
      other is ComputeSite &&
      other._executor == _executor &&
      identical(other.frameDevice, frameDevice);

  @override
  int get hashCode => Object.hash(_executor, identityHashCode(frameDevice));

  @override
  String toString() => 'ComputeSite(${device.backendName})';
}

/// Where [site] is, for a test checking the rule — exported from
/// `package:flutter3d_hardware/testing.dart` only.
ComputePlacement computePlacementOf(ComputeSite site) =>
    site._executor.placement;

/// One executor a piece of compute was not put on, and why — since
/// 1.0.0-rc.1.
///
/// **Named by its backend, never by its placement**: what a report or a log
/// shows, which says what happened without giving anything above this layer
/// a placement to choose by.
@immutable
final class PassedOver {
  const PassedOver._(this.backend, this.reason, {this.error});

  /// The device passed over, by its name for people
  /// (`GraphicsDevice.backendName`).
  final String backend;

  /// Why, in a sentence.
  final String reason;

  /// What loading the work there threw, when that is why; null for a device
  /// passed over for a requirement or a limit.
  final Object? error;

  /// Whether the work failed there, rather than not being asked of it.
  bool get didFail => error != null;

  @override
  String toString() => 'PassedOver($backend: $reason)';
}

/// A piece of compute that failed on a device and ran elsewhere — since
/// 1.0.0-rc.1: what [FrameCompute.fallbacks] reports, and the timeline
/// and the log say, each time one happens.
@immutable
final class ComputeFallback {
  const ComputeFallback._(this.step, this.passedOver, this.landedOn);

  /// The work, by its name in the frame.
  final String step;

  /// Every device passed over before it landed, in the order tried; at
  /// least one of them [PassedOver.didFail].
  final List<PassedOver> passedOver;

  /// Where it runs instead: a backend's name, or `its own host code`.
  final String landedOn;

  /// The fallback in a sentence, with each failure's reason.
  String get message {
    final failures = <String>[
      for (final p in passedOver)
        if (p.didFail) '${p.backend} failed it (${p.error})',
    ];
    return '"$step" fell back to $landedOn after ${failures.join('; ')}';
  }

  @override
  String toString() => 'ComputeFallback: $message';
}

/// Thrown instead of falling back, where falling back would hide a mistake:
/// a test, a debug build, a conformance run ([FrameCompute.strict]) —
/// since 1.0.0-rc.1.
///
/// An [Error], not an exception: a kernel that fails on a device with
/// compute and room for it is a bug in the kernel or the backend, which a
/// release build survives by running it elsewhere and a debug build stops
/// at, so it is seen.
final class ComputeFallbackError extends Error {
  ComputeFallbackError(this.fallback);

  /// What would have happened.
  final ComputeFallback fallback;

  @override
  String toString() =>
      'ComputeFallbackError: ${fallback.message}. A release build runs it '
      'there and reports it on FrameCompute.fallbacks; set '
      'FrameCompute.strict to false to do so here.';
}

/// What [FrameCompute.place] and [FrameCompute.placeHosted] answer: where
/// the work landed, what loading it there gave — its kernels' stages, say
/// — and every device passed over on the way.
final class PlacedWork<T> {
  const PlacedWork._(this.site, this.loaded, this.passedOver);

  /// Where it runs.
  final ComputeSite site;

  /// What the load gave on [site]'s device.
  final T loaded;

  /// The devices tried before [site], in order, each with why it was not
  /// used — since 1.0.0-rc.1.
  final List<PassedOver> passedOver;

  @override
  String toString() => 'PlacedWork($site)';
}

/// What [FrameCompute] found trying candidates in turn: what loaded where,
/// who was passed over, and the first error.
final class _Tried<T> {
  _Tried();
  final Map<ComputeExecutor, T> loaded = <ComputeExecutor, T>{};
  final List<PassedOver> passed = <PassedOver>[];
  Object? cause;
}

/// The compute a device's frames may use, and the hardware layer's rule for
/// where each piece of it runs — since 1.0.0-rc.1.
///
/// **Asked of the device, answered here.** [FrameCompute.of] is what frames
/// drawn on a device have: the executors the [DeviceRegistry] that opened
/// it offers (the device itself, the sidecar a backend added, the CPU
/// device), opened the first time they are needed; for a device opened
/// without one, the device alone. A renderer, a compute step, a workload
/// and a field ask it for a [ComputeSite] and are told the outcome, never
/// a placement, and none of them is told where to look for executors.
///
/// **It owns what it opened, and goes with the device** — since
/// 1.0.0-rc.1. The sidecar and the CPU device it opened, and every
/// pipeline kept in [cached], belong to the engine instance drawing on
/// [device]: they are disposed with [dispose], which the device's own
/// teardown (a loss on `GraphicsDevice.lost`, its own `destroyed` among
/// them) calls. Nothing in the layer keeps compute in a static cache.
final class FrameCompute {
  FrameCompute._(this.device, this._open);

  // Keyed by the device, weakly, and cleared by [dispose]: one instance's
  // own state hung on its device, not a cache shared between instances.
  static final Expando<FrameCompute> _of = Expando<FrameCompute>(
    'frame compute',
  );

  /// The compute of frames drawn on [device].
  static FrameCompute of(GraphicsDevice device) => _of[device] ??=
      FrameCompute._(device, () async => ComputeExecutors(device: device));

  /// The device the frames are drawn on.
  final GraphicsDevice device;

  final Future<ComputeExecutors> Function() _open;
  Future<ComputeExecutors>? _executors;
  StreamSubscription<DeviceLoss>? _watch;
  bool _disposed = false;

  /// Whether a piece of compute that fails on a device throws a
  /// [ComputeFallbackError] instead of running elsewhere — since
  /// 1.0.0-rc.1. True where assertions are on (a test, a debug build, a
  /// conformance run), false in a release build, which falls back and
  /// reports it on [fallbacks]. A failure the machine decides (a
  /// `CapabilityException`) falls back either way.
  bool strict = _assertionsOn();

  static bool _assertionsOn() {
    var on = false;
    assert(on = true, 'only ever true');
    return on;
  }

  final StreamController<ComputeFallback> _fallbacks =
      StreamController<ComputeFallback>.broadcast();

  /// Each piece of compute that failed on a device and runs elsewhere —
  /// since 1.0.0-rc.1. The same is written to the timeline
  /// (`compute fallback`) and the log (`flutter3d.compute`).
  Stream<ComputeFallback> get fallbacks => _fallbacks.stream;

  /// The executors, opened once, and let go with the device.
  Future<ComputeExecutors> _resolve() {
    if (_disposed) {
      throw StateError('the compute of a disposed device was asked for');
    }
    _watch ??= device.lost.listen((DeviceLoss loss) {
      if (!loss.isRecoverable && !loss.restored) {
        dispose(drawingDeviceGone: true);
      }
    });
    return _executors ??= _open();
  }

  /// The drawing device itself, as a site: where what the frame samples is
  /// held.
  ComputeSite get frame =>
      ComputeSite._(ComputeExecutor(ComputePlacement.device, device), device);

  /// Places the work called [step]: [load]s it — its kernels, say — on each
  /// device the rule offers in turn, stopping at the first that takes it,
  /// and answers that site with what [load] gave. A device whose [load]
  /// throws is passed over, its error kept as the refusal's cause, and the
  /// fallback reported ([strict], [fallbacks]). [besideFrame] false keeps
  /// the work off a compute-only device beside the frame's: for work the
  /// frame draws from in the same frame, which would reach it only through
  /// the host. A device that does not meet [needs] is passed over without
  /// being asked.
  ///
  /// Throws [ComputePlacementException] when nothing takes it.
  Future<PlacedWork<T>> place<T>(
    String step,
    Future<T> Function(GraphicsDevice device) load, {
    bool besideFrame = true,
    ComputeNeeds needs = ComputeNeeds.none,
  }) async {
    final all = await _resolve();
    final executors = besideFrame ? all : all._withoutSidecar;
    final tried = await _loadOnFirst(executors.available, load, needs);
    final ComputeExecutor chosen;
    try {
      chosen = executors.place(step: step, accepts: tried.loaded.containsKey);
    } on ComputePlacementException catch (refused, stack) {
      Error.throwWithStackTrace(_withCause(refused, tried), stack);
    }
    _reportFallback(step, tried.passed, chosen.device.backendName);
    return PlacedWork._(
      ComputeSite._(chosen, device),
      tried.loaded[chosen] as T,
      List<PassedOver>.unmodifiable(tried.passed),
    );
  }

  /// Places the work called [step] that has an implementation of its own on
  /// the host when [hasHost]: as [place], by the workload rule
  /// ([ComputeExecutors.placeWorkload]) — the GPUs first, then that host
  /// code, then the CPU executor for work with none. Null when its host
  /// code is to run it. [needs] as for [place]; the work's own host code
  /// meets every requirement, being the work's own reference.
  ///
  /// **Native lanes** ([lanes], `ComputePlacement.nativeSimd`): work that
  /// brings its own code on the processor's vector lanes, built here, says
  /// so, and the lanes take the place of host code — after the GPUs, ahead
  /// of the CPU executor — wherever [needs] admit them
  /// ([NativeLanes.admits]); under [ComputeRequirement.bitExact] they are
  /// refused and the work is placed as work without them. Null then means
  /// the lanes are to run it, or its host code where it has that too and
  /// the lanes were refused.
  ///
  /// Throws [ComputePlacementException] when nothing takes it.
  Future<PlacedWork<T>?> placeHosted<T>(
    String step,
    Future<T> Function(GraphicsDevice device) load, {
    required bool hasHost,
    NativeLanes? lanes,
    ComputeNeeds needs = ComputeNeeds.none,
  }) async {
    final executors = await _resolve();
    final onLanes = lanes != null && lanes.admits(needs);
    final ownCode = hasHost || onLanes;
    final tried = await _loadOnFirst(
      executors.workloadCandidates(hasHost: ownCode),
      load,
      needs,
    );
    final ComputeExecutor? chosen;
    try {
      chosen = executors.placeWorkload(
        step: step,
        hasHost: ownCode,
        accepts: tried.loaded.containsKey,
      );
    } on ComputePlacementException catch (refused, stack) {
      Error.throwWithStackTrace(_withCause(refused, tried), stack);
    }
    _reportFallback(
      step,
      tried.passed,
      chosen?.device.backendName ??
          (onLanes && !hasHost
              ? 'its native lanes (${ComputePlacement.nativeSimd.name})'
              : 'its own host code'),
    );
    if (chosen == null) return null;
    return PlacedWork._(
      ComputeSite._(chosen, device),
      tried.loaded[chosen] as T,
      List<PassedOver>.unmodifiable(tried.passed),
    );
  }

  /// Each of [candidates] in order, stopping at the first that loads: the
  /// rule then chooses that one, and asking the rest would only load the
  /// work again on devices nobody will use. A device that does not meet
  /// [needs] is passed over unasked.
  Future<_Tried<T>> _loadOnFirst<T>(
    List<ComputeExecutor> candidates,
    Future<T> Function(GraphicsDevice device) load,
    ComputeNeeds needs,
  ) async {
    final tried = _Tried<T>();
    for (final candidate in candidates) {
      final at = candidate.device;
      final unmet = needs.unmetOn(at);
      if (unmet != null) {
        tried.passed.add(PassedOver._(at.backendName, unmet));
        continue;
      }
      try {
        tried.loaded[candidate] = await load(at);
        break;
      } on Object catch (error) {
        tried.cause ??= error;
        tried.passed.add(
          PassedOver._(
            at.backendName,
            'the work failed there: $error',
            error: error,
          ),
        );
      }
    }
    return tried;
  }

  void _reportFallback(String step, List<PassedOver> passed, String landedOn) {
    if (!passed.any((PassedOver p) => p.didFail)) return;
    final fallback = ComputeFallback._(
      step,
      List<PassedOver>.unmodifiable(passed),
      landedOn,
    );
    final mistaken = passed.any(
      (PassedOver p) => p.didFail && p.error is! CapabilityException,
    );
    if (strict && mistaken) throw ComputeFallbackError(fallback);
    developer.Timeline.instantSync(
      'compute fallback',
      arguments: <String, Object>{'step': step, 'to': landedOn},
    );
    developer.log(fallback.message, name: 'flutter3d.compute', level: 900);
    if (!_fallbacks.isClosed) _fallbacks.add(fallback);
  }

  /// Where work called [step] runs that the frame draws from in the same
  /// frame and that only a device holding it can run — the engine's own
  /// stages a frame's draw reads, say: the drawing device, when it has
  /// compute and [takes] it, or null, at once — since 1.0.0-rc.1. No
  /// device beside the frame's is asked, and nothing is loaded, so there is
  /// nothing to wait for.
  ComputeSite? placeOnFrame(
    String step,
    bool Function(GraphicsDevice device) takes,
  ) {
    final executor = ComputeExecutors(
      device: device,
    ).executorFor(ComputePlacement.device);
    if (executor == null || !takes(device)) return null;
    return ComputeSite._(executor, device);
  }

  /// Places storage called [step] on the first device in placement order
  /// that [holds] it — a field's buffer a compute step steps, say.
  ///
  /// Throws [ComputePlacementException] when none does.
  Future<ComputeSite> placeStorage(
    String step,
    bool Function(GraphicsDevice device) holds,
  ) async {
    final executors = await _resolve();
    final chosen = executors.place(
      step: step,
      accepts: (ComputeExecutor e) => holds(e.device),
    );
    return ComputeSite._(chosen, device);
  }

  final Map<GraphicsDevice, Map<Object, _Kept>> _kept =
      Map<GraphicsDevice, Map<Object, _Kept>>.identity();

  /// What [make] gives on [on] for [key], made once for this engine
  /// instance and handed to every caller that asks with an equal [key]: a
  /// workload's kernels and pipelines, loaded once however many steps run
  /// it — since 1.0.0-rc.1.
  ///
  /// **Owned here, and let go with it**: [dispose] hands each value made to
  /// its [release]. A [make] that fails is forgotten, so the next asking
  /// tries again.
  ///
  /// **One key, one type**: a [key] already holding a value of another type
  /// than `T` is refused with a [StateError] naming both, rather than
  /// handing back a value the caller cannot use. Asking with a supertype of
  /// what is kept is answered.
  Future<T> cached<T>(
    GraphicsDevice on,
    Object key,
    Future<T> Function() make, {
    void Function(T value)? release,
  }) {
    if (_disposed) {
      throw StateError('the compute of a disposed device was asked for');
    }
    final kept = _kept.putIfAbsent(on, () => <Object, _Kept>{});
    switch (kept[key]) {
      case final _Kept<T> existing:
        return existing.value;
      case final existing?:
        throw StateError(
          'the compute cache key $key holds a ${existing.type}, and was '
          'asked for a $T: a key names one kind of value',
        );
      case null:
    }
    final made = make();
    kept[key] = _Kept<T>(made, release);
    made.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(kept[key]?.value, made)) kept.remove(key);
      },
    );
    return made;
  }

  /// How many values [cached] holds, across every device: for a test that
  /// holds the instance to what it let go.
  int get cachedCount =>
      _kept.values.fold(0, (int n, Map<Object, _Kept> m) => n + m.length);

  /// Lets go of everything this instance opened and kept: every value
  /// [cached] holds, through its release, and the sidecar and the CPU
  /// device opened for it, which are disposed — since 1.0.0-rc.1. The
  /// drawing [device] is not disposed: it is its owner's. Called by the
  /// device's own teardown, [drawingDeviceGone] then true so nothing is
  /// handed back to a device already gone; a second call does nothing.
  void dispose({bool drawingDeviceGone = false}) {
    if (_disposed) return;
    _disposed = true;
    unawaited(_watch?.cancel());
    if (identical(_of[device], this)) _of[device] = null;
    for (final MapEntry(key: on, value: kept) in _kept.entries) {
      if (drawingDeviceGone && identical(on, device)) continue;
      for (final k in kept.values) {
        k.release();
      }
    }
    _kept.clear();
    if (_executors case final executors?) {
      unawaited(
        executors.then<void>((ComputeExecutors e) {
          for (final other in <GraphicsDevice?>[e.sidecar, e.cpu]) {
            if (other != null && !identical(other, device)) other.dispose();
          }
        }, onError: (Object _) {}),
      );
    }
    unawaited(_fallbacks.close());
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  static ComputePlacementException _withCause(
    ComputePlacementException refused,
    _Tried<Object?> tried,
  ) => ComputePlacementException(
    step: refused.step,
    reason: refused.reason,
    tried: <String>[
      ...refused.tried,
      for (final p in tried.passed)
        if (!p.didFail) '${p.backend}: ${p.reason}',
    ],
    cause: tried.cause ?? refused.cause,
  );
}

/// One value [FrameCompute.cached] keeps, of the type it was made as, and
/// how it is let go.
final class _Kept<T> {
  _Kept(this.value, this._release);
  final Future<T> value;
  final void Function(T value)? _release;

  /// The type the value was made as, for the refusal of another.
  Type get type => T;

  /// Hands the value, once made, to its release; a failed make has none.
  void release() {
    if (_release case final release?) {
      value.then<void>(release, onError: (Object _) {});
    }
  }
}

/// Makes [open] the executors of frames drawn on [device], opened the first
/// time they are asked for: what [DeviceRegistry.open] and
/// [DeviceRegistry.adopt] do. Whatever the device had before is let go.
/// Not exported.
void attachCompute(
  GraphicsDevice device,
  Future<ComputeExecutors> Function() open,
) {
  FrameCompute._of[device]?.dispose();
  FrameCompute._of[device] = FrameCompute._(device, open);
}
