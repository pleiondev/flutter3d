/// The engine's stages a WebGL2 device opens over when it is handed none:
/// the `webgl` section of the project's own bundle, which `flutter3d_build`'s
/// hook writes with the stages the project needs, and the table this package
/// was compiled with where there is no such section.
///
/// **No `package:web` here**, so the choice is tested on the VM: the device
/// reads the asset and hands the bytes over.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderBundle, ShaderBundleException;
import 'package:flutter3d_shaders/flutter3d_shaders.dart'
    show EngineBundleStamp;
import 'package:flutter3d_shaders/translate.dart'
    show BundleSectionFormatException, WebGlSectionSources, decodeWebGlSection;

/// The `webgl` section of [bytes], the project's engine bundle as read from
/// [EngineBundleStamp.projectAsset]; null when there is no bundle, or when it
/// carries no section of this backend's (one written for a native target
/// only), and the device takes the table it was compiled with.
///
/// **A bundle that is there and cannot be read is refused**, with a
/// [ShaderBundleException] naming the asset, rather than passed over for the
/// compiled table: a broken project bundle is a broken build, and drawing
/// with stages the build did not choose would hide it.
WebGlSectionSources? projectWebGlSources(ByteData? bytes) {
  if (bytes == null) return null;
  const asset = EngineBundleStamp.projectAsset;
  final ShaderBundle bundle;
  try {
    bundle = ShaderBundle.decode(bytes);
  } on ShaderBundleException catch (error, stack) {
    Error.throwWithStackTrace(
      ShaderBundleException(
        name: error.name,
        reason: error.reason,
        asset: asset,
        advice: 'Build the project again so its hook writes the bundle anew',
      ),
      stack,
    );
  }
  final section = bundle.section(ShaderBundle.webglSection);
  if (section == null) return null;
  try {
    return decodeWebGlSection(section);
  } on BundleSectionFormatException catch (error, stack) {
    Error.throwWithStackTrace(
      ShaderBundleException(
        name: bundle.name,
        asset: asset,
        reason:
            'its "${ShaderBundle.webglSection}" section is not the JSON '
            'document this backend reads: ${error.message}',
        advice: 'Build the project again so its hook writes the bundle anew',
      ),
      stack,
    );
  }
}
