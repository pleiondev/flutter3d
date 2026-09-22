/// The viewport a page's scene is drawn in, and the panel beside it.
///
/// **The host of every page.** It opens the run on the app's device, drives the
/// frame loop, turns the camera as the pointer drags and reports what the
/// frame declined, so a page has none of that in it. On the web the frame is a
/// fixed 1280 by 720 that the browser stretches, because a WebGL canvas resets
/// when it is resized; the stage letterboxes it to 16:9 rather than draw at a
/// size the device does not have.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter3d/flutter3d.dart' show FrameResult;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/capability_report.dart';
import 'package:flutter3d_showcase/src/demo/controls_panel.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter3d_showcase/src/demo/device_holder.dart';

class DemoStage extends StatefulWidget {
  const DemoStage({super.key, required this.build, required this.declined});

  final DemoBuilder build;

  /// What the last frame declined. Set from here, read by the page's chrome.
  final ValueNotifier<List<String>> declined;

  @override
  State<DemoStage> createState() => _DemoStageState();
}

class _DemoStageState extends State<DemoStage>
    with SingleTickerProviderStateMixin {
  final FrameClock _clock = FrameClock();
  late final Ticker _ticker = createTicker(_tick);
  DemoRun? _run;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start(DeviceScope.of(context));
  }

  Future<void> _start(DeviceHolder holder) async {
    try {
      final run = await DemoRun.start(await holder.device, widget.build());
      if (!mounted) {
        run.dispose();
        return;
      }
      setState(() => _run = run);
      _clock.reset();
      _ticker.start();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _tick(Duration _) {
    final DemoRun? run = _run;
    if (run == null) return;
    // A frame that took long (a tab left in the background) is played as a
    // tenth of a second: a page that steps by `dt` is then never flung a
    // minute's worth in one go.
    run.update(math.min(_clock.tick(), 0.1));
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _run?.dispose();
    super.dispose();
  }

  /// Passes on what the frame declined, once per change and after the frame,
  /// since the chrome that shows it is built in the same pass.
  void _report(FrameResult frame) {
    final List<String> declined = declinedBy(frame);
    if (listEquals(declined, widget.declined.value)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.declined.value = declined;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DemoRun? run = _run;
    if (_error != null) {
      return DidNotStart(
        _error!,
        background: const Color(0xFF14161A),
        foreground: const Color(0xFFFF8A80),
      );
    }
    if (run == null) {
      return const ColoredBox(
        color: Color(0xFF14161A),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // A page's own body takes the viewport's place, not the panel's: its
    // controls sit beside it the same as beside a scene.
    final List<DemoControl> controls = run.demo.controls(run.context);
    final Widget viewport =
        run.demo.customBody(context, run.context) ?? _viewport(run);
    if (controls.isEmpty) return viewport;

    final Widget panel = ControlsPanel(
      controls: controls,
      onChanged: () => setState(() {}),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => box.maxWidth >= 720
          ? Row(
              children: <Widget>[
                Expanded(child: viewport),
                SizedBox(width: 280, child: panel),
              ],
            )
          : Column(
              children: <Widget>[
                Expanded(child: viewport),
                SizedBox(height: 220, child: panel),
              ],
            ),
    );
  }

  Widget _viewport(DemoRun run) {
    final Widget surface = Listener(
      onPointerMove: (PointerMoveEvent event) =>
          run.context.orbit.rotate(event.delta.dx, event.delta.dy),
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          run.context.orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
        }
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double ratio = MediaQuery.devicePixelRatioOf(context);
          final int width = kFixedResolution
              ? 1280
              : (box.maxWidth * ratio).round().clamp(1, 8192);
          final int height = kFixedResolution
              ? 720
              : (box.maxHeight * ratio).round().clamp(1, 8192);
          final FrameResult frame = run.render(width, height);
          _report(frame);
          return presentFrame(run.context.device, frame.frame);
        },
      ),
    );
    return kFixedResolution
        ? Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: surface),
          )
        : surface;
  }
}
