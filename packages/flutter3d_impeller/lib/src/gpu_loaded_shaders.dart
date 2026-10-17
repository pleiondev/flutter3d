/// A bundle loaded from bytes on flutter_gpu: `ShaderLibrary.fromBytes` and
/// `reinitializeFromBytes`, behind the HAL's `LoadedShaderLibrary`.
///
/// **The one backend where the SDK check bites.** `impellerc` output is a
/// flatbuffer whose layout follows the Flutter version, and flutter_gpu's
/// parser is not the place to find out: a bundle from another SDK may parse
/// and hand back stages that draw something else. So the section is looked
/// at only after the header's SDK token matches the one this process runs on,
/// and a mismatch is a refusal that names the bundle — the file to rebuild —
/// rather than a picture that is wrong.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart'
    show EngineBundleStamp;
import 'package:flutter_gpu/gpu.dart' as gpu;

/// The SDK this process runs on, as the token a bundle's header carries.
///
/// The first token of `Platform.version` — `3.13.0` — which is the first
/// token of `dart --version` on the machine that packed the bundle, and one
/// Flutter release ships one Dart. Read here rather than asked of Flutter,
/// which has no API for its own version.
String get runningSdk => Platform.version.split(' ').first;

/// The section this backend reads out of [bundle], or the refusal.
///
/// Pure, and public so it can be tested without a device: the two refusals
/// it makes — no section, wrong SDK — are the ones an application is most
/// likely to meet, and the messages are what it will read.
ByteData impellerSectionOf(ShaderBundle bundle, {required String running}) {
  final section = bundle.section(ShaderBundle.impellerSection);
  // 1.0: a bundle of compute kernels is refused for what it is. flutter_gpu
  // has no compute yet, so a frame on Impeller places its compute steps on
  // the wgpu sidecar or the CPU, which load the same bundle.
  if (section == null && bundle.section(ShaderBundle.kernelSection) != null) {
    throw ShaderBundleException(
      name: bundle.name,
      reason:
          'it carries compute kernels, and flutter_gpu has no compute '
          'pipelines yet (flutter/flutter#188474), so Impeller runs none. A '
          'frame places its compute steps on the wgpu sidecar or on the CPU, '
          'which load this bundle as it is.',
    );
  }
  if (section == null) {
    throw ShaderBundleException(
      name: bundle.name,
      reason:
          'it has no "${ShaderBundle.impellerSection}" section, so there is '
          'nothing compiled for this backend to load. Pack the bundle with '
          'the impellerc output beside its other sections.',
    );
  }
  if (!bundle.compiledFor(running)) {
    throw ShaderBundleException(
      name: bundle.name,
      reason:
          'its compiled section is for Dart SDK "${bundle.sdk}" and this '
          'application runs on "$running". The bundle format is tied to the '
          'Flutter version; rebuild the bundle with the SDK the application '
          'is built with.',
      stale: true,
    );
  }
  return section;
}

/// The engine's own stages for a device that opens, as flutter_gpu takes
/// them: the project's bundle when `flutter3d_build`'s hook wrote one
/// ([EngineBundleStamp.projectAsset]), and [shippedAsset] — the one this
/// package carries — when it did not. Each is held to [running] (amendment
/// 4): a bundle compiled on another SDK is a [ShaderBundleException] with
/// `stale` set and the asset and what to do named, never a library that parses
/// and draws something else.
///
/// [load] reads an asset or answers null for one that is not there; the
/// application's asset bundle outside a test.
Future<gpu.ShaderLibrary> loadEngineShaderLibrary(
  String shippedAsset, {
  Future<ByteData?> Function(String key)? load,
  String? running,
}) async {
  final read = load ?? _loadAsset;
  final sdk = running ?? runningSdk;
  final project = await read(EngineBundleStamp.projectAsset);
  final asset = project == null ? shippedAsset : EngineBundleStamp.projectAsset;
  final bytes = project ?? await read(shippedAsset);
  if (bytes == null) {
    throw ShaderBundleException(
      name: '',
      asset: shippedAsset,
      reason:
          'neither it nor ${EngineBundleStamp.projectAsset} is in the '
          "application's assets",
      advice:
          'Run the build through flutter3d_build\'s hook, which writes '
          'the project\'s bundle',
    );
  }
  final section = engineSectionOf(
    bytes,
    asset: asset,
    running: sdk,
    fromProject: project != null,
  );
  final library = await gpu.ShaderLibrary.fromBytes(section);
  if (library == null) {
    throw ShaderBundleException(
      name: 'flutter3d',
      asset: asset,
      reason: 'flutter_gpu returned no library for its compiled section',
    );
  }
  return library;
}

Future<ByteData?> _loadAsset(String key) async {
  try {
    return await rootBundle.load(key);
  } on FlutterError {
    return null;
  } on Exception {
    return null;
  }
}

