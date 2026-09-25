/// `N7`: what a build writes for each device class — one `.f3d` per class,
/// each cut to its own budget.
///
/// **A budget is four levers the pipeline already had.** The level-of-detail
/// chain (`C5`), the impostor at its end (`C4`), the largest side a texture
/// may keep (the same `TextureBudget` numbers `makeGameReady` fits a project
/// to) and, for a level, how far the light optimizer (`N1`) may move the
/// picture to drop a light. Nothing new is computed per class; the same
/// conversion runs once per class with different numbers.
///
/// Off unless a project asks: a manifest without `classes:` builds the single
/// `.f3d` it built before, through the same code path, to the same cache key.
library;

import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:flutter3d_core/flutter3d_core.dart'
    show DeviceClass, deviceClassPath;
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show ResizeFilter, TextureBudget, resizeRgba;
import 'package:image/image.dart' as img;

export 'package:flutter3d_core/flutter3d_core.dart'
    show DeviceClass, deviceClassPath;

/// One device class's budget.
///
/// A null [lods] or [impostor] leaves the matched rule's own (or the
/// command line's) in place: the desktop preset does, so a desktop file is
/// what the project built before classes existed.
final class DeviceClassBudget {
  const DeviceClassBudget({
    required this.deviceClass,
    required this.textures,
    this.lods,
    this.impostor,
    this.impostorCell = 64,
    this.lightDifference = 0.01,
  });

  final DeviceClass deviceClass;

  /// The triangle ratios of the chain every model of this class carries, or
  /// null for the rule's own.
  final List<double>? lods;

  /// Whether the chain ends in a baked impostor, or null for the rule's own.
  final bool? impostor;

  /// The side of one impostor view, in texels; the atlas is eight of them
  /// across.
  final int impostorCell;

  /// How large a texture may stay: its `maxSide` clamps each image axis by
  /// axis, the way `FitTexturesToProfile` does for `makeGameReady`.
  final TextureBudget textures;

  /// The largest mean picture difference, and share of under-lit pixels, a
  /// light-set change may cost this class — the light optimizer's
  /// `maxDifference` and `maxUnderLit`. The desktop keeps the optimizer's own
  /// default; a phone trades more of the picture for fewer lights.
  final double lightDifference;

  /// A phone: a three-level chain ending in a small impostor, textures to
  /// `TextureBudget.mobile`, and a light set that may drift four times as far
  /// as the desktop's.
  static const DeviceClassBudget phone = DeviceClassBudget(
    deviceClass: DeviceClass.phone,
    lods: <double>[0.5, 0.25, 0.1],
    impostor: true,
    impostorCell: 32,
    textures: TextureBudget.mobile,
    lightDifference: 0.04,
  );

  /// A browser: a two-level chain and an impostor, textures to
  /// `TextureBudget.web`.
  static const DeviceClassBudget web = DeviceClassBudget(
    deviceClass: DeviceClass.web,
    lods: <double>[0.5, 0.25],
    impostor: true,
    textures: TextureBudget.web,
    lightDifference: 0.02,
  );

  /// A desktop: the rule's own chain, textures to `TextureBudget.desktop`,
  /// and the optimizer's own tolerance.
  static const DeviceClassBudget desktop = DeviceClassBudget(
    deviceClass: DeviceClass.desktop,
    textures: TextureBudget.desktop,
  );

  /// The preset for [deviceClass].
  static DeviceClassBudget presetFor(DeviceClass deviceClass) =>
      switch (deviceClass) {
        DeviceClass.phone => phone,
        DeviceClass.web => web,
        _ => desktop,
      };

  /// This budget with the given fields replaced — what a manifest's own
  /// numbers for a class do to its preset.
  DeviceClassBudget copyWith({
    List<double>? lods,
    bool? impostor,
    int? impostorCell,
    int? maxTextureSide,
    double? lightDifference,
  }) => DeviceClassBudget(
    deviceClass: deviceClass,
    lods: lods ?? this.lods,
    impostor: impostor ?? this.impostor,
    impostorCell: impostorCell ?? this.impostorCell,
    textures: maxTextureSide == null
        ? textures
        : TextureBudget(
            maxSide: maxTextureSide,
            maxBytesOnDevice: textures.maxBytesOnDevice,
            targetFormat: textures.targetFormat,
            requirePowerOfTwo: textures.requirePowerOfTwo,
          ),
    lightDifference: lightDifference ?? this.lightDifference,
  );

