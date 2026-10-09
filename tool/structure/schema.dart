/// What a change to the tools a package offers an agent means for its version
/// number, read from two `.mcp` or two `.vm` snapshots.
///
/// **The same verdicts as `api.dart`, for a different kind of caller.** An
/// agent's host config names a tool, a prompt tells a model which arguments
/// it takes, and an editor attached to a running game calls an
/// `ext.flutter3d.*` extension by name — none of them compiled against
/// anything, so nothing fails until the call does. Decision 11 of
/// `tasks/1.0-stability.md` puts them under the same semver as the Dart API,
/// and this is the classifier that rule reads: plain Dart over text, so the
/// structure scan can run it before `pub get`, and `tool/api` imports it to
/// print the same verdict.
///
/// The formats it reads are the ones `tool/api/lib/schema_snapshot.dart`
/// writes:
///
/// ```text
/// # comment lines
///
/// server flutter3d_editor_mcp            <- one MCP server
///   schema 1.0.0                         <- the schema version it announces
///   alias place_box -> place             <- an old name kept for a renamed tool
///
/// tool place                             <- a tool of the server above
///   says Put a new thing in the level.   <- its description's first sentence
///   when game is OrderedGame             <- offered only to hosts where this holds
///   arg kind required {"enum":[…],"type":"string"}
///   arg at {"items":{"type":"number"},"type":"array"}
///   schema {"additionalProperties":false}  <- the rest of the input schema
///   hints readOnly idempotent            <- what a call does to the world
///   out {"properties":{…},"type":"object"} <- the structuredContent's shape
///
/// extension ext.flutter3d.timeline.scrubTo   <- a VM service extension
///   alias ext.flutter3d.timeline.seek    <- an old name kept for it
///   step int                             <- a parameter it reads, as a type
///   -> found step                        <- the keys of what it answers
///
/// event flutter3d.timeline.replayedUnderNewCode  <- a kind a game posts
/// ```
library;

import 'dart:convert';

import 'api.dart';

/// One block of a schema snapshot.
final class SchemaBlock {
  SchemaBlock(this.kind, this.name, this.server);

  /// `server`, `tool`, `extension` or `event`.
  final String kind;
  final String name;

  /// The server a tool belongs to; empty for everything else.
  final String server;

  /// The schema version a server announces.
  String? schemaVersion;

  /// A server's aliases, old name to current one; an extension's old names,
  /// each to the extension's own.
  final Map<String, String> aliases = <String, String>{};

  /// A tool's arguments, each to (required, its schema).
  final Map<String, ({bool required, Map<String, Object?> schema})> arguments =
      <String, ({bool required, Map<String, Object?> schema})>{};

  /// The condition a tool is offered under, as its server's source states
  /// it; null for a tool every host gets.
  String? when;

  /// The rest of a tool's input schema, beside `properties` and `required`.
  Map<String, Object?> rest = const <String, Object?>{};

  /// A tool's hints — `readOnly`, `destructive`, `idempotent`, `openWorld`.
  Set<String> hints = const <String>{};

  /// The schema of the `structuredContent` a tool answers with; null for a
  /// tool that answers in words and pictures only.
  Map<String, Object?>? output;

  /// An extension's parameter keys.
  final Set<String> keys = <String>{};

  /// An extension's parameters, each to the type it is parsed as; empty
  /// in a snapshot from before types were recorded.
  final Map<String, String> types = <String, String>{};

  /// The keys of the object an extension answers with; `*` among them when
  /// part of it is built where the snapshot cannot read.
  final Set<String> results = <String>{};
}