/// The compiled section of the engine bundle [bytes], loaded from [asset]:
/// out of the engine's container, held to [running], or the bytes as they are
/// when they are `impellerc`'s own output — what `tool/build_shaders.sh`
/// writes in a checkout, which carries no SDK to check.
///
/// Pure, and public so the refusals are tested without a device.
/// [fromProject] says which advice the stale refusal gives: a project's
/// bundle is rebuilt by building again, the shipped one is replaced by the
/// hook writing the project's own.
ByteData engineSectionOf(
  ByteData bytes, {
  required String asset,
  required String running,
  required bool fromProject,
}) {
  if (!_isContainer(bytes)) return bytes;
  final ShaderBundle bundle;
  try {
    bundle = ShaderBundle.decode(bytes);
  } on ShaderBundleException catch (refused, stack) {
    Error.throwWithStackTrace(
      ShaderBundleException(
        name: refused.name,
        reason: refused.reason,
        stale: refused.stale,
        asset: asset,
      ),
      stack,
    );
  }
  try {
    return impellerSectionOf(bundle, running: running);
  } on ShaderBundleException catch (refused, stack) {
    final stamp = EngineBundleStamp.decode(
      bundle.section(EngineBundleStamp.section),
    );
    Error.throwWithStackTrace(
      ShaderBundleException(
        name: refused.name,
        reason: stamp == null
            ? refused.reason
            : '${refused.reason} It was built with $stamp.',
        stale: refused.stale,
        asset: asset,
        advice: !refused.stale
            ? null
            : fromProject
            ? 'Build the application again: flutter3d_build\'s hook compiles '
                  'the bundle for the SDK that runs it'
            : 'Add flutter3d_build\'s hook to the application '
                  '(hook/build.dart calling buildAssets), which compiles the '
                  'engine\'s bundle for the SDK the application is built with',
      ),
      stack,
    );
  }
}

/// Whether [bytes] start with the engine container's magic rather than
/// being `impellerc`'s flatbuffer.
bool _isContainer(ByteData bytes) {
  const magic = ShaderBundle.magic;
  if (bytes.lengthInBytes < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes.getUint8(i) != magic.codeUnitAt(i)) return false;
  }
  return true;
}

/// A [LoadedShaderLibrary] over a `gpu.ShaderLibrary` built from bytes.
///
/// Handles are cached per name, as `GpuShaderLibrary` caches them, and the
/// cache is what keeps the [LoadedShaderLibrary] promise: a reload reparses
/// into the same native library and flutter_gpu mutates each `Shader` in
/// place, so the handle already handed out wraps an object that now carries
/// the new code and is marked dirty for the next pipeline build.
///
/// One thing a reload cannot do here, stated because it is flutter_gpu's
/// cache and not this one's: a name looked up while the bundle lacked it is
/// remembered as absent on the native side, so a stage *added* to a bundle
/// after that name was asked for stays absent until the application restarts.
/// Editing a stage that exists is the case a hot reload is for, and that case
/// works.
final class GpuLoadedShaderLibrary with ShaderLibrary, LoadedShaderLibrary {
  GpuLoadedShaderLibrary._(this._name, this._library, this.running);

  /// Builds the library from a whole bundle, or refuses it by name.
  ///
  /// [running] is the SDK token to hold the header to — [runningSdk] outside
  /// a test — and the library keeps it: every [refresh] is held to the same
  /// token the load was.
  static Future<GpuLoadedShaderLibrary> load(
    ByteData bytes, {
    required String running,
  }) async {
    final bundle = ShaderBundle.decode(bytes);
    final section = impellerSectionOf(bundle, running: running);
    final gpu.ShaderLibrary? library;
    try {
      library = await gpu.ShaderLibrary.fromBytes(section);
    } catch (error, stack) {
      // flutter_gpu throws a bare `Exception` with its parser's words; the
      // caller wants the bundle's name beside them.
      Error.throwWithStackTrace(
        ShaderBundleException(
          name: bundle.name,
          reason: 'flutter_gpu could not parse its compiled section: $error',
        ),
        stack,
      );
    }
    if (library == null) {
      throw ShaderBundleException(
        name: bundle.name,
        reason: 'flutter_gpu returned no library for its compiled section',
      );
    }
    return GpuLoadedShaderLibrary._(bundle.name, library, running);
  }

  String _name;
  final gpu.ShaderLibrary _library;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  /// What [refresh] holds the header to: the token [load] was given, so a
  /// library loaded against one SDK is never reloaded against another.
  final String running;

  @override
  String get name => _name;

  @override
  ShaderHandle? operator [](String name) => _handles.putIfAbsent(name, () {
    final shader = _library[name];
    return shader == null
        ? null
        : wrapShader(
            backend: shader,
            name: name,
            release: (ShaderHandle h) => forgetShader(_handles, h),
          );
  });

  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final section = impellerSectionOf(bundle, running: running);
    // A stage already handed out that the new header no longer names is a
    // refusal before flutter_gpu sees a byte: reparsing would leave the
    // handle over whatever the old registration still holds, and the
    // contract is that a live handle always has a stage in the bundle.
    final dropped = <String>[
      for (final entry in _handles.entries)
        if (entry.value != null && !bundle.names.contains(entry.key)) entry.key,
    ];
    if (dropped.isNotEmpty) {
      throw ShaderBundleException(
        name: bundle.name,
        reason:
            'it no longer has the stage${dropped.length == 1 ? '' : 's'} '
            '${dropped.map((String n) => '"$n"').join(', ')}, which '
            '${dropped.length == 1 ? 'is' : 'are'} already in use',
      );
    }
    // flutter_gpu leaves the live shaders alone when the bytes do not parse,
    // which is the contract here too: a refused reload changes nothing.
    final error = _library.reinitializeFromBytes(section);
    if (error != null) {
      throw ShaderBundleException(
        name: bundle.name,
        reason: 'flutter_gpu could not reparse its compiled section: $error',
      );
    }
    _name = bundle.name;
    // The nulls are answers about the old bundle; the non-null handles are
    // the promise, and stay.
    _handles.removeWhere((_, ShaderHandle? handle) => handle == null);
  }
}
