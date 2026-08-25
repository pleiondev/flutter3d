/// Command-line surface for `convert_asset.dart`: usage text and argument
/// parsing, kept apart from the conversion itself so each can be read on its
/// own.
const String usage = '''
Usage: convert_asset <model> [-o <output.f3d>]

Converts a glTF, GLB or OBJ model into the engine's .f3d container. Without -o
the output sits beside the input with the extension replaced.
''';

final class ConvertAssetOptions {
  const ConvertAssetOptions(this.input, this.output);

  final String input;
  final String output;

  static ConvertAssetOptions? parse(List<String> arguments) {
    String? input;
    String? output;

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '-o' || argument == '--output') {
        if (i + 1 >= arguments.length) return null;
        output = arguments[++i];
      } else if (argument.startsWith('-')) {
        return null;
      } else if (input == null) {
        input = argument;
      } else {
        return null;
      }
    }

    if (input == null) return null;
    return ConvertAssetOptions(input, output ?? _defaultOutput(input));
  }

  static String _defaultOutput(String input) {
    final dot = input.lastIndexOf('.');
    final slash = input.lastIndexOf('/');
    if (dot > slash) return '${input.substring(0, dot)}.f3d';
    return '$input.f3d';
  }
}
