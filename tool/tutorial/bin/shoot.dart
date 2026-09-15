/// `tool/tutorial/shoot.dart` — plays one scenario back against a running
/// `flutter3d_modeler` and saves a screenshot per step. `tut-00`'s own row
/// in `doc/model-editor-plan.md`: "peregenerация всех картинок — одна
/// команда" (regenerating every picture is one command) — this is that
/// command, for one case at a time.
///
///     flutter run -d macos --dart-define=mcpPort=0 \
///         -a --window=1440x900
///     dart run tool/tutorial/bin/shoot.dart \
///         --scenario tool/tutorial/test/fixtures/smoke_scenario.json \
///         --out cloud/server/web/assets/learn/modeler
///
/// Needs a real GUI build of the modeler running with `--mcp-port`.
/// Confirmed end to end against a real running window on 2026-09-15: the
/// MCP connection, `ui.standardView`/`ui.frameSubject`/`ui.say`, and
/// `screencapture -l <id>` all work without a permission prompt blocking
/// the run. One correction from that run: `--session`'s own default below
/// was a guess one directory too shallow — `getApplicationSupportDirectory()`
/// nests a further `<bundle-id>/` under `Application Support/` on macOS,
/// which this default now accounts for.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:tutorial/tutorial.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'scenario',
      help: 'path to a scenario JSON file (TutorialScenario.parse\'s shape)',
      mandatory: true,
    )
    ..addOption(
      'session',
      help:
          'path to mcp-session.json; defaults to the sandboxed app-support '
          'path the modeler writes it under, confirmed against a real run '
          '(see this file\'s own doc comment) — pass this explicitly only if '
          'the bundle id ever changes from dev.flutter3d.modeler',
      defaultsTo: _defaultSessionPath(),
    )
    ..addOption(
      'out',
      help:
          'base output directory screenshots are saved under, one '
          'subdirectory per scenario name',
      defaultsTo: 'cloud/server/web/assets/learn/modeler',
    )
    ..addOption(
      'process',
      help: 'the process name window_id.swift looks for',
      defaultsTo: 'flutter3d_modeler',
    )
    ..addOption(
      'frame-delay-ms',
      help: 'how long to wait after a tool call before screenshotting it',
      defaultsTo: '150',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'print this usage and exit',
    );

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  // `mandatory: true` on `--scenario` is only checked the first time
  // something reads it back — `parse()` itself never throws for a missing
  // one — so that first read has to be guarded here rather than above.
  final String scenarioPath;
  try {
    scenarioPath = args.option('scenario')!;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final TutorialScenario scenario;
  final McpSession session;
  try {
    final scenarioFile = File(scenarioPath);
    if (!scenarioFile.existsSync()) {
      throw FormatException('no scenario at ${scenarioFile.path}');
    }
    scenario = TutorialScenario.parse(scenarioFile.readAsStringSync());
    session = McpSession.readFile(File(args.option('session')!));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  final client = McpClient(session);
  final windowIdScript = File.fromUri(
    Platform.script.resolve('../window_id.swift'),
  ).path;
  final capture = WindowCapture(windowIdScript: windowIdScript);
  final processName = args.option('process')!;
  final frameDelay = Duration(
    milliseconds: int.parse(args.option('frame-delay-ms')!),
  );

  await client.initialize();
  try {
    // One window id for the whole scenario — the window this app opens does
    // not change mid-run, and looking it up once keeps every screenshot on
    // the same target even if a later step opens a second window (a dialog)
    // that briefly outranks it in the window list.
    int? windowId;
    final executed = await runScenario(
      scenario,
      callTool: (tool, args) async {
        await client.callTool(tool, args);
      },
      waitFrame: () => Future<void>.delayed(frameDelay),
      capture: (outputPath) async {
        windowId ??= await capture.findWindowId(processName);
        await capture.capture(windowId!, outputPath);
      },
      outDir: args.option('out')!,
    );

    final shot = executed.where((step) => step.screenshotPath != null).length;
    stdout.writeln(
      'scenario "${scenario.name}": ${executed.length} steps, $shot '
      'screenshots',
    );
  } finally {
    client.close();
  }
}

/// Where the modeler's sandboxed app-support directory holds
/// `mcp-session.json` — `dev.flutter3d.modeler`
/// (`Configs/AppInfo.xcconfig`'s own `PRODUCT_BUNDLE_IDENTIFIER`) under
/// `com.apple.security.app-sandbox`'s container. **Confirmed** against a
/// real `flutter run -d macos --dart-define=mcpPort=0` on 2026-09-15:
/// `getApplicationSupportDirectory()` nests a further `dev.flutter3d.modeler/`
/// folder under `Application Support/` (the bundle id names both the
/// container and, again, the directory path_provider hands back inside it) —
/// this was missing from an earlier, unverified guess.
String _defaultSessionPath() {
  final home = Platform.environment['HOME'] ?? '';
  return '$home/Library/Containers/dev.flutter3d.modeler/Data/Library/'
      'Application Support/dev.flutter3d.modeler/mcp-session.json';
}
