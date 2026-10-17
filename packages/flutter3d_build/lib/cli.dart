/// The `flutter3d` command line, as functions: [runFlutter3d], the whole
/// command, and the parts a test or a tool calls on its own (`convert`,
/// `doctor`, `create project`). Every file in `bin/` is one line over
/// [runFlutter3d]: `bin/flutter3d.dart` the command, the others its
/// subcommands under their `dart run flutter3d_build:<name>` names.
///
/// **A library of its own, not part of `flutter3d_build.dart`**, which the
/// build hook imports: the hook has no use for a Unity or USD reader and
/// should not compile one.
library;

export 'src/cli_contract.dart';
export 'src/commands.dart' show runFlutter3d;
export 'src/convert/command.dart'
    show ConvertCommandSettings, runConvertCommand;
export 'src/convert/external.dart'
    show
        ExternalTool,
        MissingToolException,
        ToolFailedException,
        blender,
        externalTools,
        fbx2gltf,
        usdcat;
export 'src/convert/report.dart';
export 'src/doctor.dart';
export 'src/project_template.dart';
