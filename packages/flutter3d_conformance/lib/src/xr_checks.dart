/// Two views of a headset's frame reach their own layers of the runtime's
/// image: through one pass where the device has multiview, through one pass
/// per view where it does not, and through the copy the projection layer
/// makes on every device with texture copies — 1.0.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import '../flutter3d_conformance.dart';

/// The color each view is cleared to: view 0 red, view 1 blue.
final List<Vector4> _viewColors = <Vector4>[
  Vector4(1.0, 0.0, 0.0, 1.0),
  Vector4(0.0, 0.0, 1.0, 1.0),
];

const int _size = 4;

/// A runtime's image: an array texture with a layer for each of two views.
TextureHandle _image(GraphicsDevice device) => device.createTexture(
  const TextureDescriptor(
    width: _size,
    height: _size,
    format: TextureFormat.r8g8b8a8UNormInt,
    dimension: TextureDimension.d2Array,
    depthOrArrayLayers: 2,
    usage: TextureUsage.standard,
  ),
);

/// Declines a device that cannot put a layer where a readback can see it.
void _needsCopies(GraphicsDevice device) {
  if (!device.features.has(DeviceFeature.textureArrays) ||
      !device.features.has(DeviceFeature.textureCopy)) {
    decline(
      device,
      'has no array textures or no texture copies, so no view reaches a '
      "layer of a runtime's image",
    );
  }
}

/// Layer [layer] of [image], copied into a texture of its own and read back.
Future<ByteData> _readLayer(
  GraphicsDevice device,
  TextureHandle image,
  int layer,
) async {
  final flat = device.createTexture(
    const RenderTargetDescriptor(
      width: _size,
      height: _size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  try {
    device.beginTransferPass(label: 'layer $layer out')
      ..copyTextureToTexture(
        TextureCopyLocation(image, z: layer),
        TextureCopyLocation(flat),
        width: _size,
        height: _size,
      )
      ..submit();
    return await device.readback(flat);
  } finally {
    device.releaseTexture(flat);
  }
}

/// Holds layer [layer] of [image] to [color], every texel.
Future<void> _requireLayer(
  GraphicsDevice device,
  TextureHandle image,
  int layer,
  Vector4 color,
  String how,
) async {
  final bytes = await _readLayer(device, image, layer);
  final want = <int>[
    (color.x * 255).round(),
    (color.y * 255).round(),
    (color.z * 255).round(),
    (color.w * 255).round(),
  ];
  for (var texel = 0; texel < _size * _size; texel++) {
    for (var channel = 0; channel < 4; channel++) {
      final got = bytes.getUint8(texel * 4 + channel);
      require(
        (got - want[channel]).abs() <= 1,
        '$how: layer $layer texel $texel channel $channel is $got, not '
        '${want[channel]}',
      );
    }
  }
}

/// Each view drawn by a pass of its own into its layer — the fallback of a
/// device without multiview — lands in that layer and no other.
Future<void> checkViewsDrawnPerLayer(GraphicsDevice device) async {
  _needsCopies(device);
  if (!device.features.has(DeviceFeature.renderToArrayLayer)) {
    decline(
      device,
      'draws into no array layer, so a view has no pass of its own',
    );
  }
  final image = _image(device);
  try {
    for (var view = 0; view < 2; view++) {
      device
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[
                ColorTarget(
                  texture: image,
                  clearValue: _viewColors[view],
                  layer: view,
                ),
              ],
              label: 'view $view',
            ),
          )
          .submit();
    }
    for (var view = 0; view < 2; view++) {
      await _requireLayer(
        device,
        image,
        view,
        _viewColors[view],
        'one pass per view',
      );
    }
  } finally {
    device.releaseTexture(image);
  }
}

/// Two views drawn side by side into one target and copied each into its
/// layer — what `ProjectionLayerNode` does for a runtime — land each in its
/// own layer.
Future<void> checkViewsCopiedIntoLayers(GraphicsDevice device) async {
  _needsCopies(device);
  final image = _image(device);
  final views = <TextureHandle>[
    for (var view = 0; view < 2; view++)
      device.createTexture(
        const RenderTargetDescriptor(
          width: _size,
          height: _size,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      ),
  ];
  try {
    for (var view = 0; view < 2; view++) {
      device
          .beginRenderPass(
            RenderPassDescriptor(
              colors: <ColorTarget>[
                ColorTarget(
                  texture: views[view],
                  clearValue: _viewColors[view],
                ),
              ],
              label: 'eye $view',
            ),
          )
          .submit();
    }
    final copies = device.beginTransferPass(label: 'projection layer');
    for (var view = 0; view < 2; view++) {
      copies.copyTextureToTexture(
        TextureCopyLocation(views[view]),
        TextureCopyLocation(image, z: view),
        width: _size,
        height: _size,
      );
    }
    copies.submit();
    for (var view = 0; view < 2; view++) {
      await _requireLayer(
        device,
        image,
        view,
        _viewColors[view],
        'copied into its layer',
      );
    }
  } finally {
    for (final view in views) {
      device.releaseTexture(view);
    }
    device.releaseTexture(image);
  }
}

/// One multiview pass over both views clears both layers, on a device that
/// has multiview; a device without it is asked by the refusal check
/// beside this one.
Future<void> checkViewsDrawnInOnePass(GraphicsDevice device) async {
  _needsCopies(device);
  if (!device.features.has(DeviceFeature.multiview)) {
    decline(
      device,
      'has no multiview, so its views are drawn one pass each (checked '
      'beside this)',
    );
  }
  final image = _image(device);
  try {
    final opened = ViewPasses.draw(
      device,
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: image, clearValue: _viewColors.first),
        ],
        viewMask: 0x3,
        label: 'both views',
      ),
      (CommandEncoder pass, ViewPass view) {},
    );
    require(opened == 1, 'a device with multiview drew two views in $opened');
    for (var view = 0; view < 2; view++) {
      await _requireLayer(
        device,
        image,
        view,
        _viewColors.first,
        'one multiview pass',
      );
    }
  } finally {
    device.releaseTexture(image);
  }
}

/// The three, as checks.
List<ConformanceCheck> get xrChecks => <ConformanceCheck>[
  (
    name: 'two views drawn a pass each land in their own layers',
    run: checkViewsDrawnPerLayer,
  ),
  (
    name: 'two views copied into a runtime image land in their own layers',
    run: checkViewsCopiedIntoLayers,
  ),
  (
    name: 'two views drawn in one multiview pass land in both layers',
    run: checkViewsDrawnInOnePass,
  ),
];
