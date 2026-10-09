/// The steps a build runs: the engine's three, and any a project adds.
///
/// **The hook used to be a fixed sequence.** Models, then materials, then the
/// plugin list, written out in [buildAssets]. A project with a format of its
/// own — a baker for its terrain, an importer for a level editor's export —
/// had nowhere to put it but a second hook of its own, which ran in an order
/// nobody chose and declared its inputs separately. Now each of the three is
/// a [BuildStep] with a name, a project's own steps sit beside them, and one
/// scheduler orders them all by `after`/`before`.
///
/// **Not a plugin registry, and that is where it runs.** A plugin installs
/// into an engine at run time; a build step runs in `hook/build.dart`, before
/// the application is compiled, with no engine anywhere. So a plugin package
/// exports its steps, and the application's hook names them:
///
/// ```dart
/// import 'package:flutter3d_build/flutter3d_build.dart';
/// import 'package:hooks/hooks.dart';
/// import 'package:wind/build.dart';
///
/// void main(List<String> arguments) async {
///   await build(arguments, buildAssetsWith(<BuildStep>[WindBaker()]));
/// }
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ConstraintCycleException, ResourceException, orderByConstraints;

import 'build_assets.dart';
import 'convert.dart';
import 'layout.dart';
import 'material_build.dart';
import 'plugin_discovery.dart';

/// One thing a build does: an importer, a baker, a generated file.
///
/// **Ordered by name**, against the engine's own three ([models],
/// [materials], [plugins]) and against each other. Where [after] and
/// [before] leave a choice, the engine's steps come first and a project's
/// follow in the order it gave them — so a step that says nothing runs after
/// the plugin list, last.
///
/// **What it reads is declared to the hook.** [inputs] is asked after [run],
/// so a step may report what it actually read rather than guess it up
/// front; each path is handed to the hook as a dependency, and an edit to
/// any of them runs the build again. A step that reads a file it does not
/// list is a step whose change the next build does not notice.
///
/// `base`: extend it, so a member added later arrives with a default.
abstract base class BuildStep {
  const BuildStep();

  /// The engine's model and texture conversion, `assets_src/` into
  /// `flutter3d_generated/`.
  static const String models = 'models';

  /// The engine's material compile, `.f3dmat` into shader bundles.
  static const String materials = 'materials';

  /// The engine's plugin discovery, which writes `lib/plugins.g.dart`.
  static const String plugins = 'plugins';

  /// The engine's three, in the order they run.
  static const List<String> builtIn = <String>[models, materials, plugins];

  /// Unique among the steps of one build. The engine's three are taken.
  String get name;

  /// Steps this one runs after. A name no step has is ignored, as a loop
  /// constraint naming an absent system is.
  List<String> get after => const <String>[];

  /// Steps this one runs before.
  List<String> get before => const <String>[];

  /// Absolute paths of the files this step read, declared to the hook as
  /// dependencies. Asked after [run].
  List<String> inputs(BuildStepContext context) => const <String>[];

  /// Absolute paths of the files this step wrote, for the report. Asked
  /// after [run].
  List<String> outputs(BuildStepContext context) => const <String>[];

  /// Does the work. A throw fails the build, with this step's name in the
  /// message.
  FutureOr<void> run(BuildStepContext context);

  @override
  String toString() => 'BuildStep($name)';
}

/// What a [BuildStep] is handed: the project, where things go, and the
/// target the build is for.
final class BuildStepContext {
  BuildStepContext({
    required this.projectRoot,
    this.sink,
    this.textures = TextureFamily.auto,
    this.deviceClasses,
  });

  /// The application's root: its `pubspec.yaml`, `assets_src/` and
  /// `flutter3d_generated/`.
  final Directory projectRoot;

  /// The sink the build was given, or null for stdout.
  final IOSink? sink;

  /// Where a step writes what it says.
  IOSink get log => sink ?? stdout;

  /// The compression family the platform being built for samples.
  final TextureFamily textures;

  /// The device classes this build carries, or null for every one the
  /// manifest names.
  final List<DeviceClass>? deviceClasses;

  /// Where sources are and where generated files go.
  late final AssetLayout layout = AssetLayout(projectRoot: projectRoot);
}

/// A build step that threw, named.
final class BuildStepException extends ResourceException {
  const BuildStepException(this.step, this.error);

  /// The step's name.
  final String step;

  /// What it threw.
  final Object error;

  @override
  Object get cause => error;

  @override
  String get message => 'build step "$step" failed: $error';

  @override
  String toString() => 'BuildStepException: $message';
}

/// What [runBuildSteps] did.
final class BuildStepsReport {
  const BuildStepsReport({
    required this.ran,
    required this.dependencies,
    required this.outputs,
  });

  /// Every step's name, in the order it ran.
  final List<String> ran;

  /// Every step's [BuildStep.inputs], in run order: what the hook declares.
  final List<String> dependencies;

  /// Every step's [BuildStep.outputs], in run order.
  final List<String> outputs;
}

