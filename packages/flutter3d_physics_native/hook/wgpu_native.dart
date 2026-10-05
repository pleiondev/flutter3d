// Fetches wgpu-native for the target the hook builds for — P9, phase 10.
//
// A pinned release of gfx-rs/wgpu-native, its archive's sha256 checked
// against the one written here, unpacked into the hooks' shared output so a
// second build does not fetch it again. Only the static library and the
// headers are kept: the GPU library links wgpu-native in, so there is one
// binary to ship and no second one to find at run time.
//
// When there is no release for the target, no network, or a checksum that
// does not match, this says why and returns null, and the hook builds the
// core without its GPU passes: a game built offline still runs, on the CPU.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';

/// The release, and each archive's sha256 as the release lists it.
const String wgpuNativeVersion = 'v29.0.1.1';

const Map<String, String> wgpuNativeArchives = <String, String>{
  'android-aarch64':
      '721741f1b05a20c1738166bedf7a5efb2ba4b382da689526d3fc33de22bdd573',
  'android-armv7':
      'f9d76c77b3fda3f7121476884eb16ec067f7dada83276298a3cc8bf6a8403d60',
  'android-i686':
      '593b94875bc4fcc1506ea0b6714dd12b96b7c852921caa63f45eb61517793312',
  'android-x86_64':
      'ef16fc0644bf0e308a39ac4516742da8e22d8c201d3a542cc5baf533d272c491',
  'ios-aarch64':
      'e36c9913b9e5095a530fa9121c50b16a4e3dd020e1eebf601f2f47ce24d56941',
  'ios-aarch64-simulator':
      '750e706765bef3744313745194774d095c916fc21d2a0e7d4d7b0bc4d0c92789',
  'ios-x86_64-simulator':
      '94f67e1b268e8dd31b8e59b32f211ac469f09ed7950fceee52bd84f0623da3d9',
  'linux-aarch64':
      '015fcdf1dbae82e614a783cc38017e5399ae0927a889fe9b69c9b664bc61b47a',
  'linux-x86_64':
      '95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a',
  'macos-aarch64':
      'a5797a37b1adf720bcd5dcffb291edbbd5b7b14be0a3874c28e6393a655a7a3e',
  'macos-x86_64':
      '8e2f7378548ddd0e2cf21e7d864dda46e953f0af724855a33778b85ead206d41',
  'windows-aarch64-msvc':
      '4a876421a8c1e5fe72f849b3722214280fe485cb1c56f77f8b0c82414be5b29f',
  'windows-x86_64-msvc':
      '7e67d7445c42aeb85e30f88930fd8d7d83ee769e3390aeb1ada75ebf3cf78132',
};

/// The release's name for [config]'s target, or null when it has none.
String? wgpuNativeTarget(CodeConfig config) {
  final arch = config.targetArchitecture;
  switch (config.targetOS) {
    case OS.macOS:
      return arch == Architecture.arm64 ? 'macos-aarch64' : 'macos-x86_64';
    case OS.linux:
      if (arch == Architecture.arm64) return 'linux-aarch64';
      return arch == Architecture.x64 ? 'linux-x86_64' : null;
    case OS.windows:
      if (arch == Architecture.arm64) return 'windows-aarch64-msvc';
      return arch == Architecture.x64 ? 'windows-x86_64-msvc' : null;
    case OS.android:
      if (arch == Architecture.arm64) return 'android-aarch64';
      if (arch == Architecture.arm) return 'android-armv7';
      if (arch == Architecture.x64) return 'android-x86_64';
      return arch == Architecture.ia32 ? 'android-i686' : null;
    case OS.iOS:
      final simulator = config.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      if (!simulator) return arch == Architecture.arm64 ? 'ios-aarch64' : null;
      return arch == Architecture.arm64
          ? 'ios-aarch64-simulator'
          : 'ios-x86_64-simulator';
    default:
      return null;
  }
}

/// When every unpacked file says it was last modified.
final DateTime _unpackedAt = DateTime.utc(2000);

/// Where wgpu-native for [target] is unpacked under [shared]: its `include`
/// and `lib` directories. Fetches it the first time; null, after saying why
/// through [say], when it cannot.
Future<Directory?> fetchWgpuNative(
  String target,
  Uri shared,
  void Function(String) say,
) async {
  final expected = wgpuNativeArchives[target];
  if (expected == null) {
    say(
      'no wgpu-native $wgpuNativeVersion for $target: building without GPU passes',
    );
    return null;
  }
  final home = Directory.fromUri(
    shared.resolve('wgpu-native/$wgpuNativeVersion/$target/'),
  );
  final done = File('${home.path}/.unpacked');
  if (done.existsSync() && done.readAsStringSync() == expected) return home;
  final url = Uri.parse(
    'https://github.com/gfx-rs/wgpu-native/releases/download/'
    '$wgpuNativeVersion/wgpu-$target-release.zip',
  );
  final List<int> bytes;
  try {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        say(
          'fetching $url: HTTP ${response.statusCode}: building without GPU passes',
        );
        return null;
      }
      bytes = await response.fold<List<int>>(
        <int>[],
        (all, part) => all..addAll(part),
      );
    } finally {
      client.close();
    }
  } on IOException catch (e) {
    say('fetching $url: $e: building without GPU passes');
    return null;
  }
  final actual = sha256.convert(bytes).toString();
  if (actual != expected) {
    say('$url has sha256 $actual, not $expected: building without GPU passes');
    return null;
  }
  // Only the headers and the static library: the dynamic one would be what
  // the linker prefers, and is not what is shipped.
  final archive = ZipDecoder().decodeBytes(bytes);
  home.createSync(recursive: true);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name;
    final keep =
        name.startsWith('include/') ||
        name.endsWith('/libwgpu_native.a') ||
        name.endsWith('/wgpu_native.lib') ||
        name == 'lib/libwgpu_native.a' ||
        name == 'lib/wgpu_native.lib';
    if (!keep) continue;
    File('${home.path}/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(entry.content as List<int>)
      // Dated long before this build: the headers are what the GPU library
      // is compiled against, so they are among its dependencies, and a file
      // dated now told the build runner it was modified during the build —
      // "Build must be rerun", and `flutter test` exiting 1 on every fresh
      // checkout, CI's every run.
      ..setLastModifiedSync(_unpackedAt);
  }
  done.writeAsStringSync(expected);
  return home;
}

/// What the static wgpu-native needs linked beside it on [os].
List<String> wgpuNativeSystemLibraries(OS os) => switch (os) {
  OS.macOS || OS.iOS => const <String>[
    '-framework',
    'Metal',
    '-framework',
    'QuartzCore',
    '-framework',
    'Foundation',
  ],
  OS.linux => const <String>['-lm', '-ldl', '-lpthread'],
  OS.android => const <String>['-lm', '-ldl', '-llog', '-landroid'],
  OS.windows => const <String>[
    'd3d12.lib',
    'dxgi.lib',
    'd3dcompiler.lib',
    'user32.lib',
    'ws2_32.lib',
    'userenv.lib',
    'bcrypt.lib',
    'ntdll.lib',
    'opengl32.lib',
    'gdi32.lib',
    'ole32.lib',
    'oleaut32.lib',
    'advapi32.lib',
    'propsys.lib',
    'runtimeobject.lib',
  ],
  _ => const <String>[],
};
