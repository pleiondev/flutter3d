import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import '../screens/credits.dart' show Credit;

/// What the game layer's widgets say, in the player's language.
///
/// **Every default string a widget here would otherwise have typed in
/// English.** The settings panel, the rebinding rows, the privacy questions,
/// "tap to play again", the credits heading, the share strip, the pedals and
/// the photo mode's key hints read their words from here, so a game in Russian
/// is a game in Russian down to the gear's tooltip. A widget that takes a
/// string parameter still takes it, and a game that passes one says its own
/// words.
///
/// **Installed like Flutter's own**, beside them in the app's
/// `localizationsDelegates`:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: const <LocalizationsDelegate<Object>>[
///     Flutter3dGameLocalizations.delegate,
///     ...GlobalMaterialLocalizations.delegates,
///   ],
///   supportedLocales: Flutter3dGameLocalizations.supportedLocales,
/// );
/// ```
///
/// Without it, [of] answers in English, so a widget pumped in a test or an
/// app that never thought about languages still reads.
///
/// **English and Russian ship.** Another language is a subclass overriding
/// what it translates, handed out by a delegate of the game's own; every
/// member here has an English body, so a member added in a minor release does
/// not break it.
base class Flutter3dGameLocalizations {
  /// English, which is also what every other language falls back to.
  const Flutter3dGameLocalizations();

  /// The words for [locale]: Russian for `ru`, English for anything else.
  factory Flutter3dGameLocalizations.forLocale(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => const _Russian(),
        _ => english,
      };

  /// The English words, for a caller with no [BuildContext].
  static const Flutter3dGameLocalizations english =
      Flutter3dGameLocalizations();

  /// The delegate an app lists in `localizationsDelegates`.
  static const LocalizationsDelegate<Flutter3dGameLocalizations> delegate =
      _Delegate();

  /// The languages that ship.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// The words for [context]'s locale, or [english] when the app installed
  /// no [delegate].
  static Flutter3dGameLocalizations of(BuildContext context) =>
      Localizations.of<Flutter3dGameLocalizations>(
        context,
        Flutter3dGameLocalizations,
      ) ??
      english;

  /// The language this speaks, as a locale's language code.
  String get languageCode => 'en';

  // ── The settings panel ────────────────────────────────────────────────────

  String get settings => 'Settings';
  String get controls => 'Controls';
  String get resetControls => 'Reset controls';
  String get accessibility => 'Accessibility';
  String get cameraMotion => 'Camera motion';
  String get colorVision => 'Colour vision';

  /// The choices of the colour-vision row: none, then the three kinds of
  /// colour blindness a correction is made for.
  List<String> get colorVisionChoices => const <String>[
    'Off',
    'Protan',
    'Deutan',
    'Tritan',
  ];

  String get highContrast => 'High contrast';
  String get holdToSprint => 'Hold to sprint';
  String get colors => 'Colours';
  String get mouse => 'Mouse';
  String get lookSpeed => 'Look speed';
  String get invertVerticalLook => 'Invert vertical look';

  /// The gamepad section's heading, saying when no pad is connected.
  String gamepad({required bool connected}) =>
      connected ? 'Gamepad' : 'Gamepad (none connected)';

  String get deadZone => 'Dead zone';
  String get settingsNotSaved =>
      'These settings could not be saved, and will be lost when the game '
      'closes. The disk or the browser’s storage is full.';
  String get backToTheGame => 'Back to the game';

  /// A volume slider's heading for the mixer bus called [bus].
  String volume(String bus) => switch (bus) {
    'master' => 'master',
    'music' => 'music',
    'sfx' => 'effects',
    _ => bus,
  };

  /// A colour row's swatch, for a screen reader: the game's own colour at
  /// [index] nought, a numbered alternative otherwise.
  String colorChoice(String label, int index) =>
      index == 0 ? '$label, as the game has it' : '$label, $index';

  // ── Rebinding ─────────────────────────────────────────────────────────────

  String get pressAKeyOrButton => 'press a key or a button';
  String get boundToNothing => 'nothing';

  /// A binding row as a screen reader says it.
  String boundTo(String action, String bound) => '$action, bound to $bound';

  /// What an action is called, by its message id: an `ActionDeclaration`'s
  /// label, or the action's name when it has none.
  ///
  /// The engine's own actions are said here; an id this does not know is a
  /// game's, and comes back as it is unless the game's own words answer it
  /// first (`ActionBindingsSection.actionLabel`).
  String actionLabel(String id) => switch (id) {
    'forward' || 'moveForward' => 'forward',
    'back' || 'moveBack' => 'back',
    'left' || 'moveLeft' => 'left',
    'right' || 'moveRight' => 'right',
    'jump' => 'jump',
    'sprint' => 'sprint',
    'use' => 'use',
    'look' => 'look',
    'move' => 'move',
    _ => id,
  };

  /// What a composite's part is called after its action's name.
  String part(CompositePart part) => switch (part) {
    CompositePart.negative => '−',
    CompositePart.positive => '+',
    CompositePart.up => 'up',
    CompositePart.down => 'down',
    CompositePart.left => 'left',
    CompositePart.right => 'right',
  };

  /// The line under the controls after a rebind took [source] from
  /// [action]: "`J` was jump's."
  String conflict(String source, String action) => '$source was $action’s.';

  /// A sensitivity slider's label: the action, on the device.
  String sensitivity(String action, String on) => '$action, $on';

  String invertVertically(String action, String on) =>
      'Invert $action vertically, $on';
  String invertHorizontally(String action, String on) =>
      'Invert $action horizontally, $on';
  String invert(String action, String on) => 'Invert $action, $on';

  /// What to call [source] on screen — a key's label, `pad face.south`,
  /// `mouse`, `touch stick`.
  ///
  /// The **identifier** is what gets saved and `key:32` is not a thing
  /// anybody can read, so this is the one place that translates — and only
  /// for showing, never for storing. A pad button keeps its position name,
  /// because that is what it is: `face.south` is where the button sits, and
  /// there is no way to know what is printed on it.
  String source(InputSource source) {
    if (source == InputSource.none) return boundToNothing;
    if (source == InputSource.pointerMotion) return mouseMotion;
    if (source.device == 'pointer') {
      return mouseButton(int.tryParse(source.id.substring('pointer:'.length)));
    }
    if (source.device == 'touch') {
      return '$touchPrefix ${source.id.substring('touch:'.length)}';
    }
    if (source.id.startsWith(InputSource.padPrefix)) {
      return '$padPrefix ${source.id.substring(InputSource.padPrefix.length)}';
    }
    if (!source.id.startsWith('key:')) return source.id;
    final id = int.tryParse(source.id.substring(4));
    if (id == null) return source.id;
    final named = keyName(id);
    if (named != null) return named;
    final label = LogicalKeyboardKey.findKeyByKeyId(id)?.keyLabel ?? '';
    return label.trim().isEmpty ? source.id : label;
  }

  /// The mouse's motion, as a source.
  String get mouseMotion => 'mouse';

  /// A mouse button; [button] null for one this cannot name.
  String mouseButton(int? button) => switch (button) {
    0 => 'left mouse button',
    1 => 'right mouse button',
    _ => 'mouse button ${button ?? '?'}',
  };

  String get touchPrefix => 'touch';
  String get padPrefix => 'pad';

  /// The name of a key whose label is not a thing to put on screen, by its
  /// [LogicalKeyboardKey.keyId], or null for a key whose label will do.
  ///
  /// **`LogicalKeyboardKey.debugName` would have answered all of these and is
  /// deliberately not used**: it is stripped in a release build, so a panel
  /// built on it reads perfectly in development and shows nothing to a
  /// player. `keyLabel` is the supported one, and for space it is a space.
  String? keyName(int keyId) => _englishKeys[keyId];

  // ── Your data ─────────────────────────────────────────────────────────────

  String get yourData => 'Your data';
  String get cloudSaves => 'Cloud saves';
  String get cloudSavesExplained =>
      'Keeps your run on the save server too, so another device can carry '
      'on from it.';
  String get noSaveServer =>
      'This build has no save server; your run stays on this device.';
  String get sendMyRuns => 'Send my runs';
  String get sendMyRunsExplained =>
      'Sends what you pressed in each level you finish, with no name, so the '
      'makers can see where levels are too hard.';
  String get answerNotKept => 'That answer could not be saved on this device.';
  String get whichRun => 'Which run do you want?';
  String get onThisDevice => 'On this device';
  String get inTheCloud => 'In the cloud';
  String get later => 'Later';
  String get theClouds => 'The cloud’s';
  String get thisDevices => 'This device’s';

  /// One of the two runs offered: [where] it is, and the level and the time
  /// played in it, or none.
  String runLine(String where, {String? level, String? played}) =>
      level == null ? '$where: none' : '$where: $level, $played in';

  // ── The screens around play ───────────────────────────────────────────────

  String get tapToPlayAgain => 'Tap to play again';

  /// The credits' heading.
  String get art => 'Art';

  /// The ending's credits heading.
  String get artInThisGame => 'Art in this game';

  /// One credit, as a screen reads it out.
  String creditLine(Credit credit) {
    if (!credit.isTraced) {
      return '${credit.work} — author unknown, licence untraced';
    }
    final changed = credit.modified ? ', modified' : '';
    return '${credit.work} by ${credit.author} — ${credit.license}$changed';
  }

  /// The settings gear's tooltip, for the button a game draws in its own HUD
  /// to open the settings overlay; no widget here draws that button.
  String get openSettings => settings;

  // ── Sharing a run ─────────────────────────────────────────────────────────

  String get shareThisRun => 'Share this run';
  String get aFriendsCode => 'A friend’s code';
  String get openTheirRun => 'Race it';

  // ── Touch ─────────────────────────────────────────────────────────────────

  String get throttle => 'throttle';
  String get brake => 'brake';
  String get handbrake => 'handbrake';

  // ── Photo mode ────────────────────────────────────────────────────────────

  String get takingThePicture => 'Taking the picture…';

  /// The photo bar's first line.
  String photoMode({required String filter, String? exposure}) =>
      'Photo mode · filter: $filter · ${exposure ?? 'game exposure'}';

  /// The keys of a photo mode whose walking keys fly the camera and whose
  /// Space and C take it up and down.
  String get photoWalkingKeys =>
      'WASD fly · Space/C up and down · Shift faster · [ ] filter · '
      ', . tilt · − = zoom · Enter 2× · Shift+Enter 4× · P back';

  /// The photo bar's exposure dials.
  String get photoExposureKeys =>
      '1 2 aperture · 3 4 shutter · 5 6 ISO · 0 the game’s exposure';

  // ── The heads-up display ──────────────────────────────────────────────────

  /// The speedometer's unit.
  String get kilometersPerHour => 'km/h';
}