/// A snapshot's blocks, keyed `kind name` — `tool server/name` for a tool.
Map<String, SchemaBlock> parseSchema(String text) {
  final blocks = <String, SchemaBlock>{};
  SchemaBlock? current;
  var server = '';
  for (final line in text.split('\n')) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      final space = line.indexOf(' ');
      final kind = space < 0 ? line : line.substring(0, space);
      final name = space < 0 ? '' : line.substring(space + 1).trim();
      if (kind == 'server') server = name;
      current = SchemaBlock(kind, name, kind == 'tool' ? server : '');
      blocks[_key(current)] = current;
      continue;
    }
    final block = current;
    if (block == null) continue;
    final member = line.trim();
    final space = member.indexOf(' ');
    final word = space < 0 ? member : member.substring(0, space);
    final rest = space < 0 ? '' : member.substring(space + 1);
    switch ((block.kind, word)) {
      case ('server', 'schema'):
        block.schemaVersion = rest;
      case ('server', 'alias'):
        final parts = rest.split(' -> ');
        if (parts.length == 2) block.aliases[parts[0]] = parts[1];
      case ('tool', 'arg'):
        final cut = rest.indexOf(' ');
        final name = rest.substring(0, cut);
        var json = rest.substring(cut + 1);
        final required = json.startsWith('required ');
        if (required) json = json.substring('required '.length);
        block.arguments[name] = (
          required: required,
          schema: (jsonDecode(json) as Map).cast<String, Object?>(),
        );
      case ('tool', 'when'):
        block.when = rest;
      case ('tool', 'schema'):
        block.rest = (jsonDecode(rest) as Map).cast<String, Object?>();
      case ('tool', 'hints'):
        // `writes` is the snapshot saying "none of the four", an ordinary
        // edit, so a snapshot written before it said so compares equal.
        block.hints = rest.split(' ').toSet()..remove('writes');
      case ('tool', 'out'):
        block.output = (jsonDecode(rest) as Map).cast<String, Object?>();
      // An old name is an `ext.` name; a parameter is a bare key.
      case ('extension', 'alias') when rest.startsWith('ext.'):
        block.aliases[rest] = block.name;
      case ('extension', '->'):
        block.results.addAll(rest.split(' ').where((w) => w.isNotEmpty));
      case ('extension', _):
        block.keys.add(word);
        if (rest.isNotEmpty) block.types[word] = rest;
      default:
        break;
    }
  }
  return blocks;
}

String _key(SchemaBlock b) =>
    b.kind == 'tool' ? 'tool ${b.server}/${b.name}' : '${b.kind} ${b.name}';

