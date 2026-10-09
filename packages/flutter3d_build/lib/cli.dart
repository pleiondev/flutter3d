/// The `flutter3d` command line, as functions: `convert`, `doctor` and
/// `create project`. `bin/flutter3d.dart` is the thin wrapper; a test calls
/// these without a process.
///
/// **A library of its own, not part of `flutter3d_build.dart`**, which the
/// build hook imports: the hook has no use for a Unity or USD reader and
/// should not compile one.
library;

export 'src/cli_contract.dart';
export 'src/convert/command.dart'
    show ConvertCommandSettings, runConvertCommand;
export 'src/convert/external.dart'
    show ExternalTool, blender, externalTools, fbx2gltf, usdcat;
export 'src/convert/report.dart';
export 'src/doctor.dart';
export 'src/project_template.dart';
