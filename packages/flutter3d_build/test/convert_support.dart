// What the `flutter3d convert` suites share: running the command into a
// scratch directory and reading back what it said and wrote.
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/cli.dart';

/// The fixtures, small enough to read in a diff.
const String fixtures = 'test/fixtures/convert';

/// One run: its exit code, its JSON report, and where it wrote.
final class ConvertRun {
  const ConvertRun(this.code, this.json, this.output, this.text);

  final int code;
  final Map<String, Object?> json;
  final Directory output;
  final String text;

  /// The report for the input whose path ends with [suffix].
  Map<String, Object?> report(String suffix) =>
      (json['reports']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (Map<String, Object?> r) =>
                (r['input']! as String).endsWith(suffix),
          );

  /// The file the run wrote at [relative], as text.
  String read(String relative) =>
      File('${output.path}/$relative').readAsStringSync();

  /// The file the run wrote at [relative], decoded.
  Object? readJson(String relative) => jsonDecode(read(relative));

  bool wrote(String relative) => File('${output.path}/$relative').existsSync();
}

/// Runs `flutter3d convert` with [arguments] into [output] (a fresh scratch
/// directory when null), always with `--json`, and with `--split` unless
/// [bundle]: the format tests check each file a format maps to, which the
/// split layout writes separately.
Future<ConvertRun> convert(
  List<String> arguments, {
  Directory? output,
  bool bundle = false,
}) async {
  final out = output ?? Directory.systemTemp.createTempSync('f3d_import_');
  final sink = BufferSink();
  final code = await runConvertCommand(
    <String>[...arguments, '-o', out.path, '--json', if (!bundle) '--split'],
    out: sink,
    err: BufferSink(),
  );
  final text = sink.text;
  final start = text.indexOf('{');
  return ConvertRun(
    code,
    start < 0
        ? const <String, Object?>{}
        : jsonDecode(text.substring(start)) as Map<String, Object?>,
    out,
    text,
  );
}

/// An [IOSink] into a string.
final class BufferSink implements IOSink {
  final StringBuffer _buffer = StringBuffer();
  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  Encoding encoding = utf8;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  Future<void> flush() async {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
}
