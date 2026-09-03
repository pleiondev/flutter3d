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

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
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
  if (section == null) {
    throw ShaderBundleRefused(
      name: bundle.name,
      reason:
          'it has no "${ShaderBundle.impellerSection}" section, so there is '
          'nothing compiled for this backend to load. Pack the bundle with '
          'the impellerc output beside its other sections.',
    );
  }
  if (!bundle.compiledFor(running)) {
    throw ShaderBundleRefused(
      name: bundle.name,
      reason:
          'its compiled section is for Dart SDK "${bundle.sdk}" and this '
          'application runs on "$running". The bundle format is tied to the '
          'Flutter version; rebuild the bundle with the SDK the application '
          'is built with.',
    );
  }
  return section;
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
final class GpuLoadedShaderLibrary implements LoadedShaderLibrary {
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
    } catch (error) {
      // flutter_gpu throws a bare `Exception` with its parser's words; the
      // caller wants the bundle's name beside them.
      throw ShaderBundleRefused(
        name: bundle.name,
        reason: 'flutter_gpu could not parse its compiled section: $error',
      );
    }
    if (library == null) {
      throw ShaderBundleRefused(
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
    return shader == null ? null : ShaderHandle(backend: shader, name: name);
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
      throw ShaderBundleRefused(
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
      throw ShaderBundleRefused(
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
