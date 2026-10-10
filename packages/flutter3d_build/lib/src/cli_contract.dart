/// What the `flutter3d` command promises to scripts and CI from 1.0: its
/// exit codes, the shape of its `--json` output, and the list of its
/// subcommands.
///
/// **Frozen like the Dart API.** A script that checks `$? -eq 3` or reads
/// `.reports[0].outcome` is a caller, and strict semver covers it: a
/// subcommand, a flag or an exit code is not removed or renamed within a
/// major, and the `--json` output only grows. `api/flutter3d_build.cli` is the
/// whole surface as `flutter3d help --surface` prints it, and the structure
/// check fails when the two differ, so a change to it is a change somebody
/// reviewed.
library;

/// The exit codes every `flutter3d` subcommand answers with.
///
/// A subcommand uses the ones that apply to it; none uses a number outside
/// this list.
abstract final class CliExit {
  /// It did what it was asked, or there was nothing to do.
  static const int ok = 0;

  /// It tried and failed: a file it could not read or write, an input it
  /// could not convert, a step that broke. The output says which.
  static const int failure = 1;

  /// It was asked wrongly: an unknown subcommand or option, a missing
  /// argument. The usage goes to stderr.
  static const int usage = 2;

  /// It declined, or found something out of date: `--check` with changes
  /// pending (`init --check`, `plugins --check`), a target that is not empty,
  /// a tool it needs that is not installed. Nothing was changed.
  static const int refused = 3;

  /// It would have written over a file with other contents, and was not
  /// given `--overwrite`. Nothing was written. Only `convert` answers this.
  static const int wouldOverwrite = 4;

  /// Every code, with what it means, for the help text and the README.
  static const Map<int, String> meanings = <int, String>{
    ok: 'ok',
    failure: 'failed',
    usage: 'usage error',
    refused: 'refused, or out of date under --check',
    wouldOverwrite: 'would overwrite (convert)',
  };
}

/// The version of the `--json` output's shape, written in every document a
/// subcommand prints with `--json` as the envelope's `version`.
///
/// **Its own number, not the package's.** It moves only when the shape does:
/// a key added is a minor bump, and nothing is removed or retyped within a
/// major.
const int cliJsonVersion = 1;

/// [body] as a subcommand's `--json` document: the format envelope every
/// flutter3d JSON document starts with (`format` `f3d.cli`, `version`
/// [cliJsonVersion], `requires`, `generator`), then `command`, then the
/// subcommand's own keys, whose shapes [cliJsonBodies] lists.
Map<String, Object?> cliJson(String command, Map<String, Object?> body) =>
    <String, Object?>{
      'format': 'f3d.cli',
      'version': cliJsonVersion,
      'requires': const <String>[],
      'generator': 'flutter3d',
      'command': command,
      ...body,
    };

/// The keys each subcommand's `--json` document carries after `command`,
/// as `flutter3d help --surface` prints them and
/// `api/flutter3d_build.cli` commits them, so a key removed or renamed is a
/// change somebody reviews. `?` marks a key that may be absent; `[...]` a
/// list of the object that follows.
const Map<String, String> cliJsonBodies = <String, String>{
  'convert':
      '{output, dryRun, reports: [{input, format, outcome, error?, written, '
      'mapped, dropped, warnings}]}',
  'doctor': '{checks: [{name, status, detail, fix?}]}',
  'plugins':
      '{check, path, current? (with --check), written? (without), '
      'plugins: [{package, import, class}], excluded: [{package, import, '
      'class}], warnings}',
};

/// The subcommands, in the order `flutter3d help` lists them.
const List<String> cliCommands = <String>[
  'convert',
  'create',
  'init',
  'plugins',
  'migrate',
  'lights',
  'doctor',
  'help',
];

/// What `flutter3d` prints with no arguments or `help`.
const String flutter3dUsage =
    '''
Usage: flutter3d <command> [arguments]

Commands:
  convert   Bring models, materials and scenes from other tools in: glTF,
            OBJ, STL, PLY, USD, MaterialX, Unity prefabs and scenes, Godot
            scenes, and FBX and .blend through FBX2glTF or Blender.
  create    A new project (create project <dir>) or plugin
            (create plugin --kind <kind> --name <name>).
  init      Wire the build hook into an existing project.
  plugins   Write lib/plugins.g.dart from the dependencies' plugin markers,
            or check that it is current (--check).
  migrate   Move a project written against flutter3d 0.8 to 1.0.
  lights    Fewer lights for a level, judged by the pictures they make.
  doctor    Check the SDKs and the optional tools.
  help      This text, or a command's: flutter3d help <command>.

Exit codes:
  0  ok
  1  failed
  2  usage error
  3  refused, or out of date under --check
  4  would overwrite (convert)

--json, where a command takes it, prints one JSON document with
"format": "f3d.cli" and "version": $cliJsonVersion.

Every command also runs as `dart run flutter3d_build:<command>`.''';

