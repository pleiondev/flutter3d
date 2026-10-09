/// A server that is a table of tools over one session.
library;

import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;
import 'package:stream_channel/stream_channel.dart';

import 'argument_check.dart';
import 'project_tools.dart';
import 'tool_spec.dart';

/// One tool: what an agent is offered, and what calling it does to the
/// session.
///
/// **A pair rather than a table and a switch.** The obvious arrangement is a
/// list of tools for `tools/list` and a `switch` on the name in `tools/call`,
/// and the two drift the moment somebody adds one and forgets the other — an
/// offered tool that answers "no tool registered with that name", which
/// nothing notices because both halves compile. Here a tool that is offered is
/// a tool that has a body, because they are the same object.
final class OfferedTool<S, A> {
  const OfferedTool(this.spec, this.run);

  /// What `tools/list` hands the agent: a name, a sentence and a schema.
  final ToolSpec spec;

  /// What calling it does to [S]. `FutureOr`, so a tool that decodes a file
  /// and one that renames an object are the same kind of value.
  final FutureOr<A> Function(S session, Map<String, Object?> arguments) run;

  String get name => spec.name;

  /// This tool offered as [spec] instead, running the same body.
  OfferedTool<S, A> withSpec(ToolSpec spec) => OfferedTool<S, A>(spec, run);
}

/// One prompt: what `prompts/list` offers, and the text `prompts/get` hands
/// back — `ux-44`.
///
/// **A prompt here is advice, not a template with holes in it.** The thing an
/// agent that has never driven this editor needs is the order to do things in
/// — look before you edit, render before and after, check before you export —
/// and that is one paragraph that takes no arguments. A prompt with arguments
/// would be a tool, and there are a hundred and fifty of those already.
final class OfferedPrompt {
  const OfferedPrompt({
    required this.name,
    required this.description,
    required this.text,
  });

  final String name;
  final String description;

  /// What the host puts in front of the model, as one user message.
  final String text;
}

/// The name a tool is published under, `area.verb`, and what it does to the
/// world it is called on.
///
/// **One naming scheme across every server**: the thing acted on, a dot, and
/// what is done to it — `brush.add`, `capture.open`, `run.write`. A list of
/// two hundred tools sorts into groups an agent can read, and a plugin's
/// tools (`<plugin id>.<name>`) read the same way.
///
/// A server is handed these by the name its tools are written under; the
/// written name stays answerable as an alias until the next major release,
/// so a host config or a prompt that named it keeps working.
final class ToolName {
  const ToolName(this.name, [this.hints = ToolHints.writes]);

  /// The published name, `area.verb`.
  final String name;

  /// What a call does: [ToolHints.reads], [ToolHints.writes] or
  /// [ToolHints.destroys].
  final ToolHints hints;

  /// What a published name may be: lower-case words joined by dots, at least
  /// two of them; a word may be camel-cased or use `_` after its first letter.
  ///
  /// The area is a word like any other: `textureGraph.addNode` and
  /// `shapeKey.delete` are what the modelling server publishes.
  static final RegExp pattern = RegExp(
    r'^[a-z][A-Za-z0-9_]*(\.[a-z][A-Za-z0-9_]*)+$',
  );
}

/// The `_meta` key a server's tools, and its `initialize` result, carry
/// their schema version under.
const String schemaVersionMetaKey = 'flutter3d/schemaVersion';

/// The name of the tool every server offers to say what schema versions it
/// speaks.
const String schemaToolName = 'flutter3d.schema';

/// One call a [ToolTableServer] answered, as a watcher is told of it:
/// [ToolTableServer.onCall] with the server's own answer type,
/// [ToolTableServer.onProjectCall] with a project tool's [ToolResult].
///
/// **An object, so a call can say more later.** The hooks took four
/// positional arguments, and the next thing a feed wants to show (which
/// client called, whether the call was refused) would have broken every
/// watcher; a field added here does not.
final class AnsweredCall<A> {
  const AnsweredCall({
    required this.toolName,
    required this.arguments,
    required this.answer,
    required this.elapsed,
  });

