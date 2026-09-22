import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter3d_showcase/src/registry/registry.dart';

/// A device that draws with no window and no GPU.
CpuDevice cpuDevice({int width = 320, int height = 180}) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// What one page did on one frame.
final class PageFrame {
  const PageFrame(this.frame, this.litPixels);

  final FrameResult frame;

  /// Pixels that are not near-black, so a frame that drew nothing is
  /// distinguishable from one that drew something dark.
  final int litPixels;
}

/// Builds the page of [feature], draws one frame of it on the software device
/// and runs the page's own claim against that frame.
Future<PageFrame> renderPage(Feature feature) async {
  final DemoBuilder? build = kDemos[feature.id];
  if (build == null) throw StateError('no demo registered for ${feature.id}');
  final CpuDevice device = cpuDevice();
  final DemoRun run = await DemoRun.start(device, build());
  try {
    run.update(1 / 60);
    final FrameResult frame = run.render(320, 180);
    run.demo.verify(run.scene, frame);
    final pixels = (await device.readPixels(frame.frame))!.buffer.asUint8List();
    var lit = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] + pixels[i + 1] + pixels[i + 2] > 30) lit++;
    }
    return PageFrame(frame, lit);
  } finally {
    run.dispose();
  }
}

/// The whole catalog, for a test that walks it.
List<Feature> get allFeatures => kCatalog;
