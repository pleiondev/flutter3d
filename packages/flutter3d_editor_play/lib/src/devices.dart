import 'dart:convert';
import 'dart:io';

/// A device `flutter run -d` can be given, as `flutter devices --machine`
/// lists it.
final class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.emulator = false,
  });

  /// What `-d` takes.
  final String id;

  /// What a person calls it: "Galaxy A55", "macOS", "Chrome".
  final String name;

  /// The tool's `targetPlatform`: `darwin`, `android-arm64`, `web-javascript`.
  final String platform;

  final bool emulator;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform,
    'emulator': emulator,
  };

  @override
  String toString() => '$name ($id, $platform${emulator ? ', emulator' : ''})';
}

/// The devices in what `flutter devices --machine` printed.
///
/// **From the first `[` on**, because the tool may say something before the
/// list — that it is downloading an artifact, that a newer version exists —
/// and that is not a reason to offer no devices. Entries the tool marks
/// unsupported, or that lack an id, are left out: `-d` would refuse them.
List<FlutterDevice> parseFlutterDevices(String printed) {
  final start = printed.indexOf('[');
  if (start < 0) return const <FlutterDevice>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(printed.substring(start));
  } on FormatException {
    return const <FlutterDevice>[];
  }
  if (decoded is! List<Object?>) return const <FlutterDevice>[];
  return <FlutterDevice>[
    for (final entry in decoded)
      if (entry case {
        'id': final String id,
        'name': final String name,
      } when entry['isSupported'] != false)
        FlutterDevice(
          id: id,
          name: name,
          platform: '${entry['targetPlatform'] ?? 'unknown'}',
          emulator: entry['emulator'] == true,
        ),
  ];
}

/// Runs `flutter` with [arguments] to the end. A parameter of
/// [flutterDevices] so a test answers for the tool.
typedef RunFlutter = Future<ProcessResult> Function(List<String> arguments);

Future<ProcessResult> _runFlutter(List<String> arguments) =>
    Process.run('flutter', arguments, runInShell: Platform.isWindows);

/// What `flutter run -d` could be pointed at on this machine now.
///
/// Throws a [StateError] with what the tool said when it fails, since "no
/// devices" and "flutter is not on the path" are different news.
Future<List<FlutterDevice>> flutterDevices({
  RunFlutter run = _runFlutter,
}) async {
  final result = await run(const <String>['devices', '--machine']);
  if (result.exitCode != 0) {
    throw StateError('flutter devices failed: ${result.stderr}'.trim());
  }
  return parseFlutterDevices('${result.stdout}');
}
