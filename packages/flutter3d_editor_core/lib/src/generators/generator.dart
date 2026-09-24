import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A program that writes documents: the files it owns, by path, as text.
///
/// **Paths, not a disk.** This package reads no file and writes none (see its
/// library comment), so a generator is handed a [GeneratorSource] for what it
/// has to read — a document another generator wrote, a file it copies — and
/// gives back what it would write. The tool that runs it does the IO; a test
/// compares the text with what is committed and never touches a file.
typedef LevelGenerator = Map<String, String> Function(GeneratorSource source);

/// What a generator may read, and which of a directory's files exist.
abstract interface class GeneratorSource {
  /// The text of the file at [path], relative to the repository root.
  String read(String path);

  /// The names of the files directly in [directory], relative to the root.
  List<String> list(String directory);
}

/// A generator refusing to write a document a player could not use.
///
/// Thrown at generate time rather than left for the loader, which would say
/// the same in front of a player: a generator is run far more often than a
/// level is loaded.
final class GeneratorRefused implements Exception {
  const GeneratorRefused(this.message);

  final String message;

  @override
  String toString() => 'GeneratorRefused: $message';
}

/// [value] to [digits] places the way a document's own numbers are, keeping
/// an `int` an `int`.
///
/// A yaw of `0` and a yaw of `0.0` are different bytes in a file, and the
/// generators that wrote the shipped levels kept the difference — so a
/// rewritten one has to as well.
num roundNumber(num value, int digits) =>
    value is int ? value : roundDecimal(value.toDouble(), digits);
