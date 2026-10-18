/// A pipeline the backend could not build or link, and the device's record
/// of every one, so that a frame skips the draws that need it instead of
/// failing.
///
/// **Why a draw does not throw for it.** A pipeline is linked by a driver,
/// and a driver can refuse a pair of stages every other driver accepts. On
/// flutter_gpu the link is lazy: an OpenGL ES fallback links on the first
/// draw and refuses there, so the draw threw, the renderer rethrew, and one
/// shader on one phone failed every frame of the application, sixty times a
/// second, with the menu and the HUD behind it. One material missing from a
/// picture is a bug report; a black screen is a one-star review.
///
/// So a backend that cannot build a pipeline says so here, on
/// `GraphicsDevice.pipelineRefusals`, and skips the draw: the refusal is
/// reported once per pipeline, the backend drops what it built and tries
/// again at the next use, and after [PipelineRefusals.maxBuilds] failed
/// builds it stops trying and every draw with that pipeline is skipped. The
/// rest of the frame draws.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

import 'shader.dart';

/// Why a backend refused a pipeline — [PipelineRefusedException.reason].
///
/// **An open set**: a backend from outside this repository, or a later minor,
/// may name a reason this version does not, so a `switch` over it ends with a
/// wildcard. [byName] reads a reason back from a log.
final class PipelineRefusalReason {
  const PipelineRefusalReason._(this.name);

  /// A stage did not compile on this device: the bundle's code was refused
  /// by the driver's own compiler.
  static const PipelineRefusalReason compile = PipelineRefusalReason._(
    'compile',
  );

  /// The two stages compiled and would not link: a varying, an attribute or
  /// a uniform block the driver reads differently from the bundle, or a
  /// driver that refuses a link the others accept.
  static const PipelineRefusalReason link = PipelineRefusalReason._('link');

  /// A vertex attribute or an attachment format the backend cannot build a
  /// pipeline for.
  static const PipelineRefusalReason unsupportedFormat =
      PipelineRefusalReason._('unsupportedFormat');

  /// The device was lost while the pipeline was being built. Every handle is
  /// spent then (`GraphicsDevice.lost`); this says which build found out.
  static const PipelineRefusalReason deviceLost = PipelineRefusalReason._(
    'deviceLost',
  );

  /// Anything else the backend's API said no with.
  static const PipelineRefusalReason other = PipelineRefusalReason._('other');

  /// Every reason this version names.
  static const List<PipelineRefusalReason> values = <PipelineRefusalReason>[
    compile,
    link,
    unsupportedFormat,
    deviceLost,
    other,
  ];

  /// The reason called [name], or null when this version names none.
  static PipelineRefusalReason? byName(String name) {
    for (final reason in values) {
      if (reason.name == name) return reason;
    }
    return null;
  }

  /// The reason's stable name, as reports and logs spell it.
  final String name;

  @override
  String toString() => 'PipelineRefusalReason.$name';
}

/// A pipeline the backend could not build or link.
///
/// **Reported, not thrown, by every backend here.** It reaches the engine
/// through `GraphicsDevice.pipelineRefusals`, and from there a frame's
/// `FrameResult.pipelineRefusals`, once per pipeline. It is an exception
/// rather than a plain record so that a caller who builds a pipeline by hand
/// and wants to fail on a refusal can throw the very thing it was told.
final class PipelineRefusedException extends ResourceException {
  /// Creates the refusal of [pipeline] by [backend] for [reason], with the
  /// API's own words in `detail`.
  const PipelineRefusedException({
    required this.pipeline,
    required this.backend,
    required this.reason,
    this.detail = '',
    this.cause,
  });

  /// The pipeline's name, `vertex+fragment` as `PipelineHandle.name` spells
  /// it.
  final String pipeline;

  /// Who refused, as a person would name the backend.
  final String backend;

  /// Why, as a reason a caller can act on.
  final PipelineRefusalReason reason;

  /// What the backend's API said, in its own words: a driver's info log, a
  /// browser's validation message. Empty when it said nothing.
  final String detail;

