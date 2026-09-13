import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Заголовок окна/вкладки — имя приложения, не переводится по смыслу.
  ///
  /// In ru, this message translates to:
  /// **'flutter3d modeller'**
  String get appTitle;

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Несохранённые изменения'**
  String get unsavedChangesTitle;

  /// No description provided for @unsavedChangesBody.
  ///
  /// In ru, this message translates to:
  /// **'В этой модели есть изменения, которые не были сохранены.'**
  String get unsavedChangesBody;

  /// No description provided for @keepEditing.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить редактирование'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In ru, this message translates to:
  /// **'Не сохранять'**
  String get discard;

  /// No description provided for @saveAndClose.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить и закрыть'**
  String get saveAndClose;

  /// No description provided for @restoreUnsavedChangesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить несохранённые изменения?'**
  String get restoreUnsavedChangesTitle;

  /// Текст диалога восстановления после аварийного завершения сессии.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one {Найден автосохранённый файл сессии, которая закрылась некорректно ({count} объект).} few {Найден автосохранённый файл сессии, которая закрылась некорректно ({count} объекта).} many {Найден автосохранённый файл сессии, которая закрылась некорректно ({count} объектов).} other {Найден автосохранённый файл сессии, которая закрылась некорректно ({count} объекта).}}'**
  String restoreUnsavedChangesBody(int count);

  /// No description provided for @restore.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get restore;

  /// No description provided for @exportAnywayTitle.
  ///
  /// In ru, this message translates to:
  /// **'Всё равно экспортировать?'**
  String get exportAnywayTitle;

  /// Строка под усечённым списком проблем экспорта.
  ///
  /// In ru, this message translates to:
  /// **'и ещё {count}'**
  String exportAnywayMoreIssues(int count);

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @exportAnyway.
  ///
  /// In ru, this message translates to:
  /// **'Всё равно экспортировать'**
  String get exportAnyway;

  /// No description provided for @addPrimitiveTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Добавить примитив'**
  String get addPrimitiveTooltip;

  /// No description provided for @add.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get add;

  /// No description provided for @open.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get open;

  /// No description provided for @save.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get save;

  /// No description provided for @exportTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Экспортировать копию'**
  String get exportTooltip;

  /// No description provided for @export.
  ///
  /// In ru, this message translates to:
  /// **'Экспорт'**
  String get export;

  /// No description provided for @materialStudioSemanticsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Материал-студия'**
  String get materialStudioSemanticsLabel;

  /// No description provided for @materialStudioTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Материал-студия — предпросмотр материала'**
  String get materialStudioTooltip;

  /// No description provided for @keyboardShortcuts.
  ///
  /// In ru, this message translates to:
  /// **'Горячие клавиши'**
  String get keyboardShortcuts;

  /// No description provided for @keyboardShortcutsTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Горячие клавиши (?)'**
  String get keyboardShortcutsTooltip;

  /// No description provided for @startScreenSemanticsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Стартовый экран'**
  String get startScreenSemanticsLabel;

  /// No description provided for @startScreenTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Стартовый экран — открыть файл или начать новый проект'**
  String get startScreenTooltip;

  /// No description provided for @reportProblem.
  ///
  /// In ru, this message translates to:
  /// **'Сообщить о проблеме'**
  String get reportProblem;

  /// No description provided for @sectionDisplay.
  ///
  /// In ru, this message translates to:
  /// **'Отображение'**
  String get sectionDisplay;

  /// No description provided for @sectionView.
  ///
  /// In ru, this message translates to:
  /// **'Вид'**
  String get sectionView;

  /// No description provided for @sectionObjects.
  ///
  /// In ru, this message translates to:
  /// **'Объекты'**
  String get sectionObjects;

  /// No description provided for @sectionTransform.
  ///
  /// In ru, this message translates to:
  /// **'Трансформация'**
  String get sectionTransform;

  /// No description provided for @sectionModifiers.
  ///
  /// In ru, this message translates to:
  /// **'Модификаторы'**
  String get sectionModifiers;

  /// No description provided for @sectionLastOperation.
  ///
  /// In ru, this message translates to:
  /// **'Последняя операция'**
  String get sectionLastOperation;

  /// No description provided for @sectionSelection.
  ///
  /// In ru, this message translates to:
  /// **'Выделение'**
  String get sectionSelection;

  /// No description provided for @sectionMesh.
  ///
  /// In ru, this message translates to:
  /// **'Меш'**
  String get sectionMesh;

  /// No description provided for @sectionBudget.
  ///
  /// In ru, this message translates to:
  /// **'Бюджет'**
  String get sectionBudget;

  /// No description provided for @rowWhat.
  ///
  /// In ru, this message translates to:
  /// **'Что'**
  String get rowWhat;

  /// No description provided for @rowVertices.
  ///
  /// In ru, this message translates to:
  /// **'Вершины'**
  String get rowVertices;

  /// No description provided for @rowFaces.
  ///
  /// In ru, this message translates to:
  /// **'Грани'**
  String get rowFaces;

  /// No description provided for @rowTriangles.
  ///
  /// In ru, this message translates to:
  /// **'Треугольники'**
  String get rowTriangles;

  /// No description provided for @rowProfile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get rowProfile;

  /// No description provided for @shadingMaterial.
  ///
  /// In ru, this message translates to:
  /// **'Материал'**
  String get shadingMaterial;

  /// No description provided for @shadingNormals.
  ///
  /// In ru, this message translates to:
  /// **'Нормали'**
  String get shadingNormals;

  /// No description provided for @shadingWire.
  ///
  /// In ru, this message translates to:
  /// **'Каркас'**
  String get shadingWire;

  /// No description provided for @lensPerspective.
  ///
  /// In ru, this message translates to:
  /// **'Перспектива'**
  String get lensPerspective;

  /// No description provided for @lensOrthographic.
  ///
  /// In ru, this message translates to:
  /// **'Ортографическая'**
  String get lensOrthographic;

  /// No description provided for @viewFront.
  ///
  /// In ru, this message translates to:
  /// **'Спереди'**
  String get viewFront;

  /// No description provided for @viewBack.
  ///
  /// In ru, this message translates to:
  /// **'Сзади'**
  String get viewBack;

  /// No description provided for @viewLeft.
  ///
  /// In ru, this message translates to:
  /// **'Слева'**
  String get viewLeft;

  /// No description provided for @viewRight.
  ///
  /// In ru, this message translates to:
  /// **'Справа'**
  String get viewRight;

  /// No description provided for @viewTop.
  ///
  /// In ru, this message translates to:
  /// **'Сверху'**
  String get viewTop;

  /// No description provided for @viewBottom.
  ///
  /// In ru, this message translates to:
  /// **'Снизу'**
  String get viewBottom;

  /// No description provided for @recoverUnsavedChangesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить несохранённые изменения?'**
  String get recoverUnsavedChangesTitle;

  /// No description provided for @recoverUnsavedChangesBody.
  ///
  /// In ru, this message translates to:
  /// **'Найдена автосохранённая версия новее последнего сохранённого файла. Восстановить её или открыть файл в том виде, в каком он был сохранён?'**
  String get recoverUnsavedChangesBody;

  /// No description provided for @openSavedFile.
  ///
  /// In ru, this message translates to:
  /// **'Открыть сохранённый файл'**
  String get openSavedFile;

  /// No description provided for @restoreAutosave.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить автосохранение'**
  String get restoreAutosave;

  /// No description provided for @startTitle.
  ///
  /// In ru, this message translates to:
  /// **'Начало'**
  String get startTitle;

  /// No description provided for @openFile.
  ///
  /// In ru, this message translates to:
  /// **'Открыть файл'**
  String get openFile;

  /// No description provided for @newProject.
  ///
  /// In ru, this message translates to:
  /// **'Новый проект'**
  String get newProject;

  /// No description provided for @recent.
  ///
  /// In ru, this message translates to:
  /// **'Недавние'**
  String get recent;

  /// No description provided for @tutorial.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get tutorial;

  /// No description provided for @close.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get close;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
