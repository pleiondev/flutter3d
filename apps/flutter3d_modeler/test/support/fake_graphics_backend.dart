/// A graphics backend for tests that do not look at the picture.
///
/// **What this is for, measured rather than assumed.** Under `flutter test`
/// there is no Impeller, so `openDevice` walks the registry, finds no
/// preferred backend that starts, and lands on the one registered
/// `asFallback` — `flutter3d_cpu`, the software rasteriser. Every widget test
/// that opens a viewport therefore rasterises it in Dart, a pixel at a time,
/// on the test's own thread. Measured on `opening_report_test.dart`: two
/// tests, 19 seconds with the rasteriser and 3 with this.
///
/// **It has to be taken off again, and that is not a detail.** `very_good
/// test` bundles a package's whole suite into one process, so a backend
/// registered by one file stays registered for every file after it. Left in
/// place, a fake that draws nothing becomes the backend a later test's
/// *picture* is drawn with — and an empty frame compares equal to another
/// empty frame, so the test goes green while asserting nothing. Hence
/// [useFakeGraphicsBackend] registering through `addTearDown` rather than
/// leaking, and hence `BackendRegistration.undo` existing at all.
///
/// **Do not use it in a test that reads pixels.** Those are tagged `golden`
/// — `very_good test -x golden` skips the lot — and they want the real
/// rasteriser.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puts a do-nothing backend in front of the software rasteriser for the
/// current test, and takes it off again afterwards.
///
/// Call from `setUp`, not `setUpAll`: the tear-down it registers belongs to
/// one test, which is what keeps the registry clean between files sharing a
/// process.
void useFakeGraphicsBackend() {
  final backend = registerBackendOpener(
    'FakeBackend (test)',
    ({required int width, required int height}) async => FakeBackend(),
  );
  _useFakePresenter();
  addTearDown(backend.undo);
}

/// Registers something to stand where a [FakeBackend]'s picture would be, and
/// takes it off again afterwards.
///
/// **Separate from [useFakeGraphicsBackend] because a device can arrive two
/// ways.** A test that lets the application open one needs the opener; a test
/// that builds its own through [fakeTestDevice] does not. Both need this:
/// `presentFrame` throws `no presenter registered for FakeBackend` the moment
/// a widget tries to show a frame, which is what twelve tests did when the
/// device was swapped and this was not.
void _useFakePresenter() {
  final presenter = registerDevicePresenter<FakeBackend>(
    (
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit = BoxFit.fill,
      FilterQuality quality = FilterQuality.none,
    }) =>
        // Sized rather than empty, because a viewport that collapses to
        // nothing changes the layout around it and a test asserting on that
        // layout would be measuring the fake instead of the application.
        SizedBox(
          width: frame.width.toDouble(),
          height: frame.height.toDouble(),
        ),
  );
  addTearDown(presenter.undo);
}

/// `cpuTestDevice`'s shape, backed by a device that draws nothing.
///
/// **The same record, so the swap is one word at the call site.** A test that
/// built a software rasteriser to hold a stage together — not to look at what
/// it drew — changes `cpuTestDevice(...)` to `fakeTestDevice(...)` and
/// nothing else: `it.device`, `it.albedo` and `it.normal` keep working.
///
/// The size arguments are accepted and ignored, deliberately rather than
/// removed. They never did what their name suggested: `ModelerViewport`
/// renders at its *widget's* constraints, so `cpuTestDevice(width: 64,
/// height: 64)` under a 400x400 box rasterised 160,000 pixels a frame and the
/// 64 was decoration. Keeping the parameters makes the swap mechanical and
/// keeps that sentence next to the number it explains.
({GraphicsDevice device, TextureHandle albedo, TextureHandle normal})
fakeTestDevice({int width = 96, int height = 72}) {
  // The helper hands out a device, so it owes the caller the thing that can
  // show that device's frames. Leaving it to the caller is what turned a
  // one-word swap into twelve tests throwing out of `LayoutBuilder`.
  _useFakePresenter();
  final device = FakeBackend();
  TextureHandle texel() => device.createTexture(
    const RenderTargetSpec(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  // White and flat-in-tangent-space are what the real helper hands back; what
  // a fake samples is nothing, so only the handles' existence matters here.
  return (device: device, albedo: texel(), normal: texel());
}
