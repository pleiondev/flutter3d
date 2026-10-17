// What tape_digests_test.dart reads natively: a file the script staged, from
// the package root the test runs in.
import 'dart:io';

/// The text of `build/tape_parity/<name>`.
Future<String> readStaged(String name) async {
  final file = File('build/tape_parity/$name');
  if (!file.existsSync()) {
    throw StateError(
      '${file.path} is not staged: run tool/digest_platforms.sh tapes',
    );
  }
  return file.readAsString();
}