/// What `flutter3d help plugins` prints.
const String pluginsUsage = '''
Usage: flutter3d plugins [--check] [--json]

Writes lib/plugins.g.dart: the plugins this project's dependencies declare
with a `flutter3d_plugins:` marker, less what this project's own pubspec
leaves out with `flutter3d_plugins: include:` or `exclude:` (a package, a
library such as flutter3d_post/motion.dart, or one class after a #).

  --check   Write nothing; exit 3 when lib/plugins.g.dart is missing or is
            not what the dependencies declare, 0 when it is current.
  --json    Print the result as JSON (format f3d.cli).''';

/// What `flutter3d help help` prints.
const String helpUsage = '''
Usage: flutter3d help [<command>]
       flutter3d help --surface   every command's help, as committed in
                                  api/flutter3d_build.cli''';

/// What `flutter3d help create` prints.
const String createUsage = '''
Usage: flutter3d create project <dir> [--name <package>]
       flutter3d create plugin --kind <kind> --name <name> [--target <dir>]
       flutter3d create --list

Exits 3 when the target directory is not empty.''';

/// `flutter3d convert`'s help.
const String convertUsage = '''
Usage: flutter3d convert <input...> [-o <dir>] [options]

Converts models, materials and scenes into the engine's formats. Each input
becomes ONE <name>.f3d bundle: the model with its lights and cameras, its
materials and textures, material language programs (.f3dmat), and its scene
as prefab documents, with the models a scene names carried inside. --split
writes the separate files instead; with it, each format becomes:

  glTF, GLB, OBJ+MTL, STL, PLY   -> <name>.f3d, materials/*.fmat
  .ply/.spz splat capture        -> <name>.f3dsplat
  FBX (FBX2glTF or Blender)      -> <name>.f3d via glTF
  .blend (Blender)               -> <name>.f3d via glTF
  USDA, USDZ (.usdc via usdcat)  -> <name>.f3d, materials/*.fmat,
                                    <name>.level.json with prefabs
  MaterialX .mtlx                -> materials/*.fmat, or *.f3dmat for a graph
  Unity .prefab, .unity          -> <name>.level.json with prefabs,
                                    models/*.f3d, materials/*.fmat
  Unity .mat                     -> materials/*.fmat
  Godot .tscn                    -> <name>.level.json with prefabs
  Godot .tres material           -> materials/*.fmat

An input may be a file, a directory (every recognised file under it) or a
glob ('assets/**.prefab', quoted so the shell leaves it alone). The format
is read from the extension, and from the first bytes when the extension
says nothing.

Options:
  -o, --output <dir>      Where to write (default: the current directory).
  --dry-run               Read everything, report what would be written, and
                          write nothing.
  --overwrite             Replace files that exist with different contents.
                          Without it the run writes nothing when any would be
                          replaced, and exits 4. A file that already holds
                          exactly what would be written is not a conflict.
  --asset-prefix <path>   What the paths a level document names start with
                          (default: the output directory as given, when it is
                          relative). Level paths are asset paths.
  --split                 Write the separate files listed above (.fmat,
                          .f3dmat, textures, models, .level.json) beside the
                          .f3d instead of one bundle per input.
  --no-materials          Do not write a model's materials as .fmat files.
  --report <file>         Also write the report as JSON.
  --json                  Print the report as JSON (format f3d.cli) instead
                          of text.
  --textures <family>     auto | bc | etc2 | universal | none, for the images
                          inside a .f3d (see dart run flutter3d_build:convert).
  --no-mips               No mip chains for compressed images.
  --lods <ratios>         Levels of detail, e.g. 0.5,0.25.
  --impostor              Bake an octahedral impostor per model.
  --chunks[=<triangles>]  Split large static meshes into culled clusters.
  -h, --help              Show this text.

Exit codes: 0 converted; 1 an input failed; 2 usage; 3 a needed external
tool (FBX2glTF, Blender, usdcat) is not installed; 4 an output exists with
different contents and --overwrite was not given.
''';

