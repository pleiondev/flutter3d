/// What a page is, to the app that hosts it.
///
/// **A page contains the lines that are about its capability and nothing
/// else.** Opening the device, building the renderer, orbiting the camera,
/// drawing the controls and telling the person that their backend skipped a
/// pass are the host's, written once in `demo_viewport.dart`. A page file is
/// then short enough to be read as a guide, and every line of it can be quoted
/// by one: that is the reason for the split, and the reason a helper a page
/// needs goes into the page's own file until it is used by a second one.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_showcase/src/demo/capability_report.dart';

/// Makes a fresh demo. Called every time a page is opened, so nothing a demo
/// holds survives a visit.
typedef DemoBuilder = ShowcaseDemo Function();

/// What a demo is given to build itself with.
final class DemoContext {
  const DemoContext({
    required this.device,
    required this.renderer,
    required this.camera,
    required this.view,
    required this.orbit,
    required this.caps,
  });

  final GraphicsDevice device;
  final Renderer renderer;

  /// The camera the viewport draws through. The host adds it to the scene.
  final CameraNode camera;
  final RenderView view;

  /// Turns [camera] as the pointer drags. A demo that wants a different start
  /// sets it in [ShowcaseDemo.configureView].
  final OrbitController orbit;
  final CapabilityReport caps;
}

/// A slider, a switch or a choice in the panel beside the viewport.
///
/// Descriptors and not widgets: the page says what can be changed and the host
/// draws it the same way on every page, so the panel looks like one panel.
sealed class DemoControl {
  const DemoControl(this.label);

  final String label;
}

final class SliderControl extends DemoControl {
  const SliderControl(
    super.label, {
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.divisions,
    this.format,
  });

  final double min;
  final double max;
  final int? divisions;
  final double Function() value;
  final void Function(double value) onChanged;
  final String Function(double value)? format;
}

final class ToggleControl extends DemoControl {
  const ToggleControl(
    super.label, {
    required this.value,
    required this.onChanged,
  });

  final bool Function() value;
  final void Function(bool value) onChanged;
}

final class ChoiceControl extends DemoControl {
  const ChoiceControl(
    super.label, {
    required this.options,
    required this.index,
    required this.onChanged,
  });

  final List<String> options;
  final int Function() index;
  final void Function(int index) onChanged;
}

/// A page that draws a scene.
abstract class ShowcaseDemo {
  const ShowcaseDemo();

  /// Where the camera starts, if not at the default distance and angle.
  void configureView(DemoContext context) {}

  /// Anything to load before [build], such as a sample model. The viewport
  /// shows a spinner until it completes.
  Future<void> prepare(DemoContext context) async {}

  /// The scene. The host adds the camera to it.
  Scene build(DemoContext context);

  /// Called every frame with the seconds since the last, before it is drawn.
  void update(DemoContext context, double dt) {}

  /// What to draw it with, read every frame, so a control that changes a
  /// setting only has to change a field.
  RenderSettings settings(DemoContext context) => const RenderSettings();

  List<DemoControl> controls(DemoContext context) => const <DemoControl>[];

  /// A body of the page's own instead of the viewport, for a capability that
  /// is not a picture (a writer, a decoder's report). Null to use the
  /// viewport.
  Widget? customBody(BuildContext buildContext, DemoContext context) => null;

  /// The claim this page makes, checked by its test after one frame: that what
  /// it is about actually happened. Throw, or use `expect`, to fail.
  void verify(Scene scene, FrameResult frame) {}
}