/// Every difference between [before] and [after], classified.
///
/// The [ApiChange.library] of each is what it belongs to — a server's name,
/// or `vm` — and its subject the tool, extension or event a CHANGELOG entry
/// has to name. What counts as a break is decided where each case is, as in
/// `api.dart`, because that list is the contract `CONTRIBUTING.md` points at.
List<ApiChange> classifySchema(String before, String after) {
  final now = parseSchema(after);
  final changes = <ApiChange>[];
  void add(String where, String subject, String what, Bump bump) =>
      changes.add(ApiChange(where, subject, what, bump));
  final old = _followRenamedServers(parseSchema(before), now, add);

  // Servers: a server gone takes every tool it had; its tools say so below.
  for (final key in <String>{...old.keys, ...now.keys}.toList()..sort()) {
    final a = old[key];
    final b = now[key];
    final block = (b ?? a)!;
    final where = switch (block.kind) {
      'server' => block.name,
      'tool' => block.server,
      _ => 'vm',
    };
    switch (block.kind) {
      case 'server':
        if (a == null) {
          add(where, block.name, 'a new server', Bump.minor);
        } else if (b == null) {
          add(where, block.name, 'the server is gone', Bump.major);
        } else {
          for (final alias in a.aliases.keys) {
            if (!b.aliases.containsKey(alias)) {
              add(
                where,
                alias,
                'the alias `$alias` for `${a.aliases[alias]}` is gone: '
                'everything that still calls the old name breaks',
                Bump.major,
              );
            }
          }
        }
      case 'tool':
        if (a == null) {
          add(where, block.name, 'a new tool', Bump.minor);
          continue;
        }
        if (b == null) {
          // Renamed with its old name kept as an alias: the old name still
          // answers, with the new tool's schema — compare against that.
          final server = now['server ${a.server}'];
          final target = server?.aliases[a.name];
          final renamed = target == null
              ? null
              : now['tool ${a.server}/$target'];
          if (renamed == null) {
            add(
              where,
              a.name,
              server == null
                  ? 'gone with its server'
                  : 'removed, or renamed without keeping its old name as an '
                        'alias',
              Bump.major,
            );
            continue;
          }
          add(
            where,
            a.name,
            'renamed to `$target`, its old name kept as an alias',
            Bump.minor,
          );
          _classifyInput(where, a.name, a, renamed, add);
          continue;
        }
        _classifyInput(where, a.name, a, b, add);
      case 'extension':
        // Renamed with its old name kept as an alias: the old name still
        // answers, as the new extension does — compare against that.
        final renamed = a == null || b != null
            ? null
            : now.values
                  .where(
                    (SchemaBlock e) =>
                        e.kind == 'extension' && e.aliases.containsKey(a.name),
                  )
                  .firstOrNull;
        if (a != null && b != null) {
          for (final alias in a.aliases.keys) {
            if (!b.aliases.containsKey(alias)) {
              add(
                where,
                alias,
                'the alias `$alias` for `${block.name}` is gone: everything '
                'that still calls the old name breaks',
                Bump.major,
              );
            }
          }
        }
        final target = b ?? renamed;
        if (a == null) {
          add(where, block.name, 'a new extension', Bump.minor);
        } else if (target == null) {
          add(
            where,
            block.name,
            'the extension is gone, or renamed without keeping its old name '
            'as an alias',
            Bump.major,
          );
        } else {
          if (b == null) {
            add(
              where,
              a.name,
              'renamed to `${target.name}`, its old name kept as an alias',
              Bump.minor,
            );
          }
          for (final k in a.keys.difference(target.keys)) {
            add(
              where,
              block.name,
              'no longer reads `$k`: a caller sending it is ignored',
              Bump.major,
            );
          }
          for (final k in target.keys.difference(a.keys)) {
            // The VM service hands every parameter over as a string, and an
            // extension decides for itself what a missing one means, so the
            // snapshot cannot tell a required key from an optional one. It is
            // counted as what decision 11 allows — an addition — and
            // CONTRIBUTING says a new key has to have a default.
            add(where, block.name, 'reads a new key `$k`', Bump.minor);
          }
          for (final k in a.keys.intersection(target.keys)) {
            final was = a.types[k];
            final now = target.types[k];
            if (was != null && now != null && was != now) {
              add(
                where,
                block.name,
                'reads `$k` as $now, not $was: a caller sending what it '
                'used to is refused',
                Bump.major,
              );
            }
          }
          for (final k in a.results.difference(target.results)) {
            if (k == '*') continue;
            add(
              where,
              block.name,
              'no longer answers `$k`: a caller reading it finds nothing',
              Bump.major,
            );
          }
          for (final k in target.results.difference(a.results)) {
            add(where, block.name, 'answers `$k` too', Bump.minor);
          }
        }
      case 'event':
        if (a == null) {
          add(where, block.name, 'a new event', Bump.minor);
        } else if (b == null) {
          add(
            where,
            block.name,
            'the event is no longer posted: whoever waits for it waits '
            'forever',
            Bump.major,
          );
        }
    }
  }
  return changes;
}

typedef _Add =
    void Function(String where, String subject, String what, Bump bump);

