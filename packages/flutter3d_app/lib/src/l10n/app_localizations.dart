import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

/// What this package's widgets say, in the reader's language: the status
/// screens, the text a `Flutter3dView` shows when no device opened, and the
/// stereo lesson's step buttons.
///
/// **Installed like Flutter's own**, beside them in the app's
/// `localizationsDelegates`:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: const <LocalizationsDelegate<Object>>[
///     Flutter3dAppLocalizations.delegate,
///     ...GlobalMaterialLocalizations.delegates,
///   ],
///   supportedLocales: Flutter3dAppLocalizations.supportedLocales,
/// );
/// ```
///
/// Without it, [of] answers in English, so a widget in a test or an app that
/// never thought about languages still reads. A widget that takes a string
/// parameter still takes it, and a caller that passes one says its own words.
///
/// **English and Russian ship.** Another language is a subclass overriding
/// what it translates, handed out by a delegate of the application's own;
/// every member has an English body, so one added in a minor release does
/// not break it.
base class Flutter3dAppLocalizations {
  /// English, which is also what every other language falls back to.
  const Flutter3dAppLocalizations();

  /// The words for [locale]: Russian for `ru`, English for anything else.
  factory Flutter3dAppLocalizations.forLocale(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => const _Russian(),
        _ => english,
      };

  /// The English words, for a caller with no [BuildContext].
  static const Flutter3dAppLocalizations english = Flutter3dAppLocalizations();

  /// The delegate an app lists in `localizationsDelegates`.
  static const LocalizationsDelegate<Flutter3dAppLocalizations> delegate =
      _Delegate();

  /// The languages that ship.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// The words for [context]'s locale, or [english] when the app installed
  /// no [delegate].
  static Flutter3dAppLocalizations of(BuildContext context) =>
      Localizations.of<Flutter3dAppLocalizations>(
        context,
        Flutter3dAppLocalizations,
      ) ??
      english;

  /// The language this speaks, as a locale's language code.
  String get languageCode => 'en';

  /// While a level is being read.
  String get loading => 'Loading…';

  /// The title of the screen shown when the renderer never started.
  String get rendererDidNotStart => 'The renderer did not start.';

  /// What a person meeting that screen most likely has to do.
  String get rebuildShaderBundle =>
      'The engine\'s shader bundle is compiled for one Flutter SDK; after '
      'changing the SDK, build the application again so the bundle is '
      'rebuilt.';

  /// The title of the screen shown when a level threw rather than loaded.
  String get levelWouldNotLoad => 'That level would not load.';

  /// The way out of a level that will not load.
  String get startOver => 'Throw the run away and start again';

  /// What a `Flutter3dView` shows when no device would open.
  String viewDidNotStart(Object error) => 'The 3D view could not start: $error';

  /// A stereo lesson's button back one step.
  String get previousStep => 'Previous step';

  /// A stereo lesson's button on one step.
  String get nextStep => 'Next step';
}

final class _Russian extends Flutter3dAppLocalizations {
  const _Russian();

  @override
  String get languageCode => 'ru';
  @override
  String get loading => 'Загрузка…';
  @override
  String get rendererDidNotStart => 'Рендерер не запустился.';
  @override
  String get rebuildShaderBundle =>
      'Шейдеры движка собраны под одну версию Flutter SDK; после смены SDK '
      'соберите приложение заново, чтобы они пересобрались.';
  @override
  String get levelWouldNotLoad => 'Этот уровень не загрузился.';
  @override
  String get startOver => 'Бросить забег и начать заново';
  @override
  String viewDidNotStart(Object error) => '3D-вид не запустился: $error';
  @override
  String get previousStep => 'Предыдущий шаг';
  @override
  String get nextStep => 'Следующий шаг';
}

final class _Delegate extends LocalizationsDelegate<Flutter3dAppLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => Flutter3dAppLocalizations.supportedLocales
      .any((Locale it) => it.languageCode == locale.languageCode);

  @override
  Future<Flutter3dAppLocalizations> load(Locale locale) =>
      SynchronousFuture<Flutter3dAppLocalizations>(
        Flutter3dAppLocalizations.forLocale(locale),
      );

  @override
  bool shouldReload(_Delegate old) => false;
}