  @override
  final Object? cause;

  @override
  String get message =>
      '$backend refused the pipeline $pipeline (${reason.name})'
      '${detail.isEmpty ? '' : ': $detail'}';

  @override
  String toString() => cause == null
      ? 'PipelineRefusedException: $message'
      : 'PipelineRefusedException: $message (caused by $cause)';
}

/// One device's record of the pipelines its backend could not build —
/// `GraphicsDevice.pipelineRefusals`.
///
/// **What a backend does with it.** When its API refuses a pipeline, at
/// `createPipeline` or at the first draw that links it, the backend calls
/// [report] and skips the draw. [report] answers whether another build may
/// be tried: while it is true the backend drops what it built and builds
/// again at the pipeline's next use; once it is false, [isRefused] is true
/// and every draw with the pipeline is skipped without a build.
///
/// **What the engine does with it.** The renderer [drain]s what was reported
/// at the end of each frame and puts it on the frame's result, so each
/// refusal is told once, on the frame that met it.
///
/// Keyed by the handle, not by its name: a pipeline relinked after a shader
/// reload is a new handle with a new count, which is what a fixed shader
/// deserves.
///
/// A backend's device keeps one, made with `PipelineRefusals()`.
final class PipelineRefusals {
  /// How many times a pipeline is built before it is left refused: the first
  /// build and two rebuilds.
  ///
  /// Small because a refusal is usually the same every time — a driver that
  /// will not link a pair today will not link it at the next frame — and
  /// every failed build costs a frame its time. More than one because the
  /// exceptions are real: a link that ran out of memory while a level loaded,
  /// a pipeline built in the middle of a context loss.
  static const int maxBuilds = 3;

  final Expando<_Refusals> _byPipeline = Expando<_Refusals>(
    'pipeline refusals',
  );
  final List<PipelineRefusedException> _untold = <PipelineRefusedException>[];

  /// Records that [pipeline] would not build, for [refusal]'s reason.
  ///
  /// The first refusal of a pipeline is kept for [drain]; a later one is
  /// counted and not told again. Answers whether the backend may build the
  /// pipeline once more at its next use — false from the [maxBuilds]th
  /// failure on, when the pipeline is left refused.
  ///
  /// [retry] false is for a refusal no rebuild can change — a vertex format
  /// the backend cannot read is the same format at the next frame — and
  /// leaves the pipeline refused at once, without builds that are known to
  /// fail.
  bool report(
    PipelineHandle pipeline,
    PipelineRefusedException refusal, {
    bool retry = true,
  }) {
    final refusals = _byPipeline[pipeline] ??= _Refusals(refusal);
    if (refusals.failures == 0) _untold.add(refusal);
    refusals.failures = retry ? refusals.failures + 1 : maxBuilds;
    return refusals.failures < maxBuilds;
  }

  /// Whether [pipeline] has failed [maxBuilds] builds and is not built
  /// again: every draw with it is skipped.
  bool isRefused(PipelineHandle pipeline) => failuresOf(pipeline) >= maxBuilds;

  /// How many builds of [pipeline] have failed; zero for one never refused.
  int failuresOf(PipelineHandle pipeline) =>
      _byPipeline[pipeline]?.failures ?? 0;

  /// The first refusal reported for [pipeline], or null when it was never
  /// refused.
  PipelineRefusedException? refusalOf(PipelineHandle pipeline) =>
      _byPipeline[pipeline]?.first;

  /// The refusals reported since the last call, one per pipeline, oldest
  /// first. Each is answered once.
  List<PipelineRefusedException> drain() {
    if (_untold.isEmpty) return const <PipelineRefusedException>[];
    final taken = List<PipelineRefusedException>.unmodifiable(_untold);
    _untold.clear();
    return taken;
  }
}

/// What [PipelineRefusals] keeps for one pipeline.
final class _Refusals {
  _Refusals(this.first);

  final PipelineRefusedException first;
  int failures = 0;
}