/// [old] with each server that now announces another name filed under that
/// name, so its tools are compared with the tools they became.
///
/// **A server's announced name is not what a host calls it by** — a host's
/// configuration names the command it starts — so a new name is an addition,
/// not a break, as long as the server still answers every tool it did. A
/// server that is gone from [now] is taken to be the new one whose tools and
/// aliases hold every one of its tools; a server no new one covers is gone.
Map<String, SchemaBlock> _followRenamedServers(
  Map<String, SchemaBlock> old,
  Map<String, SchemaBlock> now,
  _Add add,
) {
  final renamed = <String, String>{};
  final servers = <SchemaBlock>[
    for (final b in now.values)
      if (b.kind == 'server') b,
  ];
  for (final a in old.values) {
    if (a.kind != 'server' || now.containsKey('server ${a.name}')) continue;
    final tools = <String>{
      for (final t in old.values)
        if (t.kind == 'tool' && t.server == a.name) t.name,
      ...a.aliases.keys,
    };
    for (final b in servers) {
      if (old.containsKey('server ${b.name}')) continue;
      final answers = <String>{
        for (final t in now.values)
          if (t.kind == 'tool' && t.server == b.name) t.name,
        ...b.aliases.keys,
      };
      if (tools.isNotEmpty && answers.containsAll(tools)) {
        renamed[a.name] = b.name;
        add(
          b.name,
          b.name,
          'the server announces itself as `${b.name}`, not `${a.name}`',
          Bump.minor,
        );
        break;
      }
    }
  }
  if (renamed.isEmpty) return old;
  final out = <String, SchemaBlock>{};
  for (final block in old.values) {
    final server = renamed[block.kind == 'server' ? block.name : block.server];
    if (server == null) {
      out[_key(block)] = block;
      continue;
    }
    final moved =
        SchemaBlock(
            block.kind,
            block.kind == 'server' ? server : block.name,
            block.kind == 'tool' ? server : '',
          )
          ..schemaVersion = block.schemaVersion
          ..when = block.when
          ..rest = block.rest
          ..hints = block.hints
          ..output = block.output;
    moved.aliases.addAll(block.aliases);
    moved.arguments.addAll(block.arguments);
    moved.keys.addAll(block.keys);
    out[_key(moved)] = moved;
  }
  return out;
}

/// A tool's input, old against new: what a call written against [a] does
/// when [b] answers it.
void _classifyInput(
  String where,
  String tool,
  SchemaBlock a,
  SchemaBlock b,
  _Add add,
) {
  switch ((a.when, b.when)) {
    case (null, final String now):
      add(
        where,
        tool,
        'now offered only when $now: a host where it does not hold loses it',
        Bump.major,
      );
    case (final String was, null):
      add(where, tool, 'no longer offered only when $was', Bump.minor);
    case (final String was, final String now) when was != now:
      add(
        where,
        tool,
        'offered when $now instead of when $was: a host where only the old '
        'condition holds loses it',
        Bump.major,
      );
    default:
      break;
  }
  for (final name in <String>{
    ...a.arguments.keys,
    ...b.arguments.keys,
  }.toList()..sort()) {
    final was = a.arguments[name];
    final now = b.arguments[name];
    if (was == null) {
      add(
        where,
        tool,
        now!.required
            ? 'a new required argument `$name`: every existing call lacks it'
            : 'a new optional argument `$name`',
        now.required ? Bump.major : Bump.minor,
      );
      continue;
    }
    if (now == null) {
      add(
        where,
        tool,
        'the argument `$name` is gone: a call passing it is refused or '
        'ignored',
        Bump.major,
      );
      continue;
    }
    if (!was.required && now.required) {
      add(where, tool, '`$name` is now required', Bump.major);
    } else if (was.required && !now.required) {
      add(where, tool, '`$name` is no longer required', Bump.minor);
    }
    _classifyValue('$tool.$name', was.schema, now.schema, (w, b) {
      add(where, tool, w, b);
    });
  }
  _classifyValue('$tool (the input)', a.rest, b.rest, (w, bump) {
    add(where, tool, w, bump);
  });
  if (a.hints.difference(b.hints).isNotEmpty ||
      b.hints.difference(a.hints).isNotEmpty) {
    // A hint tells a host whether to ask a person first; no call a host
    // makes stops working when one moves.
    add(
      where,
      tool,
      'its hints are ${b.hints.isEmpty ? 'none' : b.hints.join(' ')}, not '
      '${a.hints.isEmpty ? 'none' : a.hints.join(' ')}',
      Bump.minor,
    );
  }
  switch ((a.output, b.output)) {
    case (null, null):
      break;
    case (null, _):
      add(
        where,
        tool,
        'declares the shape of its structured answer',
        Bump.minor,
      );
    case (_, null):
      add(
        where,
        tool,
        'no longer declares the shape of its structured answer: a caller '
        'reading a field cannot rely on it',
        Bump.major,
      );
    case (final Map<String, Object?> was, final Map<String, Object?> now):
      _classifyOutput('$tool (the answer)', was, now, (w, bump) {
        add(where, tool, w, bump);
      });
  }
}