  /// What goes into the build cache, so a budget that changes converts again.
  String get stamp =>
      '${deviceClass.name}:${lods?.join(',') ?? '-'}:${impostor ?? '-'}:'
      '$impostorCell:${textures.maxSide}';
}

/// The classes a build for [targetOS] carries.
///
/// **A native build carries the phone and the desktop files, a web build only
/// the web's.** A browser reads nothing else, so shipping the others is
/// download size for nobody; a native application reads either of the two,
/// because a slow laptop is given the phone's and a tablet that samples BC is
/// given the desktop's.
///
/// Null is a build with no code configuration, which is how the Flutter tool
/// asks for a web build — a browser has no code assets to build — and is
/// taken as one. A project that builds some other way names its classes with
/// the `deviceClasses` hook user define instead.
List<DeviceClass> deviceClassesForTargetOS(OS? targetOS) =>
    DeviceClass.availableOn(web: targetOS == null);

/// Parses `phone,web,desktop` (or a YAML list of the same words), or returns
/// null when any of them is not a class.
List<DeviceClass>? parseDeviceClasses(Object? value) {
  final words = switch (value) {
    final String text => text.split(','),
    final List<Object?> list => <String>[for (final w in list) '$w'],
    _ => null,
  };
  if (words == null) return null;
  final classes = <DeviceClass>[];
  for (final word in words) {
    final parsed = DeviceClass.parse(word.trim());
    if (parsed == null) return null;
    if (!classes.contains(parsed)) classes.add(parsed);
  }
  return classes.isEmpty ? null : classes;
}

/// [destination] (`chair.f3d`) as [deviceClass]'s file (`chair.phone.f3d`).
String deviceClassDestination(String destination, DeviceClass deviceClass) =>
    deviceClassPath(destination, deviceClass);

/// Every image in [document] no larger than [maxSide] on either axis.
///
/// An image over it is clamped axis by axis and box-filtered down, which is
/// what `FitTexturesToProfile` does for `makeGameReady`, so a texture comes
/// out of the build at the size the editor would have fitted it to. An image
/// already inside, one already block-compressed and one this cannot decode
/// are carried over as they arrived, and [report] hears about each resize.
///
/// Runs before the texture encoder, which then compresses the smaller image
/// and cuts its chain from there.
ModelDocument fitDocumentTextures(
  ModelDocument document,
  int maxSide, {
  void Function(String message)? report,
}) {
  final fitted = <EncodedImage>[
    for (final image in document.images) _fitOne(image, maxSide, report),
  ];
  final changed = Iterable<int>.generate(
    fitted.length,
  ).any((i) => !identical(fitted[i], document.images[i]));
  if (!changed) return document;
  return PlainModelDocument(
    surfaces: document.surfaces,
    materials: document.materials,
    images: fitted,
    nodes: document.nodes,
    animations: document.animations,
    skins: document.skins,
    lights: document.lights,
    cameras: document.cameras,
    warnings: document.warnings,
    asset: document.asset,
    variants: document.variants,
  );
}

EncodedImage _fitOne(
  EncodedImage image,
  int maxSide,
  void Function(String message)? report,
) {
  if (image.isEmpty || isKtx2File(image.bytes)) return image;
  final decoded = img.decodeImage(image.bytes);
  if (decoded == null) return image;
  if (decoded.width <= maxSide && decoded.height <= maxSide) return image;
  final width = decoded.width > maxSide ? maxSide : decoded.width;
  final height = decoded.height > maxSide ? maxSide : decoded.height;
  final rgba = Uint8List.fromList(
    decoded
        .convert(format: img.Format.uint8, numChannels: 4, alpha: 255)
        .getBytes(order: img.ChannelOrder.rgba),
  );
  final resized = resizeRgba(
    rgba,
    decoded.width,
    decoded.height,
    width,
    height,
    filter: ResizeFilter.box,
  );
  report?.call(
    '${image.name ?? image.sourceUri ?? '(embedded image)'}: '
    '${decoded.width}x${decoded.height} fitted to ${width}x$height',
  );
  return EncodedImage(
    bytes: encodeCompressedPng(width, height, resized),
    name: image.name,
    mimeType: 'image/png',
    sourceUri: image.sourceUri,
  );
}
