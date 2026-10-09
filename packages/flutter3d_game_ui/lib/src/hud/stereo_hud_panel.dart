import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A HUD built once and redrawn from a [ValueListenable], for a surface in
/// front of a stereo camera.
///
/// **Why it listens instead of being rebuilt.** A `WidgetSurface`'s child is
/// fixed when the surface is made, so the tree on it is built once and has
/// to tick itself from then on. The flat screen's overlay is rebuilt by its
/// parent's `setState`; this one is the same HUD, handed the same readout,
/// redrawn through [ValueListenableBuilder] each time [reading] changes.
///
/// [reading] holds null until there is something to show, and the panel is
/// empty until then.
final class StereoHudPanel<T extends Object> extends StatelessWidget {
  const StereoHudPanel({
    super.key,
    required this.reading,
    required this.builder,
  });

  final ValueListenable<T?> reading;

  /// The HUD for one reading. Anything else it shows — a message beside the
  /// numbers — is read here, fresh each time [reading] notifies, rather than
  /// through a second listenable that would change at the same moment.
  final Widget Function(BuildContext context, T reading) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T?>(
    valueListenable: reading,
    builder: (BuildContext context, T? value, Widget? _) =>
        value == null ? const SizedBox.shrink() : builder(context, value),
  );
}