/// A tool's answer, old against new — the other way round from its input:
/// a caller *reads* this, so a field taken away or retyped is a break and a
/// field added is not.
void _classifyOutput(
  String at,
  Map<String, Object?> a,
  Map<String, Object?> b,
  void Function(String what, Bump bump) add,
) {
  if (jsonEncode(a['type']) != jsonEncode(b['type'])) {
    add('$at changed type: ${a['type']} -> ${b['type']}', Bump.major);
    return;
  }
  final p0 = (a['properties'] as Map?)?.cast<String, Object?>() ?? const {};
  final p1 = (b['properties'] as Map?)?.cast<String, Object?>() ?? const {};
  final r0 = <Object?>{...?a['required'] as List?};
  final r1 = <Object?>{...?b['required'] as List?};
  for (final name in <String>{...p0.keys, ...p1.keys}.toList()..sort()) {
    final x = p0[name];
    final y = p1[name];
    if (x == null) {
      add('$at.$name is a new field', Bump.minor);
    } else if (y == null) {
      add('$at.$name is gone', Bump.major);
    } else {
      if (r0.contains(name) && !r1.contains(name)) {
        add('$at.$name may now be absent', Bump.major);
      }
      _classifyOutput(
        '$at.$name',
        (x as Map).cast<String, Object?>(),
        (y as Map).cast<String, Object?>(),
        add,
      );
    }
  }
  if (a['items'] case final Map<Object?, Object?> i0) {
    if (b['items'] case final Map<Object?, Object?> i1) {
      _classifyOutput(
        '$at[]',
        i0.cast<String, Object?>(),
        i1.cast<String, Object?>(),
        add,
      );
    }
  }
}

/// Keys of a JSON Schema whose value is a lower bound: raising one refuses a
/// value it used to take.
const Set<String> _lowerBounds = <String>{
  'minimum',
  'exclusiveMinimum',
  'minItems',
  'minLength',
  'minProperties',
};

/// Keys whose value is an upper bound: lowering one refuses a value too.
const Set<String> _upperBounds = <String>{
  'maximum',
  'exclusiveMaximum',
  'maxItems',
  'maxLength',
  'maxProperties',
};

/// Keys that change nothing a call may send.
const Set<String> _prose = <String>{'description', 'title', 'default'};

