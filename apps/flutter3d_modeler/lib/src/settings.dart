/// What a person chose once and expects to find again next launch.
///
/// **One document for every setting, rather than a file per row that wants
/// one.** `ux-09` exists because the rows after it — two navigation schemes,
/// three keymap presets, how `G`/`R`/`S` start, which workspace, which
/// language, whether Home shows at launch — each say "a setting", and seven
/// rows each inventing their own storage is seven ways to spell the same
/// read, seven defaults to disagree about, and a Settings screen that has to
/// know all of them. This is the one place; a new setting is a field here and
/// a row on the screen.
///
/// **Kept through the same [Storage] [RecentModels] already uses**, for its
/// reasons: the directory is per platform, a read that finds nothing is a
/// first launch rather than a failure, and a write goes through a temporary
/// and a rename so a crash cannot leave half a document.
///
/// **A value that cannot be read comes back as the default and is not
/// reported.** A settings file written by a newer build, hand-edited into
/// nonsense, or truncated by a full disk is a bad day for one preference, not
/// a reason to refuse to start — and the failure a person actually sees then
/// is a setting that went back to how it shipped, which is both survivable
/// and obvious.
library;

import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart' show Storage, defaultStorage;

import 'recent_projects.dart' show RecentModels;

/// Which way the camera is driven — `ux-04`'s own two schemes.
///
/// **Named for what they do rather than after another product.** A person
/// choosing between "Blender" and "Maya" is being asked which program they
/// used last rather than which behaviour they want, and somebody who has used
/// neither is being asked nothing at all.
enum NavigationScheme {
  /// The middle button orbits, Shift and it pans, the wheel zooms; Alt with
  /// the left button stands in for a middle button a laptop has not got, and
  /// two fingers on a trackpad orbit.
  middleMouseOrbit,

  /// A left drag on empty space orbits unless a drag tool is armed; a box
  /// comes from the Select tool or `B`; the right button held is free-look.
  leftDragOrbit;

  String get id => switch (this) {
    NavigationScheme.middleMouseOrbit => 'middle-mouse-orbit',
    NavigationScheme.leftDragOrbit => 'left-drag-orbit',
  };

  /// What the Settings screen shows, in English. The localised label is the
  /// screen's own business — see `ux-22` — and this stays readable where a
  /// stored document or a log is being read by hand.
  String get label => switch (this) {
    NavigationScheme.middleMouseOrbit => 'Middle-mouse orbit',
    NavigationScheme.leftDragOrbit => 'Left-drag orbit',
  };

  static NavigationScheme? byId(String? id) {
    for (final NavigationScheme it in NavigationScheme.values) {
      if (it.id == id) return it;
    }
    return null;
  }
}

/// Which set of keys is live — `ux-10`'s own three presets.
enum KeymapPreset {
  /// This application's own, with the collisions the review found fixed.
  standard,

  /// The keys somebody arriving from a modelling package of that school
  /// already has in their hands: `G`/`R`/`S`, `Tab`, numpad views.
  modalKeys,

  /// The other school: `W`/`E`/`R`, `Q` to select, `F` to frame, Alt to
  /// navigate.
  toolKeys;

  String get id => switch (this) {
    KeymapPreset.standard => 'standard',
    KeymapPreset.modalKeys => 'modal-keys',
    KeymapPreset.toolKeys => 'tool-keys',
  };

  String get label => switch (this) {
    KeymapPreset.standard => 'Default',
    KeymapPreset.modalKeys => 'Modal keys',
    KeymapPreset.toolKeys => 'Tool keys',
  };

  static KeymapPreset? byId(String? id) {
    for (final KeymapPreset it in KeymapPreset.values) {
      if (it.id == id) return it;
    }
    return null;
  }
}

/// How a transform begins — `ux-11`'s own pair.
enum TransformStart {
  /// The modal opens on the key press, takes the pointer, and `X`/`Y`/`Z`
  /// constrain it from that moment.
  modalOnPress,

  /// The key arms the tool and the drag that follows does the work, which is
  /// what this application did before there was a choice.
  armThenDrag;

  String get id => switch (this) {
    TransformStart.modalOnPress => 'modal-on-press',
    TransformStart.armThenDrag => 'arm-then-drag',
  };

  String get label => switch (this) {
    TransformStart.modalOnPress => 'Modal on press',
    TransformStart.armThenDrag => 'Arm, then drag',
  };

  static TransformStart? byId(String? id) {
    for (final TransformStart it in TransformStart.values) {
      if (it.id == id) return it;
    }
    return null;
  }
}

/// Which set of screens the mode switcher offers — `ux-37`'s own workspaces.
enum Workspace {
  /// Object, Material and Scene: what "open a model, paint it, export it"
  /// needs and nothing past it. The default.
  essential,

