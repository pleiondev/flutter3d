import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException, Registration;

import 'events.dart';
import 'host.dart';
import 'registration.dart';
import 'render_program.dart';

/// One named top-level section of a `.f3dplugin` document, read and
/// installed by the subsystem that owns what the section declares.
///
/// **The runtime that reads a data plugin does not know every subsystem.**
/// `effects` are particle effects, `physicalMaterials` are substances in the
/// material catalogue; the package that reads the document would otherwise
/// depend on every package a section names, and grow a dependency with each
/// new section. So a subsystem registers its sections in the engine's
/// [DataSectionRegistry], and the runtime hands each one what the document
/// wrote under its [name].
///
/// The life of a section, in order, each step refusing what it cannot take
/// before anything is installed:
///
/// 1. [read] when the document is read: what was written under [name], held
///    to the section's shape, or a [Flutter3dFormatException] saying what is
///    wrong;
/// 2. [resources]: the plugin's own files the section names, which the
///    loader reads with the plugin's others, through its permissions;
/// 3. [load], once those files are in memory: a document a file holds, read;
/// 4. [install], when the plugin is installed: into the registries of the
///    host, through the plugin's own view of them, so switching the plugin
///    off takes it out again.
///
/// What a step returns is the section's own business and is handed to the
/// next one as it was returned.
abstract base class DataSection {
  const DataSection();

  /// The key the section has in a document: `effects`.
  String get name;

  /// What a document that has this section names in its `requires`, so a
  /// build that does not read the section refuses the document rather than
  /// installing the plugin without it. Null for a section a build may
  /// ignore.
  String? get requirement => null;

  /// [DataSectionRead.written], what the document has under [name], read
  /// for the plugin the step's context names. Throws a
  /// [Flutter3dFormatException] for a section that is not the shape it
  /// should be.
  Object read(DataSectionRead step);

  /// What [read] returned, as the document writes it back: the same shape
  /// [read] takes.
  Object? write(Object section);

  /// The files of the plugin's own that [section] names, relative to its
  /// directory, in the order they are named.
  List<String> resources(Object section) => const <String>[];

  /// [DataSectionLoad.section] with the files it named in memory, read
  /// through [DataSectionContext.textOf]; the section itself when it names
  /// none.
  Object load(DataSectionLoad step) => step.section;

  /// Puts [DataSectionInstall.section], as [load] returned it, into
  /// [DataSectionInstall.host]'s registries. A registry the section needs
  /// and the engine does not have is a `PluginException`; what is left out
  /// on purpose — an effect on an engine that draws nothing — goes to
  /// [DataSectionContext.note].
  void install(DataSectionInstall step);
}

/// What [DataSection.read] is handed.
///
/// **One object per step, so a minor can hand a section more** without
/// breaking a section written against 1.0; what every step shares is
/// [context].
final class DataSectionRead {
  const DataSectionRead(this.written, {required this.context});

  /// What the document has under the section's name, as JSON decoded it.
  final Object? written;

  /// The plugin being read.
  final DataSectionContext context;
}

/// What [DataSection.load] is handed, for the reason [DataSectionRead]
/// gives.
final class DataSectionLoad {
  const DataSectionLoad(this.section, {required this.context});

  /// What [DataSection.read] returned.
  final Object section;

  /// The plugin being read, whose files are in memory now.
  final DataSectionContext context;
}

/// What [DataSection.install] is handed, for the reason [DataSectionRead]
/// gives.
final class DataSectionInstall {
  const DataSectionInstall(
    this.section, {
    required this.host,
    required this.context,
  });

  /// What [DataSection.load] returned.
  final Object section;

  /// The plugin's own view of the engine's registries.
  final PluginHost host;

  /// The plugin being installed.
  final DataSectionContext context;
}

/// What a [DataSection] is told about the plugin it is reading or
/// installing.
///
/// Made by the runtime that reads the document, never by a section.
final class DataSectionContext {
  const DataSectionContext({
    required this.plugin,
    this._textOf,
    this._eventName,
    this._numbersOf,
    this._note,
    this._renderProgram,
  });

  /// The plugin's id, which a name it brings is prefixed with:
  /// `<plugin>.<name>`.
  final String plugin;

  final String Function(String path)? _textOf;
  final String Function(String event)? _eventName;
  final List<double>? Function(BusEvent event)? _numbersOf;
  final void Function(String note)? _note;
  final RenderProgram? Function(String step)? _renderProgram;

  /// The program that drives the plugin's render step [step] (its name
  /// without the plugin's prefix) frame by frame — a `wasmRender` module of
  /// the document, made by the runtime that read it — or null when nothing
  /// drives it. Asked by the section that installs render steps, at
  /// install; the runtime counts a program nobody asked for as one whose
  /// step the document does not have.
  RenderProgram? renderProgram(String step) => _renderProgram?.call(step);

  /// The text of [path], one of the files [DataSection.resources] named.
  /// Throws a [StateError] before the files are read.
  String textOf(String path) =>
      (_textOf ??
      (String path) => throw StateError(
        'plugin "$plugin": $path is asked for before its files are read',
      ))(path);

  /// The name [event] is declared under on the bus: `<plugin>.<event>` for
  /// one of the plugin's own events, and the name as written for the
  /// engine's or another plugin's.
  String eventName(String event) => _eventName?.call(event) ?? event;

  /// The numbers [event] carries when one of a data plugin's systems
  /// published it, in order and as decimals; null for any other event.
  List<double>? numbersOf(BusEvent event) => _numbersOf?.call(event);

  /// Says what was left out of the install and why, for the plugin list to
  /// show beside the plugin.
  void note(String note) => _note?.call(note);
}

/// The sections a data plugin may have beyond the runtime's own, each read
/// by the subsystem that registered it.
///
/// **One per engine**, handed to the loop among its registries and to the
/// loader that reads documents for it. A subsystem registers its sections
/// with the application's assembly (`registry.register(effectsSection)`),
/// and a compiled plugin may teach the engine a section of its own in
/// `install`, which goes again when the plugin is switched off.
abstract base class DataSectionRegistry extends PluginRegistry {
  const DataSectionRegistry();

  /// Reads [section] from every data plugin read after this. Throws a
  /// [NameTakenException] when another section already has its name, and
  /// an [ArgumentError] when the name is one of the runtime's own keys.
  Registration register(DataSection section);

  /// The section registered under [name], or null.
  DataSection? operator [](String name);

  /// Every registered section's name, in the order they were registered.
  List<String> get names;

  @override
  DataSectionRegistry forPlugin(PluginScope scope);
}
