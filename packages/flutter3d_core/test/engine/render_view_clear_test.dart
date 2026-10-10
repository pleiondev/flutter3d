// A view's clear colour is a `LinearColor`, linear like every other colour
// the engine takes; a colour read off a picker goes in through `fromSrgb`.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:test/test.dart';

void main() {
  test('a view clears to the dark slate it always did, as linear light', () {
    final view = RenderView(camera: CameraNode());
    expect(view.clearColor, LinearColor.fromSrgb(0.055, 0.062, 0.078));
    expect(view.clearColor, RenderView.defaultClearColor);
  });

  test('a clear colour given is kept as given, and assigned whole', () {
    final view = RenderView(
      camera: CameraNode(),
      clearColor: const LinearColor(0.1, 0.2, 0.3),
    );
    expect(view.clearColor, const LinearColor(0.1, 0.2, 0.3));
    view.clearColor = LinearColor.black;
    expect(view.clearColor, LinearColor.black);
  });
}