const String initUsage = '''
Usage: dart run flutter3d_build:init [options] [project-directory]

Writes hook/build.dart, a pubspec.yaml dev_dependencies: flutter3d_build
line, a pubspec.yaml flutter: assets: entry for the generated directory,
and a .gitignore line for it — everything ap-05's build hook needs to run
on every build. project-directory defaults to the current directory.

Options:
  --check      Report what a run would change, without changing it. Exits
               3 if anything is pending, 0 if nothing is.
  --force      Overwrite hook/build.dart even if its content does not
               match what init writes. Otherwise a hook a person has
               edited is left alone and reported instead of overwritten.
  -h, --help   Show this text.
''';

/// What `dart run flutter3d_build:lights` prints when it is asked wrongly.
const String lightsUsage = '''
usage: dart run flutter3d_build:lights --optimize <level.json> [options]

Fewer lights that light the level the way it is lit now. Every light is
drawn alone in software from the views; lights others already cover are
removed, close pairs are merged, and the rest are retuned, keeping only
changes whose picture stays close to the original.

  --poses <file.json>   where players stood: a JSON list of poses
                        ({"t", "p": [x, y, z], "y"}), as a game's Recorder
                        writes them while it plays a .f3drun back. May be
                        given more than once. Without one, the views are four
                        headings from every player spawn.
  --state <file.json>   a lighting state the level must look right
                        under: {"name": "noon", "lights": [...]}, the lights
                        written as the level writes them and never changed.
                        May be given more than once, and the level is then
                        judged under each; a state with no lights is night.
  -o, --out <path>      where to write the level; default: over the input
  --preview <dir>       write before.png and after.png of the first view
  --dry-run             say what would change and write no level
  --classes <names>     phone,web,desktop: write one level per device class
                        beside the output (level.phone.json, ...), each
                        optimised to its class's tolerance (the nearest
                        flutter3d_assets.yaml's lightDifference for the
                        class, or the preset's), and leave the level
                        itself alone
''';

/// What `flutter3d help migrate` prints.
const String migrateUsage = '''
Moves a project written against flutter3d 0.8 to 1.0.0-rc.1.

  dart pub global run flutter3d_build:migrate [options] <project dir>

  --dry-run           change a copy beside the project, report, remove it
  --data              lift the data files to the versions this build
                      writes, in place, instead of migrating the code;
                      reports `file: vN → vM` and what was not carried over
  --backup            with --data, keep each file as it was as
                      <file>.v<N>.bak
  --from <version>    the release the project is on (default 0.8)
  --no-pub-get        only the pubspec and the imports
  --lints-from <dir>  run flutter3d_lints:migrate from that checkout
''';

/// What `flutter3d help doctor` prints.
const String doctorUsage =
    'Usage: flutter3d doctor [--json]\n\n'
    'Checks the Dart and Flutter SDKs against the versions SUPPORT.md '
    'promises, and finds the optional programs: impellerc, glslangValidator '
    'and naga for building materials, FBX2glTF, Blender and usdcat for '
    'flutter3d convert. Run in a project, it also names the data files '
    'below the version this build writes, which `flutter3d migrate --data` '
    'lifts. Exits 1 when a required SDK is too old.\n\n'
    '  --json   Print the checks as JSON (format f3d.cli): {"checks": [...]}.';

/// The whole surface, as `flutter3d help --surface` prints it and
/// `api/flutter3d_build.cli` commits it: the top-level usage, then each
/// subcommand's own help under a `== <command> ==` line.
String cliSurface() {
  const usages = <String, String>{
    'convert': convertUsage,
    'create': createUsage,
    'init': initUsage,
    'plugins': pluginsUsage,
    'migrate': migrateUsage,
    'lights': lightsUsage,
    'doctor': doctorUsage,
    'help': helpUsage,
  };
  final sections = <String>[
    '== flutter3d ==\n$flutter3dUsage',
    for (final command in cliCommands)
      if (usages[command] case final String text)
        '== $command ==\n${text.trimRight()}',
    '== --json ==\n$_jsonBodies',
  ];
  return '${sections.join('\n\n')}\n';
}

/// [cliJsonBodies], a line a subcommand.
String get _jsonBodies => <String>[
  for (final MapEntry(:key, :value) in cliJsonBodies.entries) '$key $value',
].join('\n');
