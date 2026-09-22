/// What is wrong with a tool call's arguments, said the way a refusal is said
/// everywhere else here — `ux-43`.
///
/// **A wrong argument used to be a silent one.** `select {ids: [1]}` was
/// accepted, did nothing, and answered "nothing selected"; the agent that made
/// the call had spelled `objects` wrong and had no way to find that out, so it
/// tried the same call again with a different id. `dart_mcp` validates against
/// the schema on its own, but it does not know the key was never offered — an
/// unknown property is allowed by JSON Schema unless a schema says otherwise —
/// and what it says about the failures it does find is a path expression:
/// ``Value `x` is not of type `int` at path #root["id"]``.
///
/// So this checks both halves and says them the way this repository says every
/// other refusal: what the caller asked for, why it cannot be, and what the
/// alternative is. `"id" is a whole number, not "3.5"` is a sentence somebody
/// can act on; the path expression is a sentence somebody has to decode first.
library;

import 'package:dart_mcp/server.dart';

/// Why [arguments] are not a call to [tool], or null when they are.
String? refuseArguments(Tool tool, Map<String, Object?> arguments) {
  final ObjectSchema schema = tool.inputSchema;
  final Map<String, Schema> properties =
      schema.properties ?? const <String, Schema>{};

  // **Unknown keys first, because they are the mistake that used to pass.**
  // A misspelt key is not a type error and not a missing one: every other
  // field is fine, the call runs, and the argument the caller meant to give
  // simply is not there.
  for (final String key in arguments.keys) {
    if (properties.containsKey(key)) continue;
    return properties.isEmpty
        ? '${tool.name} takes no arguments, and was given "$key"'
        : '${tool.name} does not take "$key". It takes '
              '${_list(properties.keys)}';
  }

  final List<ValidationError> errors = schema.validate(arguments);
  if (errors.isEmpty) return null;
  return '${tool.name}: ${_sentence(errors.first, schema, arguments)}';
}

/// One validation failure, in words.
///
/// The first failure only: a caller fixes one thing and calls again, and a
/// list of six complaints about one malformed argument is six chances to fix
/// the wrong one.
String _sentence(
  ValidationError error,
  ObjectSchema schema,
  Map<String, Object?> arguments,
) {
  final List<String> path = error.path;
  final String field = path.isEmpty ? 'the arguments' : '"${path.last}"';
  final Schema? at = _schemaAt(schema, path);
  // What was actually sent, quoted back. **A refusal that does not repeat the
  // value is a refusal a caller has to take on trust** — and the caller that
  // sent "potato" for a profile is usually a caller that thinks it sent
  // something else.
  final Object? sent = _valueAt(arguments, path);

  switch (error.error) {
    case ValidationErrorType.requiredPropertyMissing:
      // The path names the object, not the missing key, so the key itself
      // comes out of the details `dart_mcp` wrote.
      return error.details ?? 'something required is missing';
    case ValidationErrorType.enumValueNotAllowed:
      final Iterable<String>? values = _valuesOf(at);
      return values == null
          ? '$field is not one of the values it takes, and $sent is not one'
          : '$field is one of ${_list(values)}, not ${_quoted(sent)}';
    case ValidationErrorType.typeMismatch:
      return '$field is ${_typeOf(at)}, not ${_quoted(sent)}';
    case ValidationErrorType.minItemsNotMet:
    case ValidationErrorType.maxItemsExceeded:
      final int? exactly = _exactItems(at);
      return exactly == null
          ? '$field has the wrong number of items'
          : '$field takes exactly $exactly numbers';
    case ValidationErrorType.minimumNotMet:
    case ValidationErrorType.exclusiveMinimumNotMet:
    case ValidationErrorType.maximumExceeded:
    case ValidationErrorType.exclusiveMaximumExceeded:
      return '$field is out of range — ${error.details ?? 'see the schema'}';
    default:
      // Everything else keeps `dart_mcp`'s own words rather than being
      // guessed at: a sentence this file invented for a case it has never
      // seen would be a worse answer than an accurate awkward one.
      return '$field — ${error.details ?? error.error.name}';
  }
}

/// The schema [path] points at, or null when the walk does not reach one.
Schema? _schemaAt(Schema schema, List<String> path) {
  Schema? at = schema;
  for (final String step in path) {
    final Map<String, Object?> raw = at! as Map<String, Object?>;
    final Object? properties = raw['properties'];
    final Object? items = raw['items'];
    if (properties is Map && properties[step] != null) {
      at = properties[step] as Schema;
    } else if (items != null && int.tryParse(step) != null) {
      at = items as Schema;
    } else {
      return null;
    }
  }
  return at;
}

/// What [arguments] actually hold at [path], or null when the walk runs out.
Object? _valueAt(Object? arguments, List<String> path) {
  Object? at = arguments;
  for (final String step in path) {
    final int? index = int.tryParse(step);
    if (at is Map && at.containsKey(step)) {
      at = at[step];
    } else if (at is List && index != null && index >= 0 && index < at.length) {
      at = at[index];
    } else {
      return null;
    }
  }
  return at;
}

/// A value as it should appear inside a sentence: a word in quotes, a number
/// bare, and nothing at all as "nothing".
String _quoted(Object? value) => switch (value) {
  null => 'nothing',
  final String word => '"$word"',
  _ => '$value',
};

Iterable<String>? _valuesOf(Schema? schema) {
  if (schema == null) return null;
  final Object? values = (schema as Map<String, Object?>)['enum'];
  return values is Iterable ? values.cast<String>() : null;
}

/// `minItems` and `maxItems` when they agree — the shape every vector and
/// matrix argument here has.
int? _exactItems(Schema? schema) {
  if (schema == null) return null;
  final Map<String, Object?> raw = schema as Map<String, Object?>;
  final Object? min = raw['minItems'];
  final Object? max = raw['maxItems'];
  return min is int && min == max ? min : null;
}

/// What a schema wants, in the words a person uses.
String _typeOf(Schema? schema) =>
    switch ((schema as Map<String, Object?>?)?['type']) {
      'integer' => 'a whole number',
      'number' => 'a number',
      'string' => 'a word',
      'boolean' => 'true or false',
      'array' => 'a list',
      'object' => 'an object',
      _ => 'not that shape',
    };

String _list(Iterable<String> words) {
  final List<String> all = words.toList();
  if (all.isEmpty) return 'nothing';
  if (all.length == 1) return all.single;
  return '${all.take(all.length - 1).join(', ')} or ${all.last}';
}