/// One value's schema, old against new. Everything here is about what a
/// caller may *send*, so a schema that takes less than it did is a break
/// and one that takes more is an addition.
void _classifyValue(
  String at,
  Map<String, Object?> a,
  Map<String, Object?> b,
  void Function(String what, Bump bump) add,
) {
  for (final key in <String>{...a.keys, ...b.keys}.toList()..sort()) {
    if (_prose.contains(key)) continue;
    final was = a[key];
    final now = b[key];
    if (jsonEncode(was) == jsonEncode(now)) continue;
    switch (key) {
      case 'type':
        add('$at changed type: $was -> $now', Bump.major);
      case 'enum':
        final before = <Object?>{...?was as List?};
        final after = <Object?>{...?now as List?};
        if (was == null) {
          add('$at is narrowed to the values $after', Bump.major);
        } else if (now == null) {
          add('$at takes any value, not only $before', Bump.minor);
        } else if (before.difference(after).isNotEmpty) {
          add(
            '$at no longer takes ${before.difference(after).join(', ')}',
            Bump.major,
          );
        } else {
          add(
            '$at takes ${after.difference(before).join(', ')} too',
            Bump.minor,
          );
        }
      case _ when _lowerBounds.contains(key) || _upperBounds.contains(key):
        final lower = _lowerBounds.contains(key);
        final x = (was as num?)?.toDouble();
        final y = (now as num?)?.toDouble();
        final narrower = y != null && (x == null || (lower ? y > x : y < x));
        add(
          '$at $key: ${was ?? 'none'} -> ${now ?? 'none'}',
          narrower ? Bump.major : Bump.minor,
        );
      case 'items':
        _classifyValue(
          '$at[]',
          (was as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
          (now as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
          add,
        );
      case 'properties':
        final p0 = (was as Map?)?.cast<String, Object?>() ?? const {};
        final p1 = (now as Map?)?.cast<String, Object?>() ?? const {};
        final r1 = <Object?>{...?b['required'] as List?};
        for (final name in <String>{...p0.keys, ...p1.keys}.toList()..sort()) {
          final x = p0[name];
          final y = p1[name];
          if (x == null) {
            final required = r1.contains(name);
            add(
              required
                  ? '$at.$name is a new required field'
                  : '$at.$name is a new optional field',
              required ? Bump.major : Bump.minor,
            );
          } else if (y == null) {
            add('$at.$name is gone', Bump.major);
          } else {
            _classifyValue(
              '$at.$name',
              (x as Map).cast<String, Object?>(),
              (y as Map).cast<String, Object?>(),
              add,
            );
          }
        }
      case 'required':
        final r0 = <Object?>{...?was as List?};
        final r1 = <Object?>{...?now as List?};
        final p0 = (a['properties'] as Map?) ?? const {};
        // A field that is new and required is reported with `properties`.
        final newlyRequired = r1
            .difference(r0)
            .where((Object? n) => p0.containsKey(n));
        for (final name in newlyRequired) {
          add('$at.$name is now required', Bump.major);
        }
        for (final name in r0.difference(r1)) {
          add('$at.$name is no longer required', Bump.minor);
        }
      case 'additionalProperties':
        final closed = now == false;
        add(
          '$at ${closed ? 'no longer takes' : 'now takes'} fields it does not '
          'name',
          closed ? Bump.major : Bump.minor,
        );
      default:
        // `pattern`, `format`, `const`, `anyOf` and the rest: a constraint
        // that arrives or moves is read as a narrowing, one that leaves as a
        // widening — the snapshot cannot prove a moved pattern takes more.
        add(
          '$at $key: ${jsonEncode(was)} -> ${jsonEncode(now)}',
          now == null ? Bump.minor : Bump.major,
        );
    }
  }
}

/// [changes] as a person reads them, grouped by what they belong to.
String describeSchemaChanges(List<ApiChange> changes) => describeApiChanges(
  changes,
).replaceAll(RegExp(r'^library ', multiLine: true), '');

/// The schema version each server of [snapshot] announces, by server name.
Map<String, String> schemaVersions(String snapshot) => <String, String>{
  for (final b in parseSchema(snapshot).values)
    if (b.kind == 'server' && b.schemaVersion != null) b.name: b.schemaVersion!,
};

// ----------------------------------------------------------------- proofs

/// The proof that the schema classifier fires on what breaks a caller and
/// stays quiet on what does not, as (detector, what went wrong). Empty when
/// it works. `proveDetectorsWork` runs it with the API proofs.
///
/// Invented tools on purpose, for the reason `proveApiDetectorsWork` gives.
List<(String, String)> proveSchemaDetectorsWork() {
  final broken = <(String, String)>[];
  const server = 'server s\n  schema 1.0.0\n';
  Bump verdict(String before, String after) =>
      requiredBump(classifySchema('$server\n$before', '$server\n$after'));
  void expect(Bump got, Bump want, String fixture) {
    if (got != want) {
      broken.add(('schema classifier', 'said ${got.name} for $fixture'));
    }
  }

  const tool =
      'tool go\n  says Goes.\n'
      '  arg to required {"type":"string"}\n'
      '  arg speed {"maximum":10,"type":"number"}\n'
      '  arg mode {"enum":["walk","run"],"type":"string"}\n';

  // Breaks.
  expect(verdict(tool, ''), Bump.major, 'a tool removed');
  expect(
    verdict(tool, tool.replaceFirst('tool go', 'tool move')),
    Bump.major,
    'a tool renamed with no alias',
  );
  expect(
    verdict(tool, '$tool  arg why required {"type":"string"}\n'),
    Bump.major,
    'a required argument added',
  );
  expect(
    verdict(
      tool,
      tool.replaceFirst('  arg speed {"maximum":10,"type":"number"}\n', ''),
    ),
    Bump.major,
    'an argument removed',
  );
  expect(
    verdict(tool, tool.replaceFirst('"type":"number"', '"type":"string"')),
    Bump.major,
    "an argument's type changed",
  );
  expect(
    verdict(tool, tool.replaceFirst('["walk","run"]', '["walk"]')),
    Bump.major,
    'an enum narrowed',
  );
  expect(
    verdict(tool, tool.replaceFirst('"maximum":10', '"maximum":5')),
    Bump.major,
    'a maximum lowered',
  );
  expect(
    verdict(tool, tool.replaceFirst('arg speed {', 'arg speed required {')),
    Bump.major,
    'an optional argument made required',
  );
  expect(
    requiredBump(
      classifySchema('$server  alias walk -> go\n\n$tool', '$server\n$tool'),
    ),
    Bump.major,
    'an alias dropped',
  );
  expect(
    requiredBump(
      classifySchema('extension ext.p.go\n  step\n', 'extension ext.p.go\n'),
    ),
    Bump.major,
    'a VM extension key dropped',
  );
  expect(
    requiredBump(classifySchema('event p.done\n', '')),
    Bump.major,
    'an event no longer posted',
  );
  expect(
    requiredBump(
      classifySchema('extension ext.p.go\n', 'extension ext.p.move\n'),
    ),
    Bump.major,
    'a VM extension renamed with no alias',
  );
  expect(
    requiredBump(
      classifySchema(
        'extension ext.p.move\n  alias ext.p.go\n',
        'extension ext.p.move\n',
      ),
    ),
    Bump.major,
    'a VM extension alias dropped',
  );

  // Additions, and what moves nothing.
  expect(
    verdict(tool, '$tool  arg why {"type":"string"}\n'),
    Bump.minor,
    'an optional argument added',
  );
  expect(
    verdict(tool, '$tool\ntool stop\n  says Stops.\n'),
    Bump.minor,
    'a tool added',
  );
  expect(
    requiredBump(
      classifySchema(
        '$server\n$tool',
        '$server  alias go -> move\n\n'
            '${tool.replaceFirst('tool go', 'tool move')}',
      ),
    ),
    Bump.minor,
    'a tool renamed with its old name kept as an alias',
  );
  expect(
    verdict(tool, tool.replaceFirst('["walk","run"]', '["walk","run","fly"]')),
    Bump.minor,
    'an enum widened',
  );
  expect(
    verdict(tool, tool.replaceFirst('says Goes.', 'says Goes somewhere.')),
    Bump.none,
    'a description reworded',
  );
  expect(
    verdict(
      tool,
      tool.replaceFirst(
        '{"maximum":10,',
        '{"description":"how fast","maximum":10,',
      ),
    ),
    Bump.none,
    'an argument described',
  );
  expect(
    requiredBump(
      classifySchema('extension ext.p.go\n', 'extension ext.p.go\n  step\n'),
    ),
    Bump.minor,
    'a VM extension reads a new key',
  );
  expect(
    requiredBump(
      classifySchema(
        'extension ext.p.go\n  step int\n  -> found\n',
        'extension ext.p.move\n  alias ext.p.go\n  step int\n  -> found\n',
      ),
    ),
    Bump.minor,
    'a VM extension renamed with its old name kept as an alias',
  );

  // The CHANGELOG names a broken tool the way it names a broken type.
  final unnamed = unnamedBreaks(
    classifySchema('$server\n$tool', server),
    '\n- **Breaking: `go` is gone.** Use `move`.\n',
  );
  if (unnamed.isNotEmpty) {
    broken.add(('schema changelog', 'found $unnamed unnamed beside `go`'));
  }
  if (schemaVersions(server)['s'] != '1.0.0') {
    broken.add(('schema versions', 'read ${schemaVersions(server)}'));
  }
  return broken;
}
