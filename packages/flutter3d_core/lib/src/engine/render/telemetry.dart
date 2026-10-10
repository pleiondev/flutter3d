/// How much of a frame the renderer measures — `RenderSettings.telemetry`.
library;

/// How much of a frame the renderer measures, and what it costs to.
///
/// **Measuring is not free.** A clock started and read around every node of
/// the graph, a timeline span opened and closed, and the GPU's timestamps
/// asked for are a few microseconds each on a phone, every frame, for
/// numbers nobody reads in a shipped game. Each level keeps what the one
/// below it keeps and adds to it:
///
///  * [off]: the frame's totals (`FrameResult.drawCalls` and the rest) and
///    nothing per node or per resource. `FrameResult.passes` and
///    `FrameResult.resources` are empty.
///  * [counters]: one `FramePass` per node that ran, with its draw calls,
///    triangles and pipeline switches, and one `FrameResourceUse` per
///    resource the frame touched. No clock is read: a pass's `micros` is
///    nought and its `gpuMicros` null.
///  * [timings]: the counters, plus each node's CPU time and the GPU's where
///    the device measures it, and a `Timeline` span per node for the DevTools
///    timeline. The default, since it is what every frame reported before
///    there was a choice; a game that has profiled sets [counters] or [off].
///
/// A `final class` with const instances rather than an enum, so a level
/// added later breaks no `switch` outside; [name] is its wire name.
final class TelemetryLevel {
  const TelemetryLevel._(this.name, this._rank);

  /// The stable name, as a file or a tool writes it.
  final String name;

  final int _rank;

  /// The frame's totals, nothing per node.
  static const TelemetryLevel off = TelemetryLevel._('off', 0);

  /// Per node and per resource, counted but not timed.
  static const TelemetryLevel counters = TelemetryLevel._('counters', 1);

  /// Per node and per resource, counted and timed.
  static const TelemetryLevel timings = TelemetryLevel._('timings', 2);

  /// Every level, least first.
  static const List<TelemetryLevel> values = <TelemetryLevel>[
    off,
    counters,
    timings,
  ];

  /// Whether a frame keeps a record per node and per resource.
  bool get recordsNodes => _rank >= counters._rank;

  /// Whether a frame reads clocks around its nodes and asks the GPU for its
  /// timings.
  bool get recordsTimes => _rank >= timings._rank;

  @override
  String toString() => 'TelemetryLevel.$name';
}