/// [steps] in the order they will run beside the engine's own three.
///
/// Throws an [ArgumentError] for a step named as one of the engine's or as
/// another step, and a [ConstraintCycleException] naming the steps of a cycle.
List<String> buildStepOrder(Iterable<BuildStep> steps) => <String>[
  for (final step in _ordered(_withBuiltIns(steps))) step.name,
];

/// Runs the engine's steps and [steps] against [projectRoot], in order.
///
/// Kept apart from [buildAssetsWith] for the reason [runAssetBuild] is: a
/// test calls it on a plain [Directory]. With no [steps] it does exactly
/// what the hook always did — models, then materials, then the plugin list —
/// and declares the same files in the same order.
///
/// A project's step that throws stops the build with a
/// [BuildStepException] naming it. The engine's own throw what they always
/// did ([MaterialBuildException], [PluginDiscoveryException]), whose
/// messages already name the file at fault.
Future<BuildStepsReport> runBuildSteps(
  Directory projectRoot, {
  Iterable<BuildStep> steps = const <BuildStep>[],
  IOSink? log,
  TextureFamily textures = TextureFamily.auto,
  List<DeviceClass>? deviceClasses,
}) async {
  final context = BuildStepContext(
    projectRoot: projectRoot,
    sink: log,
    textures: textures,
    deviceClasses: deviceClasses,
  );
  final ordered = _ordered(_withBuiltIns(steps));
  final ran = <String>[];
  final dependencies = <String>[];
  final outputs = <String>[];
  for (final step in ordered) {
    if (step is _BuiltInStep) {
      await step.run(context);
    } else {
      try {
        await step.run(context);
      } catch (error) {
        throw BuildStepException(step.name, error);
      }
    }
    ran.add(step.name);
    dependencies.addAll(step.inputs(context));
    outputs.addAll(step.outputs(context));
  }
  return BuildStepsReport(
    ran: List<String>.unmodifiable(ran),
    dependencies: List<String>.unmodifiable(dependencies),
    outputs: List<String>.unmodifiable(outputs),
  );
}

List<BuildStep> _withBuiltIns(Iterable<BuildStep> steps) {
  final given = List<BuildStep>.of(steps);
  final seen = <String>{...BuildStep.builtIn};
  for (final step in given) {
    if (BuildStep.builtIn.contains(step.name)) {
      throw ArgumentError.value(
        step.name,
        'steps',
        'is the name of one of the engine\'s build steps '
            '(${BuildStep.builtIn.join(', ')}); a step needs a name of its own',
      );
    }
    if (!seen.add(step.name)) {
      throw ArgumentError.value(
        step.name,
        'steps',
        'two build steps are named "${step.name}"',
      );
    }
  }
  return <BuildStep>[_Models(), _Materials(), _Plugins(), ...given];
}

List<BuildStep> _ordered(List<BuildStep> steps) =>
    orderByConstraints<BuildStep>(
      steps,
      nameOf: (step) => step.name,
      after: (step) => step.after,
      before: (step) => step.before,
      what: 'build steps',
    );

/// One of the engine's three, which throw their own exceptions.
sealed class _BuiltInStep extends BuildStep {
  _BuiltInStep();

  /// The engine's three run in the order they always did, whatever a
  /// project's step asks of the others.
  @override
  List<String> get after => switch (name) {
    BuildStep.materials => const <String>[BuildStep.models],
    BuildStep.plugins => const <String>[BuildStep.materials],
    _ => const <String>[],
  };
}

final class _Models extends _BuiltInStep {
  AssetBuildReport? _report;

  @override
  String get name => BuildStep.models;

  @override
  Future<void> run(BuildStepContext context) async {
    _report = await runAssetBuild(
      context.projectRoot,
      log: context.sink,
      textures: context.textures,
      deviceClasses: context.deviceClasses,
    );
  }

  @override
  List<String> inputs(BuildStepContext context) =>
      _report?.dependencies ?? const <String>[];
}

final class _Materials extends _BuiltInStep {
  MaterialBuildReport? _report;

  @override
  String get name => BuildStep.materials;

  @override
  void run(BuildStepContext context) {
    _report = runMaterialBuild(context.projectRoot, log: context.sink);
  }

  @override
  List<String> inputs(BuildStepContext context) =>
      _report?.dependencies ?? const <String>[];
}

final class _Plugins extends _BuiltInStep {
  List<String> _read = const <String>[];

  @override
  String get name => BuildStep.plugins;

  /// A directory with no pubspec — a test's bare asset folder — is not a
  /// package to discover anything for.
  @override
  void run(BuildStepContext context) {
    if (!File('${context.projectRoot.path}/pubspec.yaml').existsSync()) {
      _read = const <String>[];
      return;
    }
    final discovery = writeDiscoveredPlugins(context.projectRoot).discovery;
    for (final warning in discovery.warnings) {
      context.log.writeln('flutter3d_build: $warning');
    }
    _read = discovery.readFiles;
  }

  @override
  List<String> inputs(BuildStepContext context) => _read;
}