final Map<int, String> _englishKeys = <int, String>{
  LogicalKeyboardKey.space.keyId: 'Space',
  LogicalKeyboardKey.shiftLeft.keyId: 'Left Shift',
  LogicalKeyboardKey.shiftRight.keyId: 'Right Shift',
  LogicalKeyboardKey.controlLeft.keyId: 'Left Ctrl',
  LogicalKeyboardKey.controlRight.keyId: 'Right Ctrl',
  LogicalKeyboardKey.altLeft.keyId: 'Left Alt',
  LogicalKeyboardKey.altRight.keyId: 'Right Alt',
  LogicalKeyboardKey.escape.keyId: 'Escape',
  LogicalKeyboardKey.tab.keyId: 'Tab',
  LogicalKeyboardKey.enter.keyId: 'Enter',
  LogicalKeyboardKey.arrowUp.keyId: 'Up',
  LogicalKeyboardKey.arrowDown.keyId: 'Down',
  LogicalKeyboardKey.arrowLeft.keyId: 'Left',
  LogicalKeyboardKey.arrowRight.keyId: 'Right',
};

final Map<int, String> _russianKeys = <int, String>{
  LogicalKeyboardKey.space.keyId: 'Пробел',
  LogicalKeyboardKey.shiftLeft.keyId: 'Левый Shift',
  LogicalKeyboardKey.shiftRight.keyId: 'Правый Shift',
  LogicalKeyboardKey.controlLeft.keyId: 'Левый Ctrl',
  LogicalKeyboardKey.controlRight.keyId: 'Правый Ctrl',
  LogicalKeyboardKey.altLeft.keyId: 'Левый Alt',
  LogicalKeyboardKey.altRight.keyId: 'Правый Alt',
  LogicalKeyboardKey.escape.keyId: 'Esc',
  LogicalKeyboardKey.tab.keyId: 'Tab',
  LogicalKeyboardKey.enter.keyId: 'Enter',
  LogicalKeyboardKey.arrowUp.keyId: 'Вверх',
  LogicalKeyboardKey.arrowDown.keyId: 'Вниз',
  LogicalKeyboardKey.arrowLeft.keyId: 'Влево',
  LogicalKeyboardKey.arrowRight.keyId: 'Вправо',
};

