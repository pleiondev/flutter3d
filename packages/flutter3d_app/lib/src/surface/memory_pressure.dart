/// Giving pooled render targets back when the platform asks — `gfx-71n`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';

/// Wraps [child] and gives [renderer]'s pooled targets back when the platform
/// warns about memory.
///
/// **What the pool does without this is settle at a high-water mark and stay
/// there.** It keeps one texture of every attachment shape any frame has ever
/// needed: turn bloom on once and its five levels are held for the rest of the
/// session, take one screenshot at twice the window size and that pair is held
/// too. On a desktop that is a megabyte nobody notices. On a phone the process
/// is killed, which is a crash class rather than a slow frame — and it arrives
/// as a report with no Dart stack, because the operating system did it.
///
/// **Wired to the platform's own warning rather than to a budget.** A budget
/// means this package deciding how many megabytes a game may hold on a device
/// it knows nothing about, and being wrong in both directions.
/// `didHaveMemoryPressure` is the one signal that is actually about this
/// device, at this moment, with these other applications running.
///
/// What the next frame pays is one round of allocation, once. What is lent out
/// is left alone, so a frame in flight keeps the targets it is drawing into.
///
/// ```dart
/// MemoryPressureRelease(
///   renderer: renderer,
///   child: SceneSurface(renderer: renderer, /* … */),
/// )
/// ```
class MemoryPressureRelease extends StatefulWidget {
  const MemoryPressureRelease({
    required this.renderer,
    required this.child,
    this.onReleased,
    super.key,
  });

  final Renderer renderer;
  final Widget child;

  /// Called after the release, for an application that logs it.
  ///
  /// Here because a memory warning is the sort of thing a player reports as
  /// "it got slow for a second" and a developer never sees otherwise.
  final void Function()? onReleased;

  @override
  State<MemoryPressureRelease> createState() => _MemoryPressureReleaseState();
}

class _MemoryPressureReleaseState extends State<MemoryPressureRelease>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    widget.renderer.releaseTransientTargets();
    widget.onReleased?.call();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
