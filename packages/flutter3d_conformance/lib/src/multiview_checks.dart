/// Multiview: a device without it refuses a masked pass by name, and the
/// one-pass-per-view fallback opens on every device that draws into array
/// layers — 1.0.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../flutter3d_conformance.dart';

RenderPassDescriptor _twoViews(GraphicsDevice device) {
  final views = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      dimension: TextureDimension.d2Array,
      depthOrArrayLayers: 2,
      usage: TextureUsage.renderTarget,
    ),
  );
  return RenderPassDescriptor(
    colors: <ColorTarget>[ColorTarget(texture: views)],
    label: 'two views',
    viewMask: 0x3,
  );
}

void _needsLayers(GraphicsDevice device) {
  if (!device.features.has(DeviceFeature.textureArrays) ||
      !device.features.has(DeviceFeature.renderToArrayLayer)) {
    decline(
      device,
      'draws into no array layer, so neither one pass of two views nor two '
      'passes of one has anywhere to go',
    );
  }
}

/// A pass naming two views is refused with `DeviceFeature.multiview` on a
/// device without it, rather than drawing one view.
Future<void> checkMultiviewRefusedByName(GraphicsDevice device) async {
  _needsLayers(device);
  if (device.features.has(DeviceFeature.multiview)) {
    decline(device, 'reports multiview, so a masked pass is not refused here');
  }
  final descriptor = _twoViews(device);
  try {
    device.beginRenderPass(descriptor).submit();
  } on UnsupportedCapabilityException catch (refusal) {
    require(
      refusal.feature == DeviceFeature.multiview,
      'a pass with a view mask was refused as ${refusal.feature.name}, not as '
      'multiview',
    );
    return;
  }
  require(
    false,
    'a pass with a view mask opened on a device without multiview: it drew '
    'one view where two were asked for',
  );
}

/// `ViewPasses.draw` draws both views: one pass each where the device has
/// no multiview, one pass for both where it does.
Future<void> checkMultiviewFallsBackPerView(GraphicsDevice device) async {
  _needsLayers(device);
  final seen = <int?>[];
  final opened = ViewPasses.draw(
    device,
    _twoViews(device),
    (CommandEncoder pass, ViewPass view) => seen.add(view.viewIndex),
  );
  if (ViewPasses.inOnePass(device, _twoViews(device))) {
    require(
      opened == 1 && seen.single == null,
      'a device with multiview drew two views in $opened passes',
    );
    return;
  }
  require(
    opened == 2 && seen.length == 2 && seen[0] == 0 && seen[1] == 1,
    'the fallback drew views $seen in $opened passes, not views 0 and 1 in '
    'two',
  );
}

/// The two, as checks.
List<ConformanceCheck> get multiviewChecks => <ConformanceCheck>[
  (
    name: 'a pass of two views is refused by name without multiview',
    run: checkMultiviewRefusedByName,
  ),
  (
    name: 'two views are drawn one pass each where one pass cannot',
    run: checkMultiviewFallsBackPerView,
  ),
];