final class _Russian extends Flutter3dGameLocalizations {
  const _Russian();

  @override
  String get languageCode => 'ru';

  @override
  String get settings => 'Настройки';
  @override
  String get controls => 'Управление';
  @override
  String get resetControls => 'Сбросить управление';
  @override
  String get accessibility => 'Доступность';
  @override
  String get cameraMotion => 'Движение камеры';
  @override
  String get colorVision => 'Цветовое зрение';
  @override
  List<String> get colorVisionChoices => const <String>[
    'Выкл.',
    'Протан',
    'Дейтан',
    'Тритан',
  ];
  @override
  String get highContrast => 'Высокий контраст';
  @override
  String get holdToSprint => 'Бег — удерживать';
  @override
  String get colors => 'Цвета';
  @override
  String get mouse => 'Мышь';
  @override
  String get lookSpeed => 'Скорость обзора';
  @override
  String get invertVerticalLook => 'Инвертировать обзор по вертикали';
  @override
  String gamepad({required bool connected}) =>
      connected ? 'Геймпад' : 'Геймпад (не подключён)';
  @override
  String get deadZone => 'Мёртвая зона';
  @override
  String get settingsNotSaved =>
      'Эти настройки не удалось сохранить, и они пропадут, когда игра '
      'закроется. Диск или хранилище браузера заполнены.';
  @override
  String get backToTheGame => 'Вернуться в игру';
  @override
  String volume(String bus) => switch (bus) {
    'master' => 'общая громкость',
    'music' => 'музыка',
    'sfx' => 'эффекты',
    _ => bus,
  };
  @override
  String colorChoice(String label, int index) =>
      index == 0 ? '$label, как в игре' : '$label, $index';