  /// Everything the application has, Mesh and Animation included.
  full;

  String get id => switch (this) {
    Workspace.essential => 'essential',
    Workspace.full => 'full',
  };

  String get label => switch (this) {
    Workspace.essential => 'Essential',
    Workspace.full => 'Full',
  };

  static Workspace? byId(String? id) {
    for (final Workspace it in Workspace.values) {
      if (it.id == id) return it;
    }
    return null;
  }
}

/// Everything a person has chosen, as one value.
///
/// Immutable, with [copyWith], so a screen can show a pending change without
/// the rest of the application seeing it until it is saved — and so two
/// readers can never disagree about what the settings are halfway through a
/// write.
final class ModelerSettings {
  const ModelerSettings({
    this.navigation = NavigationScheme.middleMouseOrbit,
    this.keymap = KeymapPreset.standard,
    this.transformStart = TransformStart.armThenDrag,
    this.workspace = Workspace.essential,
    this.language,
    this.showHomeAtLaunch = true,
    this.saveWithHistory = true,
    this.quickSetupDone = false,
    this.snapMove = 0.1,
    this.snapTurnDegrees = 15,
    this.snapScale = 0.1,
    this.propertiesWidth = 250,
  });

  /// How the camera is driven.
  final NavigationScheme navigation;

  /// Which keys are live.
  final KeymapPreset keymap;

  /// How `G`/`R`/`S` begin.
  ///
  /// Defaults to what the application already did, so an existing person's
  /// hands are not retrained by an upgrade; Quick Setup is where the other
  /// one is offered.
  final TransformStart transformStart;

  /// Which screens the mode switcher offers.
  final Workspace workspace;

  /// The language code the interface is shown in — `ru` or `en` — or null for
  /// whatever the system says, which is what a first launch gets.
  final String? language;

  /// Whether the Home screen opens at launch — `ux-42`'s own row. On by
  /// default: a person who has just installed a modeller has no file open and
  /// nothing to look at but a cube.
  final bool showHomeAtLaunch;

  /// Whether a project is written with its own undo history in it.
  ///
  /// On, because the alternative is a save that silently drops what a person
  /// could still have undone. The review found this asked as a dialog on
  /// every save, which is a question with the same answer every time.
  final bool saveWithHistory;

  /// Whether the one-page setup has been through once — `ux-42` shows it on a
  /// first launch and never again.
  final bool quickSetupDone;

  /// How coarse a held snap is, per kind of transform — `ux-11`.
  ///
  /// **Settings rather than three constants in `transform_modal.dart`.** The
  /// steps every modeller ships with are a tenth of a unit, fifteen degrees
  /// and a tenth of a factor, and they are right until somebody is working at
  /// a scale where they are not: a millimetre part wants a millimetre step,
  /// and an architectural scene wants a quarter metre. The chips the viewport
  /// shows during a transform read these, so what the modifier will do is
  /// legible before it is held.
  final double snapMove;

  /// In degrees, because that is what a person types. `TransformModal` takes
  /// radians and the conversion happens where the two meet.
  final double snapTurnDegrees;

  final double snapScale;

  /// How wide the properties panel is, in logical pixels — `ux-27`.
  ///
  /// Remembered because it is a choice about the window a person makes once
  /// and expects to find again, the same as which keys are live: dragging a
  /// panel back to the width you work at on every launch is the kind of
  /// thing people stop doing and then work narrow instead.
  final double propertiesWidth;

  ModelerSettings copyWith({
    NavigationScheme? navigation,
    KeymapPreset? keymap,
    TransformStart? transformStart,
    Workspace? workspace,
    String? language,
    bool clearLanguage = false,
    bool? showHomeAtLaunch,
    bool? saveWithHistory,
    bool? quickSetupDone,
    double? snapMove,
    double? snapTurnDegrees,
    double? snapScale,
    double? propertiesWidth,
  }) => ModelerSettings(
    navigation: navigation ?? this.navigation,
    keymap: keymap ?? this.keymap,
    transformStart: transformStart ?? this.transformStart,
    workspace: workspace ?? this.workspace,
    language: clearLanguage ? null : (language ?? this.language),
    showHomeAtLaunch: showHomeAtLaunch ?? this.showHomeAtLaunch,
    saveWithHistory: saveWithHistory ?? this.saveWithHistory,
    quickSetupDone: quickSetupDone ?? this.quickSetupDone,
    snapMove: snapMove ?? this.snapMove,
    snapTurnDegrees: snapTurnDegrees ?? this.snapTurnDegrees,
    snapScale: snapScale ?? this.snapScale,
    propertiesWidth: propertiesWidth ?? this.propertiesWidth,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'navigation': navigation.id,
    'keymap': keymap.id,
    'transformStart': transformStart.id,
    'workspace': workspace.id,
    if (language != null) 'language': language,
    'showHomeAtLaunch': showHomeAtLaunch,
    'saveWithHistory': saveWithHistory,
    'quickSetupDone': quickSetupDone,
    'snapMove': snapMove,
    'snapTurnDegrees': snapTurnDegrees,
    'snapScale': snapScale,
    'propertiesWidth': propertiesWidth,
  };

