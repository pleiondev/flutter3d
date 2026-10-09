/// `flutter3d doctor`: the toolchain a project builds with, against what
/// SUPPORT.md promises, and the optional programs the build and the
/// converter use when they are there.
library;

import 'dart:convert';
import 'dart:io';

import 'cli_contract.dart';
import 'convert/external.dart';

/// The Dart every pubspec's floor names (SUPPORT.md, "The Flutter and Dart
/// SDKs"). A structure test reads that section and holds these to it.
const String dartFloor = '3.12.0';

/// The Flutter floor of every package that names Flutter.
const String flutterFloor = '3.44.0';

/// The Flutter stable CI runs.
const String flutterTested = '3.47.0';

/// The Dart CI runs the plain Dart packages on.
const String dartTested = '3.13.0';

/// How a check came out.
final class DoctorStatus {
  const DoctorStatus._(this.mark, this.name);

  /// What the terminal shows before the line.
  final String mark;
  final String name;

  /// Found, and new enough.
  static const DoctorStatus ok = DoctorStatus._('[ok]', 'ok');

  /// Found, and outside what is tested: works, probably.
  static const DoctorStatus note = DoctorStatus._('[~~]', 'note');

  /// Optional, and not found: one feature is unavailable.
  static const DoctorStatus missing = DoctorStatus._('[--]', 'missing');

  /// Required, and absent or too old. The command exits 1.
  static const DoctorStatus problem = DoctorStatus._('[!!]', 'problem');
}

/// One line of the doctor's report.
final class DoctorCheck {
  const DoctorCheck(this.name, this.status, this.detail, {this.fix});

  final String name;
  final DoctorStatus status;
  final String detail;

  /// What to do about it, when anything.
  final String? fix;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'status': status.name,
    'detail': detail,
    'fix': ?fix,
  };
}