  /// The tool called, by the name it was offered under.
  final String toolName;

  /// The arguments the call carried.
  final Map<String, Object?> arguments;

  /// What the tool answered.
  final A answer;

  /// How long the tool took to answer, by the wall clock.
  final Duration elapsed;
}

/// A server offering [tools] over one [session], every answer turned into a
/// result by [toResult].
///
/// **One session, one process, and no window** — the shape every server here
/// settled on: two writers on one undo stack, or on one run, is a different
/// and much harder program, and this is the half a suite can drive over a pair
/// of streams with nothing running for real behind them.
///
/// **Holds the protocol rather than being it.** The MCP library is pre-1.0
/// and its types appear in no signature here: a server takes a channel of
/// JSON lines, offers [ToolSpec]s and answers [ToolResult]s, and the wire
/// underneath is this class's business.
base class ToolTableServer<S, A> {
  ToolTableServer(
    StreamChannel<String> channel, {
    required this.session,
    required List<OfferedTool<S, A>> tools,
    required this.toResult,
    this.prompts = const <OfferedPrompt>[],
    required this.name,
    required this.version,
    required this.instructions,
    this.schemaVersion,
    Map<String, String> aliases = const <String, String>{},
    Map<String, ToolName> names = const <String, ToolName>{},
    this.refusal,
    this.pausedBecause,
    this.onCall,
    this.onInitialize,
    this.projectTools,
    this.onProjectCall,
  }) : tools = List<OfferedTool<S, A>>.unmodifiable(
         _published(tools, names, schemaVersion),
       ),
       aliases = Map<String, String>.unmodifiable(
         _aliasesOf(tools, aliases, names),
       ) {
    if (_namingProblem(names) case final String problem) {
      throw ArgumentError.value(names, 'names', problem);
    }
    if (_aliasProblem(this.tools, this.aliases) case final String problem) {
      throw ArgumentError.value(aliases, 'aliases', problem);
    }
    _wire = _Wire(channel, this);
  }

  late final _Wire<S, A> _wire;

  /// The state every tool acts on, for the life of the process.
  final S session;

  /// What an agent is offered, under the names they are published as, in
  /// the order `tools/list` gives them — [schemaToolName] after them.
  final List<OfferedTool<S, A>> tools;

  /// The name this server tells a client it is: `flutter3d.<area>`.
  final String name;

  /// The package's version, as `serverInfo` says it.
  final String version;

  /// What the host puts in front of the model before it calls anything.
  final String instructions;

  /// The version of what [tools] offer — their names, their input and output
  /// schemas and their hints — announced beside [version] in the
  /// `initialize` result's `serverInfo`, as `schemaVersion`, in its `_meta`,
  /// in every tool's `_meta`, and by [schemaToolName].
  ///
  /// **A number of its own, because an agent's host caches what it read.**
  /// The package version moves for a fixed bug in a tool body, which changes
  /// nothing a host has to read again; this moves only when the tool surface
  /// does, by the same rule as a version number — a new tool or a new
  /// optional argument is a minor, a removed tool or a new required argument
  /// a major. The snapshot in `api/<package>.mcp` records it, and
  /// `tool/structure` holds a change to the surface to a move of this.
  ///
  /// Null announces nothing, for a server outside this repository's promise.
  final String? schemaVersion;

  /// Old names of renamed tools, each to the name it is published under now.
  ///
  /// **A rename is a break for every agent prompt and every host config that
  /// names the old tool**, so a renamed tool keeps answering to its old name
  /// until the next major release. The alias is listed by `tools/list` with
  /// the current tool's schema and a description that opens by saying it is
  /// deprecated and what to call instead, and a call to it runs the current
  /// tool — through the same brake, argument check and watcher, which hears
  /// the current name.
  ///
  /// Every name a tool was written under and published under another (the
  /// `names` the constructor takes) is one of these. An alias that names no
  /// tool, or that is itself the name of a tool, is refused when the server
  /// is built: either would be a second door that leads somewhere other than
  /// where it says.
  final Map<String, String> aliases;

  /// The advice this server offers under `prompts/list` — `ux-44`. Empty
  /// for a server with nothing to say beyond its own tools.
  final List<OfferedPrompt> prompts;

  /// How an answer travels back — see `resultOf` and `pictureResultOf`.
  final ToolResult Function(A answer) toResult;

  /// A refusal, as the answer type this server speaks — `ux-43`.
  ///
  /// **Given rather than built here, because only the caller knows what an
  /// [A] is.** A server whose answers carry a picture has a null one to put
  /// in; one whose answers are a bare `(did, says)` has nothing to add. What
  /// this buys is that an argument refused before a tool ever runs travels
  /// back through [toResult] like every other answer — marked as an error,
  /// and carrying whatever machine-readable half that server attaches — so a
  /// misspelt key and a refused edit read the same way to whoever called.
  ///
  /// Null leaves the framework's own validation in place, which says the same
  /// thing as a JSON Schema path expression.
  final A Function(String says)? refusal;

  /// Why calls are not being answered right now, or null when they are —
  /// `ux-45`.
  ///
  /// **A person's own hand on the brake.** An agent editing a document
  /// somebody is working in is a second pair of hands, and the moment a
  /// person wants it to stop there is no way to ask: killing the process
  /// loses the session, and closing the window loses the work. This is asked
  /// before every call, so a paused agent is told why rather than left
  /// waiting — and being told is what lets it say so rather than retry.
  ///
  /// Null for every headless server: there is nobody there to press it.
  final String? Function()? pausedBecause;

  /// `tut-16`'s own hook, run after every call answers, whichever of [tools]
  /// it was — a caller with a screen open beside this server (`mcp-13n`'s
  /// `--mcp-port`) wants to show a live feed of what an agent is doing, and
  /// this is the one seam every call already passes through regardless of
  /// which tool it named. Null for every server that has nobody watching,
  /// which is every server this repository starts headless.
  final void Function(AnsweredCall<A> call)? onCall;

  /// `ux-05`'s own hook: a client has said hello, with the name it gave.
  ///
  /// **Distinct from [onCall], and a screen needs both.** An open port is not
  /// an agent: the live run found the modeller giving a third of its window
  /// to an agent panel and a contact sheet from the first frame, with nobody
  /// connected and nothing to show in either. `initialize` is the first
  /// moment there is somebody there, and it arrives whether or not that
  /// somebody ever calls a tool.
  ///
  /// Run before the answer goes back, and — like [onCall] — never allowed to
  /// fail it: whatever a watching screen does with the news is its own
  /// business and none of the client's.
  final void Function(String clientName)? onInitialize;

  /// The tools the project's plugins bring, offered after this server's own
  /// [tools] and [aliases] under their published names, `<plugin id>.<name>`
  /// — decision 19 of the plugin plan. Null offers none, which is every
  /// server this repository starts on its own: what `api/<package>.mcp`
  /// snapshots is a server built without them.
  ///
  /// **Kept in step while the server runs.** A plugin switched on or off
  /// adds or withdraws its tools, and the server registers or unregisters
  /// them, which tells the client its list changed.
  ///
  /// A call to one passes the same brake ([pausedBecause]) and the same
  /// argument check ([refuseArguments]) as a call to this server's own
  /// tools, and answers through [onProjectCall] rather than [onCall], whose
  /// answer is this server's own type. A project tool whose name is already
  /// one of this server's, or an alias, is not offered; [shadowedProjectTools]
  /// names it.
  final McpTools? projectTools;

  /// [onCall] for the [projectTools]: run after every call to one answers,
  /// and never allowed to fail it.
  final void Function(AnsweredCall<ToolResult> call)? onProjectCall;

  /// What `serverInfo` says: the name, the version and the schema version.
  Map<String, Object?> get serverInfo => <String, Object?>{
    'name': name,
    'version': version,
    'schemaVersion': ?schemaVersion,
  };

  /// Every schema version this server speaks right now: its own, under
  /// `server`, and each project namespace's that declared one.
  Map<String, Object?> get schemaVersions => <String, Object?>{
    'server': name,
    'schemaVersion': ?schemaVersion,
    'namespaces': <String, String>{...?projectTools?.schemaVersions},
  };

  /// The names of project tools not offered because this server already
  /// offers a tool or an alias of that name.
  List<String> get shadowedProjectTools => <String>[
    for (final ProjectTool t in projectTools?.tools ?? const <ProjectTool>[])
      if (_ownNames.contains(t.name)) t.name,
  ];

  /// Completes when the client has gone and the server has shut down.
  Future<void> get done => _wire.done;

  /// Stops answering and closes the channel.
  Future<void> shutdown() => _wire.shutdown();

  /// This server's own tool names and aliases.
  late final Set<String> _ownNames = <String>{
    for (final OfferedTool<S, A> t in tools) t.name,
    ...aliases.keys,
    schemaToolName,
  };

  /// The tool every server answers with its schema versions.
  ToolSpec get _schemaTool => ToolSpec(
    name: schemaToolName,
    description:
        'The schema versions this server speaks: its own, and each '
        'plugin namespace\'s that declared one. A host that cached the tool '
        'list reads it again when a version moved.',
    inputSchema: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
    outputSchema: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'server': <String, Object?>{'type': 'string'},
        'schemaVersion': <String, Object?>{'type': 'string'},
        'namespaces': <String, Object?>{
          'type': 'object',
          'additionalProperties': <String, Object?>{'type': 'string'},
        },
      },
      'required': <String>['server', 'namespaces'],
    },
    hints: const ToolHints(readOnly: true, idempotent: true),
    meta: <String, Object?>{schemaVersionMetaKey: ?schemaVersion},
  );

  /// Every tool `tools/list` offers of this server's own, aliases and
  /// [schemaToolName] included, as the snapshot reads them.
  List<ToolSpec> get offeredSpecs => <ToolSpec>[
    for (final OfferedTool<S, A> t in tools) t.spec,
    _schemaTool,
  ];
}