  /// What [json] says, with the default standing in for anything it does not
  /// say or says wrongly — see the library comment for why that is not an
  /// error.
  factory ModelerSettings.fromJson(Map<String, Object?> json) {
    const ModelerSettings fallback = ModelerSettings();
    bool flag(String key, bool otherwise) {
      final Object? value = json[key];
      return value is bool ? value : otherwise;
    }

    // A cast rather than a check would throw on a document where one value is
    // the wrong *type* — a number where an id belongs, an object where a
    // string does — which is a shape a newer build, or a hand edit, really
    // does produce, and which the library comment promises costs one
    // preference rather than the launch.
    String? text(String key) {
      final Object? value = json[key];
      return value is String ? value : null;
    }

    // A step of zero or less is not a step: it would divide by zero the
    // moment the modifier was held. A document that says so gets the default
    // rather than the launch getting an exception.
    double step(String key, double otherwise) {
      final Object? value = json[key];
      if (value is! num) return otherwise;
      final double read = value.toDouble();
      return read.isFinite && read > 0 ? read : otherwise;
    }

    final String? language = text('language');
    return ModelerSettings(
      navigation:
          NavigationScheme.byId(text('navigation')) ?? fallback.navigation,
      keymap: KeymapPreset.byId(text('keymap')) ?? fallback.keymap,
      transformStart:
          TransformStart.byId(text('transformStart')) ??
          fallback.transformStart,
      workspace: Workspace.byId(text('workspace')) ?? fallback.workspace,
      language: language != null && language.isNotEmpty ? language : null,
      showHomeAtLaunch: flag('showHomeAtLaunch', fallback.showHomeAtLaunch),
      saveWithHistory: flag('saveWithHistory', fallback.saveWithHistory),
      quickSetupDone: flag('quickSetupDone', fallback.quickSetupDone),
      snapMove: step('snapMove', fallback.snapMove),
      snapTurnDegrees: step('snapTurnDegrees', fallback.snapTurnDegrees),
      snapScale: step('snapScale', fallback.snapScale),
      propertiesWidth: step('propertiesWidth', fallback.propertiesWidth),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModelerSettings &&
      other.navigation == navigation &&
      other.keymap == keymap &&
      other.transformStart == transformStart &&
      other.workspace == workspace &&
      other.language == language &&
      other.showHomeAtLaunch == showHomeAtLaunch &&
      other.saveWithHistory == saveWithHistory &&
      other.quickSetupDone == quickSetupDone &&
      other.snapMove == snapMove &&
      other.snapTurnDegrees == snapTurnDegrees &&
      other.snapScale == snapScale &&
      other.propertiesWidth == propertiesWidth;

  @override
  int get hashCode => Object.hash(
    navigation,
    keymap,
    transformStart,
    workspace,
    language,
    showHomeAtLaunch,
    saveWithHistory,
    quickSetupDone,
    snapMove,
    snapTurnDegrees,
    snapScale,
    propertiesWidth,
  );
}

/// The settings document on disk.
final class SettingsStore {
  /// The same application name [RecentModels] uses, deliberately: one
  /// directory per application, and taking the string from there rather than
  /// spelling it again is what stops a later hand giving the settings a
  /// directory of their own by accident.
  SettingsStore({Storage? storage})
    : storage = storage ?? defaultStorage(RecentModels.appName);

  /// Beside `recent.json`, in the same per-platform directory.
  static const String name = 'settings.json';

  final Storage storage;

  /// What is stored, or the defaults on a first launch — and on a document
  /// that will not parse, which is the same thing as far as a person can
  /// tell.
  ModelerSettings read() {
    final String? text = storage.read(name);
    if (text == null) return const ModelerSettings();
    try {
      final Object? json = jsonDecode(text);
      if (json is! Map<String, Object?>) return const ModelerSettings();
      return ModelerSettings.fromJson(json);
    } on FormatException {
      return const ModelerSettings();
    }
  }

  /// Writes [settings], and says whether it managed to.
  ///
  /// The boolean is answered rather than swallowed because the Settings
  /// screen is the one place a person has actually asked for something to be
  /// remembered — unlike the recent list, which is a convenience nobody
  /// requested — and a preference that silently did not stick is worse than
  /// one that says so.
  bool write(ModelerSettings settings) => storage.write(
    name,
    const JsonEncoder.withIndent('  ').convert(settings.toJson()),
  );
}
