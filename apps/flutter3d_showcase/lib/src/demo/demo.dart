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
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/capability_report.dart';

/// Makes a fresh demo. Called every time a page is opened, so nothing a demo
/// holds survives a visit.
typedef DemoBuilder = ShowcaseDemo Function();

/// What a demo is given to build itself with.
final class DemoContext {
  /// A context holding what `DemoRun.start` made for one visit to a page.
  const DemoContext({
    required this.device,
    required this.renderer,
    required this.camera,
    required this.view,
    required this.orbit,
    required this.caps,
  });

  /// The app's one device, lent to the page: what a page uploads meshes and
  /// textures to. The page does not dispose of it.
  final GraphicsDevice device;

  /// The renderer made for this visit, on [device]; `DemoRun.dispose` disposes
  /// of it when the page is left.
  final Renderer renderer;

  /// The camera the viewport draws through. The host adds it to the scene.
  final CameraNode camera;

  /// The view of [camera] the viewport draws, cleared to a near-black. What
  /// [ShowcaseDemo.views] returns unless a page draws several.
  final CameraView view;

  /// Turns [camera] as the pointer drags. A demo that wants a different start
  /// sets it in [ShowcaseDemo.configureView].
  final OrbitController orbit;

  /// What this device can do, for a page that offers a control only where it
  /// works or says in its scene what it cannot show.
  final CapabilityReport caps;
}

/// A slider, a switch or a choice in the panel beside the viewport.
///
/// Descriptors and not widgets: the page says what can be changed and the host
/// draws it the same way on every page, so the panel looks like one panel.
sealed class DemoControl {
  /// A control labelled [label].
  const DemoControl(this.label);

  /// What the panel prints beside the control, in sentence case.
  final String label;
}

/// A slider over a number between [min] and [max].
final class SliderControl extends DemoControl {
  /// A slider labelled [label] over [min] to [max], reading [value] and
  /// writing [onChanged]; continuous unless [divisions] is given, and printed
  /// with two decimals unless [format] says otherwise.
  const SliderControl(
    super.label, {
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.divisions,
    this.format,
  });

  /// The left end of the slider, in the unit of the value it drives.
  final double min;

  /// The right end of the slider. A [value] outside [min] to [max] is drawn
  /// clamped to them.
  final double max;

  /// How many steps the slider snaps to between [min] and [max], or null for a
  /// continuous one.
  final int? divisions;

  /// Reads the value from the demo each time the panel is built.
  final double Function() value;

  /// Writes a new value into the demo as the slider is dragged; the demo reads
  /// it on the next frame.
  final void Function(double value) onChanged;

  /// How the value is printed beside the label, with its unit; null prints it
  /// with two decimals.
  final String Function(double value)? format;
}

/// A switch for something that is on or off.
final class ToggleControl extends DemoControl {
  /// A switch labelled [label], reading [value] and writing [onChanged].
  const ToggleControl(
    super.label, {
    required this.value,
    required this.onChanged,
  });

  /// Reads whether the switch is on from the demo each time the panel is built.
  final bool Function() value;

  /// Writes the new state into the demo when the switch is flipped.
  final void Function(bool value) onChanged;
}

/// A choice of one of several named options, drawn as a row of chips.
final class ChoiceControl extends DemoControl {
  /// A choice labelled [label] among [options], reading the chosen one from
  /// [index] and writing it with [onChanged].
  const ChoiceControl(
    super.label, {
    required this.options,
    required this.index,
    required this.onChanged,
  });

  /// The name of each option, in the order their indices count.
  final List<String> options;

  /// Reads the index into [options] of the chosen one from the demo each time
  /// the panel is built.
  final int Function() index;

  /// Writes the index of the option picked into the demo.
  final void Function(int index) onChanged;
}

/// A page that draws a scene.
abstract class ShowcaseDemo {
  /// A demo holds nothing until [build]; a page's fields are its controls'
  /// values.
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

  /// Called before every frame with the size in pixels it is about to be
  /// drawn at, for a page whose scene measures something in pixels.
  void resize(DemoContext context, int width, int height) {}

  /// Lets go of what the page holds beyond its scene — a physics core's
  /// world — when the page is left. Nothing by default.
  void dispose() {}

  /// The views one frame is made of. One, the viewport's own, unless a page
  /// is about drawing the same scene several ways at once — tiles of one
  /// picture, say — and hands back more.
  List<CameraView> views(DemoContext context) => <CameraView>[context.view];

  /// What to draw it with, read every frame, so a control that changes a
  /// setting only has to change a field.
  RenderSettings settings(DemoContext context) => const RenderSettings();

  /// The sliders, switches and choices in the panel beside the viewport, asked
  /// for each time the panel is built. None by default, and then no panel is
  /// drawn.
  List<DemoControl> controls(DemoContext context) => const <DemoControl>[];

  /// A body of the page's own instead of the viewport, for a capability that
  /// is not a picture (a writer, a decoder's report). Null to use the
  /// viewport.
  Widget? customBody(BuildContext buildContext, DemoContext context) => null;

  /// The claim this page makes, checked by its test after one frame: that what
  /// it is about actually happened. Throw, or use `expect`, to fail.
  void verify(Scene scene, FrameResult frame) {}
}
