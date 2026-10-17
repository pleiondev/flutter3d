import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ProbeReading, PublishedState;

import 'flutter3d_view.dart' show Flutter3dEngine;

/// Builds a widget from what one probe of the simulation read: a gauge, a
/// chart's newest point, a number under the picture.
///
/// **Read from the published state, not from the world.** [published] is
/// what the simulation published, as a view saw it after its frame —
/// [Flutter3dEngine.published] — so the readout is the same whether the
/// simulation runs in the view's loop or in an isolate, and it never holds
/// anything the next step changes. [builder] is handed the reading of the
/// probe whose id is [probe] (`Probe.id` in the simulation), or null while
/// no reading of it has been published: before the first step, or in a
/// world without that probe.
///
/// ```dart
/// ProbeBuilder(
///   published: engine.published,
///   probe: 'tank.temperature',
///   builder: (context, reading) => Text(
///     reading == null ? '—' : '${reading.value.single.toStringAsFixed(1)} °C',
///   ),
/// )
/// ```
///
/// Built again once for every state the view publishes while it is shown.
final class ProbeBuilder extends StatelessWidget {
  const ProbeBuilder({
    super.key,
    required this.published,
    required this.probe,
    required this.builder,
  });

  /// The states to read: [Flutter3dEngine.published].
  final ValueListenable<PublishedState> published;

  /// The probe's id.
  final String probe;

  /// The widget for a reading, or for none yet.
  final Widget Function(BuildContext context, ProbeReading? reading) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PublishedState>(
    valueListenable: published,
    builder: (BuildContext context, PublishedState state, Widget? _) =>
        builder(context, state.probe(probe)),
  );
}