/// [tools] under the names [names] gives them, with the hints it gives and
/// [schemaVersion] in each one's `_meta`.
List<OfferedTool<S, A>> _published<S, A>(
  List<OfferedTool<S, A>> tools,
  Map<String, ToolName> names,
  String? schemaVersion,
) => <OfferedTool<S, A>>[
  for (final OfferedTool<S, A> t in tools)
    t.withSpec(
      t.spec.copyWith(
        name: names[t.name]?.name,
        hints: names[t.name]?.hints,
        meta: <String, Object?>{schemaVersionMetaKey: ?schemaVersion},
      ),
    ),
];

/// [aliases], pointed at published names, plus every written name [names]
/// publishes under another.
Map<String, String> _aliasesOf<S, A>(
  List<OfferedTool<S, A>> tools,
  Map<String, String> aliases,
  Map<String, ToolName> names,
) => <String, String>{
  for (final MapEntry(key: old, value: current) in aliases.entries)
    old: names[current]?.name ?? current,
  for (final OfferedTool<S, A> t in tools)
    if (names[t.name] case final ToolName published
        when published.name != t.name)
      t.name: published.name,
};

/// What is wrong with [names], or null when nothing is.
String? _namingProblem(Map<String, ToolName> names) {
  // A name may cover a tool this server offers only to some hosts, so one
  // that is not here is not a mistake; one published twice is.
  final seen = <String>{};
  for (final ToolName published in names.values) {
    if (!ToolName.pattern.hasMatch(published.name)) {
      return '`${published.name}` is not `area.verb`: lower-case words '
          'joined by dots';
    }
    if (!seen.add(published.name)) {
      return 'two tools are published as `${published.name}`';
    }
  }
  return null;
}

