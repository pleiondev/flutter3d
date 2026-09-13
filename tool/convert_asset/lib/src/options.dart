/// The command line, parsed — kept apart from `bin/convert_asset.dart`
/// so a test can check what a line of arguments means without spawning
/// the process that reads them.
library;

/// One parsed invocation of `convert_asset`.
final class ConvertAssetOptions {
  const ConvertAssetOptions({
    required this.input,
    required this.format,
    required this.name,
  });

  /// The file to read.
  final String input;

  /// One of `glb`, `obj`, `stl`, `f3d` — not validated here; an unknown
  /// value is the caller's own `switch` to refuse, the same way an
  /// [ExportReport] format function would refuse one it does not
  /// recognise.
  final String format;

  /// The output files' own base name, before their extension.
  final String name;

  /// Parses [arguments], or returns null for anything [usage] would need
  /// to explain — a missing input, no `-f`, or `--textures` naming
  /// anything but `keep` (the only value this tool accepts; see the
  /// executable's own doc comment for why).
  static ConvertAssetOptions? parse(List<String> arguments) {
    String? input;
    String? format;
    String? name;
    var textures = 'keep';

    var i = 0;
    while (i < arguments.length) {
      final argument = arguments[i];
      switch (argument) {
        case '-f':
        case '--format':
          if (i + 1 >= arguments.length) return null;
          format = arguments[++i];
        case '-o':
        case '--output':
          if (i + 1 >= arguments.length) return null;
          name = arguments[++i];
        case '--textures':
          if (i + 1 >= arguments.length) return null;
          textures = arguments[++i];
        default:
          if (argument.startsWith('-')) return null;
          input ??= argument;
      }
      i++;
    }

    if (input == null || format == null) return null;
    if (textures != 'keep') return null;

    return ConvertAssetOptions(
      input: input,
      format: format,
      name: name ?? _baseNameOf(input),
    );
  }
}

/// [path]'s own file name, with its extension removed — `a/b/teapot.glb`
/// becomes `teapot`. A leading dot (a dotfile with no other `.`) is not
/// treated as the extension: `.gitignore` stays `.gitignore` rather than
/// becoming an empty name.
String _baseNameOf(String path) {
  final base = path.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? base : base.substring(0, dot);
}

const String usage = '''
Usage: convert_asset <input> -f <format> [--textures keep] [-o <name>]

  <format>   one of: glb, obj, stl, f3d
  <name>     base name for the output file(s); defaults to the input's own
  --textures keep   the only value this tool accepts today; see its own
                     doc comment for why "external" is not here yet
''';