/// Compares two dotted versions, ignoring anything after a space or `-`.
/// Negative when [a] is older.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[\s-]'))
      .first
      .split('.')
      .map((String p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Runs a program and returns its stdout, or null when it cannot start or
/// fails.
typedef ProcessProbe =
    String? Function(String executable, List<String> arguments);

String? _probe(String executable, List<String> arguments) {
  try {
    final result = Process.runSync(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) return null;
    return '${result.stdout}${result.stderr}';
  } on ProcessException {
    return null;
  }
}

/// Every check, in the order the report prints them.
///
/// [probe] runs a program; [locate] finds an external tool. Both are
/// parameters so a test can answer for a machine it is not running on.
List<DoctorCheck> runDoctorChecks({
  ProcessProbe probe = _probe,
  String? Function(ExternalTool tool)? locate,
  String? dartVersion,
}) {
  final find = locate ?? (ExternalTool t) => t.locate();
  final checks = <DoctorCheck>[];

  final dart = dartVersion ?? Platform.version.split(' ').first;
  checks.add(
    _versionCheck('Dart', dart, dartFloor, dartTested, required: true),
  );

  final machine = probe(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    const <String>['--version', '--machine'],
  );
  String? flutterRoot;
  if (machine == null) {
    checks.add(
      const DoctorCheck(
        'Flutter',
        DoctorStatus.missing,
        'not found on PATH',
        fix:
            'a game needs Flutter $flutterFloor or later (https://docs.flutter.dev/get-started/install); '
            'the plain Dart packages and this command do not',
      ),
    );
  } else {
    final start = machine.indexOf('{');
    final Object? info = start < 0 ? null : _tryJson(machine.substring(start));
    final map = info is Map ? info : const <String, Object?>{};
    final version = '${map['frameworkVersion'] ?? '?'}';
    flutterRoot = map['flutterRoot'] as String?;
    final channel = map['channel'] as String?;
    checks.add(
      _versionCheck(
        'Flutter',
        version,
        flutterFloor,
        flutterTested,
        required: true,
        extra: channel == null ? '' : ', $channel channel',
      ),
    );
    if (map['dartSdkVersion'] case final String bundled) {
      checks.add(
        _versionCheck(
          "Flutter's Dart",
          bundled,
          dartFloor,
          dartTested,
          required: true,
        ),
      );
    }
  }

  // impellerc: what builds the Impeller shader bundles from source.
  final impellerc = flutterRoot == null ? null : _impellerc(flutterRoot);
  checks.add(
    impellerc == null
        ? const DoctorCheck(
            'impellerc',
            DoctorStatus.missing,
            'not found in the Flutter SDK\'s engine artifacts',
            fix:
                'run `flutter precache`; needed only to build shader bundles from a checkout',
          )
        : DoctorCheck('impellerc', DoctorStatus.ok, impellerc),
  );

  for (final (name, purpose, install) in const <(String, String, String)>[
    (
      'glslangValidator',
      'the WebGPU section of a material bundle',
      'install the Vulkan SDK or `brew install glslang`',
    ),
    (
      'naga',
      'the WebGPU section of a material bundle',
      '`cargo install naga-cli`',
    ),
  ]) {
    final path = findOnPath(name);
    checks.add(
      path == null
          ? DoctorCheck(
              name,
              DoctorStatus.missing,
              'not on PATH: materials build without $purpose',
              fix: install,
            )
          : DoctorCheck(name, DoctorStatus.ok, path),
    );
  }

  for (final tool in externalTools) {
    final path = find(tool);
    checks.add(
      path == null
          ? DoctorCheck(
              tool.name,
              DoctorStatus.missing,
              'not found: flutter3d convert cannot use it (${tool.purpose})',
              fix: tool.install,
            )
          : DoctorCheck(tool.name, DoctorStatus.ok, '$path (${tool.purpose})'),
    );
  }
  return checks;
}

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

String? _impellerc(String flutterRoot) {
  final engine = '$flutterRoot/bin/cache/artifacts/engine';
  for (final platform in const <String>[
    'darwin-x64',
    'darwin-arm64',
    'linux-x64',
    'linux-arm64',
    'windows-x64',
    'windows-arm64',
  ]) {
    for (final name in const <String>['impellerc', 'impellerc.exe']) {
      final path = '$engine/$platform/$name';
      if (File(path).existsSync()) return path;
    }
  }
  return null;
}

DoctorCheck _versionCheck(
  String name,
  String version,
  String floor,
  String tested, {
  required bool required,
  String extra = '',
}) {
  if (compareVersions(version, floor) < 0) {
    return DoctorCheck(
      name,
      required ? DoctorStatus.problem : DoctorStatus.missing,
      '$version$extra is older than the floor, $floor',
      fix: 'upgrade to $tested, the version CI runs',
    );
  }
  final major = version.split('.').first;
  if (major != tested.split('.').first) {
    return DoctorCheck(
      name,
      DoctorStatus.note,
      '$version$extra: a major CI has not run ($tested)',
    );
  }
  return DoctorCheck(
    name,
    DoctorStatus.ok,
    '$version$extra (floor $floor, CI $tested)',
  );
}

/// `flutter3d doctor`'s `main`. Returns 1 when a required check failed.
int runDoctor(List<String> arguments, {IOSink? out}) {
  final sink = out ?? stdout;
  if (arguments.contains('-h') || arguments.contains('--help')) {
    sink.writeln(doctorUsage);
    return 0;
  }
  final checks = runDoctorChecks();
  if (arguments.contains('--json')) {
    sink.writeln(
      const JsonEncoder.withIndent('  ').convert(
        cliJson('doctor', <String, Object?>{
          'checks': <Object?>[for (final c in checks) c.toJson()],
        }),
      ),
    );
  } else {
    for (final check in checks) {
      sink.writeln(
        '${check.status.mark} ${check.name.padRight(18)} ${check.detail}',
      );
      if (check.fix case final String fix
          when check.status != DoctorStatus.ok) {
        sink.writeln('     ${''.padRight(18)} $fix');
      }
    }
  }
  return checks.any((DoctorCheck c) => c.status == DoctorStatus.problem)
      ? 1
      : 0;
}