  @override
  String get pressAKeyOrButton => 'нажмите клавишу или кнопку';
  @override
  String get boundToNothing => 'ничего';
  @override
  String boundTo(String action, String bound) => '$action: $bound';
  @override
  String actionLabel(String id) => switch (id) {
    'forward' || 'moveForward' => 'вперёд',
    'back' || 'moveBack' => 'назад',
    'left' || 'moveLeft' => 'влево',
    'right' || 'moveRight' => 'вправо',
    'jump' => 'прыжок',
    'sprint' => 'бег',
    'use' => 'действие',
    'look' => 'обзор',
    'move' => 'движение',
    _ => id,
  };

  @override
  String part(CompositePart part) => switch (part) {
    CompositePart.negative => '−',
    CompositePart.positive => '+',
    CompositePart.up => 'вверх',
    CompositePart.down => 'вниз',
    CompositePart.left => 'влево',
    CompositePart.right => 'вправо',
  };
  @override
  String conflict(String source, String action) =>
      '$source раньше было назначено на «$action».';
  @override
  String invertVertically(String action, String on) =>
      'Инвертировать «$action» по вертикали, $on';
  @override
  String invertHorizontally(String action, String on) =>
      'Инвертировать «$action» по горизонтали, $on';
  @override
  String invert(String action, String on) => 'Инвертировать «$action», $on';
  @override
  String get mouseMotion => 'мышь';
  @override
  String mouseButton(int? button) => switch (button) {
    0 => 'левая кнопка мыши',
    1 => 'правая кнопка мыши',
    _ => 'кнопка мыши ${button ?? '?'}',
  };
  @override
  String get touchPrefix => 'касание';
  @override
  String get padPrefix => 'геймпад';
  @override
  String? keyName(int keyId) => _russianKeys[keyId];