/// What `tools/list` says about [old], an alias of [current]: that it is
/// deprecated, what to call instead, and then [current]'s own description.
String _aliasDescription(String old, ToolSpec current) =>
    'Deprecated: `$old` is the old name of `${current.name}`, kept until the '
            'next major release — call `${current.name}`. '
            '${current.description ?? ''}'
        .trimRight();

/// What is wrong with [aliases] over [tools], or null when nothing is.
String? _aliasProblem<S, A>(
  List<OfferedTool<S, A>> tools,
  Map<String, String> aliases,
) {
  final Set<String> names = <String>{
    for (final OfferedTool<S, A> t in tools) t.name,
  };
  for (final MapEntry(key: String old, value: String current)
      in aliases.entries) {
    if (names.contains(old)) {
      return '`$old` is the name of a tool and cannot also be an alias';
    }
    if (!names.contains(current)) {
      return 'the alias `$old` names `$current`, which is not a tool here';
    }
  }
  return null;
}

/// The protocol's tool for [spec].
Tool _toolOf(ToolSpec spec) => Tool.fromMap(spec.toJson());

/// The protocol's result for [result].
CallToolResult _resultOf(ToolResult result) =>
    CallToolResult.fromMap(result.toJson());

/// The protocol server a [ToolTableServer] holds: everything that speaks
/// the wire, and nothing a caller sees.
base class _Wire<S, A> extends MCPServer with ToolsSupport, PromptsSupport {
  _Wire(super.channel, this._owner)
    : super.fromStreamChannel(
        implementation: Implementation.fromMap(_owner.serverInfo),
        instructions: _owner.instructions,
      );

  final ToolTableServer<S, A> _owner;

  /// The project tools offered now, by published name.
  final Map<String, ProjectTool> _offeredProjectTools = <String, ProjectTool>{};

  /// The listener on the project's tools, from [initialize] to [shutdown].
  Registration? _projectListener;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    try {
      _owner.onInitialize?.call(request.clientInfo.name);
    } catch (_) {}
    for (final OfferedPrompt offered in _owner.prompts) {
      addPrompt(
        Prompt(name: offered.name, description: offered.description),
        (GetPromptRequest request) => GetPromptResult(
          description: offered.description,
          messages: <PromptMessage>[
            PromptMessage(
              role: Role.user,
              content: Content.text(text: offered.text),
            ),
          ],
        ),
      );
    }
    for (final OfferedTool<S, A> offered in _owner.tools) {
      _register(offered.spec, offered);
    }
    for (final MapEntry(key: String old, value: String current)
        in _owner.aliases.entries) {
      final OfferedTool<S, A> offered = _owner.tools.firstWhere(
        (OfferedTool<S, A> t) => t.name == current,
      );
      _register(
        offered.spec.copyWith(
          name: old,
          description: _aliasDescription(old, offered.spec),
        ),
        offered,
      );
    }
    registerTool(
      _toolOf(_owner._schemaTool),
      (CallToolRequest call) => _resultOf(
        ToolResult(
          content: <ToolContent>[
            ToolText(
              '${_owner.name} speaks schema '
              '${_owner.schemaVersion ?? 'unversioned'}',
            ),
          ],
          structuredContent: _owner.schemaVersions,
        ),
      ),
      validateArguments: false,
    );
    if (_owner.projectTools case final McpTools project) {
      _syncProjectTools();
      _projectListener ??= project.listen(_syncProjectTools);
    }
    final InitializeResult result = await super.initialize(request);
    if (_owner.schemaVersion case final String version) {
      (result as Map<String, Object?>)['_meta'] = <String, Object?>{
        schemaVersionMetaKey: version,
      };
    }
    return result;
  }

  @override
  Future<void> shutdown() async {
    _projectListener?.cancel();
    _projectListener = null;
    await super.shutdown();
  }

  /// Registers the project tools not yet offered and unregisters those
  /// withdrawn, leaving the rest where they are.
  void _syncProjectTools() {
    final wanted = <String, ProjectTool>{
      for (final ProjectTool t
          in _owner.projectTools?.tools ?? const <ProjectTool>[])
        if (!_owner._ownNames.contains(t.name)) t.name: t,
    };
    for (final MapEntry(key: String name, value: ProjectTool offered)
        in _offeredProjectTools.entries.toList()) {
      if (identical(wanted[name], offered)) continue;
      unregisterTool(name);
      _offeredProjectTools.remove(name);
    }
    for (final MapEntry(key: String name, value: ProjectTool tool)
        in wanted.entries) {
      if (_offeredProjectTools.containsKey(name)) continue;
      _offeredProjectTools[name] = tool;
      _registerProject(tool);
    }
  }

  /// Registers [project], a plugin's tool, through the brake and the
  /// argument check this server's own tools pass.
  void _registerProject(ProjectTool project) {
    registerTool(_toolOf(project.spec), (CallToolRequest call) async {
      final Map<String, Object?> arguments =
          call.arguments ?? const <String, Object?>{};
      final String? refused =
          _owner.pausedBecause?.call() ??
          refuseArguments(project.spec, arguments);
      if (refused != null) {
        return _resultOf(ToolResult.text(refused, isError: true));
      }
      final Stopwatch? stopwatch = _owner.onProjectCall == null
          ? null
          : (Stopwatch()..start());
      final ToolResult result = await project.run(arguments);
      stopwatch?.stop();
      try {
        _owner.onProjectCall?.call(
          AnsweredCall<ToolResult>(
            toolName: project.name,
            arguments: arguments,
            answer: result,
            elapsed: stopwatch?.elapsed ?? Duration.zero,
          ),
        );
      } catch (_) {}
      return _resultOf(_checked(project.spec, result));
    }, validateArguments: false);
  }

  /// Registers [spec] — [offered]'s own, or an alias of it — to run
  /// [offered].
  void _register(ToolSpec spec, OfferedTool<S, A> offered) {
    registerTool(_toolOf(spec), (CallToolRequest call) async {
      final Map<String, Object?> arguments =
          call.arguments ?? const <String, Object?>{};
      // `ux-43`: checked here rather than by `registerTool`'s own
      // `validateArguments`, which is switched off below — see `refusal`
      // for why, and `argument_check.dart` for what it catches that the
      // framework's own pass does not.
      if (_owner.refusal case final A Function(String) asRefusal) {
        // `ux-45`: the brake first. A paused session refuses a call it
        // would otherwise have run, before it reads the arguments — a
        // complaint about a misspelt key would be a strange answer to
        // "you are paused".
        final String? paused = _owner.pausedBecause?.call();
        if (paused != null) {
          return _resultOf(_owner.toResult(asRefusal(paused)));
        }
        final String? wrong = refuseArguments(offered.spec, arguments);
        if (wrong != null) return _resultOf(_owner.toResult(asRefusal(wrong)));
      }
      // Null exactly when `onCall` is: a headless server (nobody
      // watching) never reads the clock at all, not even to throw the
      // answer away — see `repeatableStepExempt`'s own entry for this
      // file, `tool/structure/repository.dart`.
      final Stopwatch? stopwatch = _owner.onCall == null
          ? null
          : (Stopwatch()..start());
      final A answer = await offered.run(_owner.session, arguments);
      stopwatch?.stop();
      // **A watcher never fails a call.** `onCall` is somebody else's
      // screen, redrawn beside this server; whatever it does with the news
      // is its own business and none of the client's. `ux-02` found out
      // what the alternative costs: a re-sync inside this hook threw for an
      // object a device had refused, so the *answer* — already computed,
      // already correct — came back to the agent as a stack trace instead,
      // and did so again for every call after it.
      try {
        _owner.onCall?.call(
          AnsweredCall<A>(
            toolName: offered.name,
            arguments: arguments,
            answer: answer,
            elapsed: stopwatch?.elapsed ?? Duration.zero,
          ),
        );
      } catch (_) {}
      return _resultOf(_checked(offered.spec, _owner.toResult(answer)));
    }, validateArguments: _owner.refusal == null);
  }

  /// [result], held to the rule that a structured answer comes from a tool
  /// that declared its shape.
  ToolResult _checked(ToolSpec spec, ToolResult result) {
    assert(
      result.structuredContent == null || spec.outputSchema != null,
      '${spec.name} answered structuredContent without an outputSchema',
    );
    return result;
  }
}
