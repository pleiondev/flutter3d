// Writes `api/flutter3d_shaders.abi`, the shader ABI one fact a line, from
// the generated tables and the vertex stages' sources; `--check` only says
// whether the committed file is current.
//
//     dart run tool/abi_snapshot.dart [--check]
import 'dart:io';

import 'shader_abi.dart';

void main(List<String> args) {
  final file = File('api/flutter3d_shaders.abi');
  final text = shaderAbiSnapshot(Directory.current.path);
  if (args.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync() != text) {
      stderr.writeln(
        '${file.path} is not what the shaders say; run '
        'dart run tool/abi_snapshot.dart',
      );
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('wrote ${file.path}');
}