  @override
  String get yourData => 'Ваши данные';
  @override
  String get cloudSaves => 'Облачные сохранения';
  @override
  String get cloudSavesExplained =>
      'Хранит ваш забег и на сервере сохранений, чтобы продолжить его на '
      'другом устройстве.';
  @override
  String get noSaveServer =>
      'В этой сборке нет сервера сохранений; забег остаётся на этом '
      'устройстве.';
  @override
  String get sendMyRuns => 'Отправлять мои забеги';
  @override
  String get sendMyRunsExplained =>
      'Отправляет, что вы нажимали в каждом пройденном уровне, без имени, '
      'чтобы авторы видели, где уровни слишком сложны.';
  @override
  String get answerNotKept => 'Этот ответ не удалось сохранить на устройстве.';
  @override
  String get whichRun => 'Какой забег оставить?';
  @override
  String get onThisDevice => 'На этом устройстве';
  @override
  String get inTheCloud => 'В облаке';
  @override
  String get later => 'Позже';
  @override
  String get theClouds => 'Из облака';
  @override
  String get thisDevices => 'С этого устройства';
  @override
  String runLine(String where, {String? level, String? played}) =>
      level == null ? '$where: нет' : '$where: $level, сыграно $played';

  @override
  String get tapToPlayAgain => 'Коснитесь, чтобы сыграть снова';
  @override
  String get art => 'Графика';
  @override
  String get artInThisGame => 'Графика в этой игре';
  @override
  String creditLine(Credit credit) {
    if (!credit.isTraced) {
      return '${credit.work} — автор неизвестен, лицензия не установлена';
    }
    final changed = credit.modified ? ', изменено' : '';
    return '${credit.work}, автор ${credit.author} — ${credit.license}$changed';
  }

  @override
  String get shareThisRun => 'Поделиться забегом';
  @override
  String get aFriendsCode => 'Код друга';
  @override
  String get openTheirRun => 'Состязаться';

  @override
  String get throttle => 'газ';
  @override
  String get brake => 'тормоз';
  @override
  String get handbrake => 'ручник';

  @override
  String get takingThePicture => 'Снимаем…';
  @override
  String photoMode({required String filter, String? exposure}) =>
      'Фоторежим · фильтр: $filter · ${exposure ?? 'экспозиция игры'}';
  @override
  String get photoWalkingKeys =>
      'WASD — полёт · Пробел/C — вверх и вниз · Shift — быстрее · [ ] — '
      'фильтр · , . — наклон · − = — зум · Enter — 2× · Shift+Enter — 4× · '
      'P — назад';
  @override
  String get photoExposureKeys =>
      '1 2 — диафрагма · 3 4 — выдержка · 5 6 — ISO · 0 — экспозиция игры';

  @override
  String get kilometersPerHour => 'км/ч';
}

final class _Delegate
    extends LocalizationsDelegate<Flutter3dGameLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => Flutter3dGameLocalizations.supportedLocales
      .any((Locale it) => it.languageCode == locale.languageCode);

  @override
  Future<Flutter3dGameLocalizations> load(Locale locale) =>
      SynchronousFuture<Flutter3dGameLocalizations>(
        Flutter3dGameLocalizations.forLocale(locale),
      );

  @override
  bool shouldReload(_Delegate old) => false;
}
