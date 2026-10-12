// Stages what the tape parity reads, from the package root:
//
//     dart run tool/tape_parity/stage.dart
//
// copies the tapes and their levels into `build/tape_parity/`, where the VM
// reads them and a browser test fetches them, and writes
// `build/tape_parity/defines.json`, the same files handed to a device as
// one define (see `tape_digests_device_test.dart`).
//
// Plain Dart, apart from `tape_play.dart` and the games it imports, so it
// runs before anything is built.
import 'dart:convert';
import 'dart:io';

/// The files `tape_play.dart` reads, by the name it reads them under, from
/// where they live in the repository.
const Map<String, String> _files = <String, String>{
  'racing.f3drun': 'site/assets/samples/racing.f3drun',
  'ring.json': 'apps/flutter3d_demo_racing/assets/tracks/ring.json',
  'shooter.f3drun': 'site/assets/samples/shooter.f3drun',
  'crypt.json': 'apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
};

void main() {
  final out = Directory('build/tape_parity')..createSync(recursive: true);
  final contents = <String, String>{};
  for (final MapEntry(key: name, value: path) in _files.entries) {
    final file = File('../../$path');
    if (!file.existsSync()) {
      stderr.writeln('no ${file.path}: run from the package root');
      exitCode = 2;
      return;
    }
    contents[name] = file.readAsStringSync();
    file.copySync('${out.path}/$name');
  }
  File('${out.path}/defines.json').writeAsStringSync(
    jsonEncode(<String, String>{
      'F3D_TAPE_PARITY_GZIP': base64.encode(
        gzip.encode(utf8.encode(jsonEncode(contents))),
      ),
    }),
  );
  stdout.writeln('staged ${_files.length} files in ${out.path}');
}
