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

  /// mat-24's own status line — how many lights, how many are shadowed, and the cap.
  ///
  /// In ru, this message translates to:
  /// **'Источников {lightCount} · теневых {shadowedCount} из {shadowCap}'**
  String sceneStatusLabel(int lightCount, int shadowedCount, int shadowCap);

  /// No description provided for @sceneEnvironmentSectionLabel.
  ///
  /// In ru, this message translates to:
  /// **'Окружение'**
  String get sceneEnvironmentSectionLabel;

  /// No description provided for @sceneShadowsSectionLabel.
  ///
  /// In ru, this message translates to:
  /// **'Тени'**
  String get sceneShadowsSectionLabel;

  /// No description provided for @sceneShadowsToggleLabel.
  ///
  /// In ru, this message translates to:
  /// **'Тени'**
  String get sceneShadowsToggleLabel;

  /// No description provided for @sceneSourcesSectionLabel.
  ///
  /// In ru, this message translates to:
  /// **'Источники'**
  String get sceneSourcesSectionLabel;

  /// No description provided for @scenePostSectionLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пост'**
  String get scenePostSectionLabel;

  /// No description provided for @bakeTextureButtonLabel.
  ///
  /// In ru, this message translates to:
  /// **'Запечь 2048²'**
  String get bakeTextureButtonLabel;

  /// No description provided for @resetPoseButtonLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить позу'**
  String get resetPoseButtonLabel;

  /// No description provided for @toolObjectSelectLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выделение'**
  String get toolObjectSelectLabel;

  /// No description provided for @toolObjectSelectAbout.
  ///
  /// In ru, this message translates to:
  /// **'Клик по объекту берёт его в работу; с Shift — добавляет к уже выбранному.'**
  String get toolObjectSelectAbout;

  /// No description provided for @toolObjectMoveLabel.
  ///
  /// In ru, this message translates to:
  /// **'Перемещение'**
  String get toolObjectMoveLabel;

  /// No description provided for @toolObjectMoveAbout.
  ///
  /// In ru, this message translates to:
  /// **'Тяните стрелку, чтобы двигать вдоль одной оси, или центр — чтобы свободно.'**
  String get toolObjectMoveAbout;

  /// No description provided for @toolObjectRotateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Поворот'**
  String get toolObjectRotateLabel;

  /// No description provided for @toolObjectRotateAbout.
  ///
  /// In ru, this message translates to:
  /// **'Тяните кольцо, чтобы повернуть вокруг этой оси.'**
  String get toolObjectRotateAbout;

  /// No description provided for @toolObjectScaleLabel.
  ///
  /// In ru, this message translates to:
  /// **'Масштаб'**
  String get toolObjectScaleLabel;

  /// No description provided for @toolObjectScaleAbout.
  ///
  /// In ru, this message translates to:
  /// **'Тяните ручку, чтобы растянуть или сжать — по одной оси или сразу по трём от центра.'**
  String get toolObjectScaleAbout;

  /// No description provided for @toolObjectAddLabel.
  ///
  /// In ru, this message translates to:
  /// **'Добавить куб'**
  String get toolObjectAddLabel;

  /// No description provided for @toolObjectAddAbout.
  ///
  /// In ru, this message translates to:
  /// **'Ставит новый куб в начале координат, всё ещё параметрический: размеры и разбиение правятся в панели.'**
  String get toolObjectAddAbout;

  /// No description provided for @toolObjectDuplicateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Дублировать'**
  String get toolObjectDuplicateLabel;

  /// No description provided for @toolObjectDuplicateAbout.
  ///
  /// In ru, this message translates to:
  /// **'Копирует выделенное и выделяет копию, оставляя оригинал на месте.'**
  String get toolObjectDuplicateAbout;

  /// No description provided for @toolObjectBakeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Превратить в меш'**
  String get toolObjectBakeLabel;

  /// No description provided for @toolObjectBakeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Превращает форму, помнящую свои параметры, в обычную правимую геометрию. Поля размеров и разбиения исчезают.'**
  String get toolObjectBakeAbout;

  /// No description provided for @toolObjectLatheLabel.
  ///
  /// In ru, this message translates to:
  /// **'Добавить тело вращения'**
  String get toolObjectLatheLabel;

  /// No description provided for @toolObjectLatheAbout.
  ///
  /// In ru, this message translates to:
  /// **'Вращает нарисованный профиль вокруг оси — так делаются ваза, бутылка или колесо.'**
  String get toolObjectLatheAbout;

  /// No description provided for @toolObjectOriginLabel.
  ///
  /// In ru, this message translates to:
  /// **'Опорную точку вниз'**
  String get toolObjectOriginLabel;

  /// No description provided for @toolObjectOriginAbout.
  ///
  /// In ru, this message translates to:
  /// **'Опускает точку, вокруг которой объект поворачивается и масштабируется, к самой нижней вершине — объект встаёт на пол.'**
  String get toolObjectOriginAbout;

  /// No description provided for @toolObjectApplyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Применить трансформацию'**
  String get toolObjectApplyLabel;

  /// No description provided for @toolObjectApplyAbout.
  ///
  /// In ru, this message translates to:
  /// **'Вживляет положение, поворот и масштаб в сами вершины и обнуляет трансформацию.'**
  String get toolObjectApplyAbout;

  /// No description provided for @toolObjectDeleteLabel.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get toolObjectDeleteLabel;

  /// No description provided for @toolObjectDeleteAbout.
  ///
  /// In ru, this message translates to:
  /// **'Убирает выделенное. Отмена возвращает.'**
  String get toolObjectDeleteAbout;

  /// No description provided for @toolMeshSelectLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выделение'**
  String get toolMeshSelectLabel;

  /// No description provided for @toolMeshSelectAbout.
  ///
  /// In ru, this message translates to:
  /// **'Клик по вершине, ребру или грани; с Shift — добавляет к уже выбранному.'**
  String get toolMeshSelectAbout;

  /// No description provided for @toolMeshLassoLabel.
  ///
  /// In ru, this message translates to:
  /// **'Лассо'**
  String get toolMeshLassoLabel;

  /// No description provided for @toolMeshLassoAbout.
  ///
  /// In ru, this message translates to:
  /// **'Обведите нужное от руки вместо того, чтобы кликать каждую часть.'**
  String get toolMeshLassoAbout;

  /// No description provided for @toolMeshLinkedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выделить связное'**
  String get toolMeshLinkedLabel;

  /// No description provided for @toolMeshLinkedAbout.
  ///
  /// In ru, this message translates to:
  /// **'Берёт всё, что соединено с уже выбранным, — целую оболочку меша, если их несколько.'**
  String get toolMeshLinkedAbout;

  /// No description provided for @toolMeshMoveLabel.
  ///
  /// In ru, this message translates to:
  /// **'Перемещение'**
  String get toolMeshMoveLabel;

  /// No description provided for @toolMeshMoveAbout.
  ///
  /// In ru, this message translates to:
  /// **'Двигает выбранные элементы. Число, набранное во время перетаскивания, задаёт расстояние точно.'**
  String get toolMeshMoveAbout;

  /// No description provided for @toolMeshRotateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Поворот'**
  String get toolMeshRotateLabel;

  /// No description provided for @toolMeshRotateAbout.
  ///
  /// In ru, this message translates to:
  /// **'Поворачивает выбранные элементы вокруг центра выделения.'**
  String get toolMeshRotateAbout;

  /// No description provided for @toolMeshScaleLabel.
  ///
  /// In ru, this message translates to:
  /// **'Масштаб'**
  String get toolMeshScaleLabel;

  /// No description provided for @toolMeshScaleAbout.
  ///
  /// In ru, this message translates to:
  /// **'Растягивает или сжимает выбранные элементы относительно центра выделения.'**
  String get toolMeshScaleAbout;

  /// No description provided for @toolMeshExtrudeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выдавливание'**
  String get toolMeshExtrudeLabel;

  /// No description provided for @toolMeshExtrudeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Вытягивает новую геометрию из выбранных граней и оставляет стенку, соединяющую её с тем, откуда она вышла.'**
  String get toolMeshExtrudeAbout;

  /// No description provided for @toolMeshLoopCutLabel.
  ///
  /// In ru, this message translates to:
  /// **'Кольцевой разрез'**
  String get toolMeshLoopCutLabel;

  /// No description provided for @toolMeshLoopCutAbout.
  ///
  /// In ru, this message translates to:
  /// **'Добавляет кольцо рёбер вокруг всего меша — там, где следующему изгибу нужно место.'**
  String get toolMeshLoopCutAbout;

  /// No description provided for @toolMeshBevelLabel.
  ///
  /// In ru, this message translates to:
  /// **'Фаска'**
  String get toolMeshBevelLabel;

  /// No description provided for @toolMeshBevelAbout.
  ///
  /// In ru, this message translates to:
  /// **'Заменяет острое ребро узкой полоской, чтобы свет ложился на неё как на настоящем предмете.'**
  String get toolMeshBevelAbout;

  /// No description provided for @toolMeshInsetLabel.
  ///
  /// In ru, this message translates to:
  /// **'Врезка'**
  String get toolMeshInsetLabel;

  /// No description provided for @toolMeshInsetAbout.
  ///
  /// In ru, this message translates to:
  /// **'Сжимает грань внутрь и застраивает оставшееся кольцо — так делаются панель, окно или утопленная кнопка.'**
  String get toolMeshInsetAbout;

  /// No description provided for @toolMeshBridgeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Мост'**
  String get toolMeshBridgeLabel;

  /// No description provided for @toolMeshBridgeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Соединяет две открытые границы кольцом четырёхугольников: две половины трубы становятся одной поверхностью.'**
  String get toolMeshBridgeAbout;

  /// No description provided for @toolMeshSlideLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сдвиг рёбер'**
  String get toolMeshSlideLabel;

  /// No description provided for @toolMeshSlideAbout.
  ///
  /// In ru, this message translates to:
  /// **'Двигает петлю вдоль пересекающих её рёбер: шов переезжает, но ни одна грань не меняется.'**
  String get toolMeshSlideAbout;

  /// No description provided for @toolMeshTriangulateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Триангуляция'**
  String get toolMeshTriangulateLabel;

  /// No description provided for @toolMeshTriangulateAbout.
  ///
  /// In ru, this message translates to:
  /// **'Режет каждую грань на треугольники — то, что читает игровой движок, и то, чем сначала должна стать грань больше чем с четырьмя углами.'**
  String get toolMeshTriangulateAbout;

  /// No description provided for @toolMeshSeparateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Отделить'**
  String get toolMeshSeparateLabel;

  /// No description provided for @toolMeshSeparateAbout.
  ///
  /// In ru, this message translates to:
  /// **'Выносит выбранные грани в отдельный объект.'**
  String get toolMeshSeparateAbout;

  /// No description provided for @toolMeshDissolveLabel.
  ///
  /// In ru, this message translates to:
  /// **'Растворить рёбра'**
  String get toolMeshDissolveLabel;

  /// No description provided for @toolMeshDissolveAbout.
  ///
  /// In ru, this message translates to:
  /// **'Убирает выбранные рёбра, сохраняя поверхность: разделённые ими грани сливаются в одну.'**
  String get toolMeshDissolveAbout;

  /// No description provided for @toolMeshFillHolesLabel.
  ///
  /// In ru, this message translates to:
  /// **'Заполнить дыры'**
  String get toolMeshFillHolesLabel;

  /// No description provided for @toolMeshFillHolesAbout.
  ///
  /// In ru, this message translates to:
  /// **'Закрывает каждую открытую границу — те щели, из-за которых модель просвечивает с одной стороны.'**
  String get toolMeshFillHolesAbout;

  /// No description provided for @toolMeshMergeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сшить по расстоянию'**
  String get toolMeshMergeLabel;

  /// No description provided for @toolMeshMergeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Сплавляет вершины, лежащие одна на другой, — то, чем полны скан и STL.'**
  String get toolMeshMergeAbout;

  /// No description provided for @toolMeshNormalsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пересчитать нормали'**
  String get toolMeshNormalsLabel;

  /// No description provided for @toolMeshNormalsAbout.
  ///
  /// In ru, this message translates to:
  /// **'Разворачивает каждую грань наружу, чтобы поверхность перестала читаться вывернутой.'**
  String get toolMeshNormalsAbout;

  /// No description provided for @toolMeshFlipLabel.
  ///
  /// In ru, this message translates to:
  /// **'Развернуть нормали'**
  String get toolMeshFlipLabel;

  /// No description provided for @toolMeshFlipAbout.
  ///
  /// In ru, this message translates to:
  /// **'Поворачивает выбранные грани в другую сторону — для оболочки, которую и правда смотрят изнутри.'**
  String get toolMeshFlipAbout;

  /// No description provided for @toolMeshDeleteLabel.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get toolMeshDeleteLabel;

  /// No description provided for @toolMeshDeleteAbout.
  ///
  /// In ru, this message translates to:
  /// **'Убирает выбранные вершины, рёбра или грани и всё, что на них держалось.'**
  String get toolMeshDeleteAbout;

  /// No description provided for @toolPoseSelectLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выделение'**
  String get toolPoseSelectLabel;

  /// No description provided for @toolPoseSelectAbout.
  ///
  /// In ru, this message translates to:
  /// **'Клик по суставу скелета берёт его в позу.'**
  String get toolPoseSelectAbout;

  /// No description provided for @toolPoseKeyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ключ позы'**
  String get toolPoseKeyLabel;

  /// No description provided for @toolPoseKeyAbout.
  ///
  /// In ru, this message translates to:
  /// **'Записывает позу с экрана в клип, на кадре, где стоит бегунок.'**
  String get toolPoseKeyAbout;

  /// No description provided for @toolPoseDeleteKeyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Удалить ключ'**
  String get toolPoseDeleteKeyLabel;

  /// No description provided for @toolPoseDeleteKeyAbout.
  ///
  /// In ru, this message translates to:
  /// **'Убирает ключ этого кадра, оставляя соседние вести движение сквозь него.'**
  String get toolPoseDeleteKeyAbout;

  /// No description provided for @toolPoseAutoRigLabel.
  ///
  /// In ru, this message translates to:
  /// **'Автоскелет…'**
  String get toolPoseAutoRigLabel;

  /// No description provided for @toolPoseAutoRigAbout.
  ///
  /// In ru, this message translates to:
  /// **'Строит скелет по горсти точек, которые вы расставляете на модели.'**
  String get toolPoseAutoRigAbout;

  /// No description provided for @toolWeightsPaintLabel.
  ///
  /// In ru, this message translates to:
  /// **'Красить веса'**
  String get toolWeightsPaintLabel;

  /// No description provided for @toolWeightsPaintAbout.
  ///
  /// In ru, this message translates to:
  /// **'Кистью задаёт, насколько сильно выбранный сустав тянет поверхность под курсором.'**
  String get toolWeightsPaintAbout;

  /// No description provided for @toolWeightsAssignLabel.
  ///
  /// In ru, this message translates to:
  /// **'Привязать к суставу'**
  String get toolWeightsAssignLabel;

  /// No description provided for @toolWeightsAssignAbout.
  ///
  /// In ru, this message translates to:
  /// **'Отдаёт выбранному суставу каждую вершину, которой коснулась кисть, — на полную силу.'**
  String get toolWeightsAssignAbout;

  /// No description provided for @toolWeightsMirrorLabel.
  ///
  /// In ru, this message translates to:
  /// **'Отзеркалить'**
  String get toolWeightsMirrorLabel;

  /// No description provided for @toolWeightsMirrorAbout.
  ///
  /// In ru, this message translates to:
  /// **'Копирует веса одной стороны на другую: симметричная модель красится один раз.'**
  String get toolWeightsMirrorAbout;

  /// No description provided for @toolWeightsNormalizeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Нормализовать'**
  String get toolWeightsNormalizeLabel;

  /// No description provided for @toolWeightsNormalizeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Сводит тяги каждой вершины в сумму, равную единице, и отбрасывает самые слабые сверх её собственного предела.'**
  String get toolWeightsNormalizeAbout;

  /// No description provided for @toolRetargetImportLabel.
  ///
  /// In ru, this message translates to:
  /// **'Импортировать клип-источник'**
  String get toolRetargetImportLabel;

  /// No description provided for @toolRetargetImportAbout.
  ///
  /// In ru, this message translates to:
  /// **'Читает клип из другого файла, чтобы вести этим ригом.'**
  String get toolRetargetImportAbout;

  /// No description provided for @toolRetargetAutoMapLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сопоставить кости автоматически'**
  String get toolRetargetAutoMapLabel;

  /// No description provided for @toolRetargetAutoMapAbout.
  ///
  /// In ru, this message translates to:
  /// **'Угадывает по именам, какая кость источника какой кости этого рига соответствует.'**
  String get toolRetargetAutoMapAbout;

  /// No description provided for @toolRetargetApplyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Применить перенос'**
  String get toolRetargetApplyLabel;

  /// No description provided for @toolRetargetApplyAbout.
  ///
  /// In ru, this message translates to:
  /// **'Записывает перенесённое движение на этот риг как собственный клип.'**
  String get toolRetargetApplyAbout;

  /// No description provided for @toolMorphsAddLabel.
  ///
  /// In ru, this message translates to:
  /// **'Добавить форму'**
  String get toolMorphsAddLabel;

  /// No description provided for @toolMorphsAddAbout.
  ///
  /// In ru, this message translates to:
  /// **'Берёт меш как он есть сейчас — как форму, к которой будет вести ползунок.'**
  String get toolMorphsAddAbout;

  /// No description provided for @toolMorphsKeyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ключ формы'**
  String get toolMorphsKeyLabel;

  /// No description provided for @toolMorphsKeyAbout.
  ///
  /// In ru, this message translates to:
  /// **'Записывает веса форм как они есть в клип, на кадре бегунка.'**
  String get toolMorphsKeyAbout;

  /// No description provided for @toolMorphsDeleteLabel.
  ///
  /// In ru, this message translates to:
  /// **'Удалить форму'**
  String get toolMorphsDeleteLabel;

  /// No description provided for @toolMorphsDeleteAbout.
  ///
  /// In ru, this message translates to:
  /// **'Убирает выбранную форму и ползунок, который её вёл.'**
  String get toolMorphsDeleteAbout;

  /// No description provided for @primitiveBox.
  ///
  /// In ru, this message translates to:
  /// **'Куб'**
  String get primitiveBox;

  /// No description provided for @primitivePlane.
  ///
  /// In ru, this message translates to:
  /// **'Плоскость'**
  String get primitivePlane;

  /// No description provided for @primitiveSphere.
  ///
  /// In ru, this message translates to:
  /// **'Сфера'**
  String get primitiveSphere;

  /// No description provided for @primitiveCylinder.
  ///
  /// In ru, this message translates to:
  /// **'Цилиндр'**
  String get primitiveCylinder;

  /// No description provided for @primitiveTorus.
  ///
  /// In ru, this message translates to:
  /// **'Тор'**
  String get primitiveTorus;

  /// No description provided for @openTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Открыть файл — заменяет всё, что открыто сейчас'**
  String get openTooltip;

  /// No description provided for @importTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Импортировать файл — добавляет его к тому, что уже открыто'**
  String get importTooltip;

  /// No description provided for @import.
  ///
  /// In ru, this message translates to:
  /// **'Импорт'**
  String get import;

  /// No description provided for @saveTooltipDirty.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить — есть несохранённые изменения'**
  String get saveTooltipDirty;

  /// No description provided for @saveTooltipClean.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить — всё записано'**
  String get saveTooltipClean;

  /// No description provided for @saveToCabinet.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить в кабинет'**
  String get saveToCabinet;

  /// No description provided for @splitViewportSemanticsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Разделить вьюпорт'**
  String get splitViewportSemanticsLabel;

  /// No description provided for @splitViewportOn.
  ///
  /// In ru, this message translates to:
  /// **'Разделить вьюпорт — один документ с двух камер'**
  String get splitViewportOn;

  /// No description provided for @splitViewportOff.
  ///
  /// In ru, this message translates to:
  /// **'Снова один вьюпорт'**
  String get splitViewportOff;

  /// No description provided for @play.
  ///
  /// In ru, this message translates to:
  /// **'Играть'**
  String get play;

  /// No description provided for @playTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Играть — походить по документу в шаблоне'**
  String get playTooltip;

  /// Верхняя панель — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Играть — {reason}'**
  String playBlockedTooltip(String reason);

  /// No description provided for @preview.
  ///
  /// In ru, this message translates to:
  /// **'Предпросмотр'**
  String get preview;

  /// No description provided for @previewTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Предпросмотр — как это нарисует игра'**
  String get previewTooltip;

  /// No description provided for @settings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settings;

  /// No description provided for @settingsTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Настройки — навигация, клавиши, рабочее пространство, язык'**
  String get settingsTooltip;

  /// Верхняя панель — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Сеанс агента, вызовов: {count}'**
  String agentSessionSemanticsLabel(int count);

  /// Верхняя панель — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{client} · вызовов: {count}'**
  String agentSessionTooltip(String client, int count);

  /// No description provided for @exportCopyTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Экспортировать копию'**
  String get exportCopyTooltip;

  /// No description provided for @reportProblemTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сообщить о проблеме'**
  String get reportProblemTooltip;

  /// No description provided for @startScreenLabel.
  ///
  /// In ru, this message translates to:
  /// **'Начальный экран'**
  String get startScreenLabel;

  /// No description provided for @more.
  ///
  /// In ru, this message translates to:
  /// **'Ещё'**
  String get more;

  /// No description provided for @foldPropertiesPanel.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть панель свойств'**
  String get foldPropertiesPanel;

  /// No description provided for @foldToolRail.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть панель инструментов'**
  String get foldToolRail;

  /// No description provided for @legalEntry.
  ///
  /// In ru, this message translates to:
  /// **'Юридическое: лицензия, приватность и сторонние лицензии'**
  String get legalEntry;

  /// No description provided for @runACommand.
  ///
  /// In ru, this message translates to:
  /// **'Выполнить команду'**
  String get runACommand;

  /// No description provided for @gallery.
  ///
  /// In ru, this message translates to:
  /// **'Галерея'**
  String get gallery;

  /// No description provided for @galleryTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Галерея — вставить готовую модель рядом с открытым'**
  String get galleryTooltip;

  /// No description provided for @toolSculptDrawLabel.
  ///
  /// In ru, this message translates to:
  /// **'Лепка'**
  String get toolSculptDrawLabel;

  /// No description provided for @toolSculptDrawAbout.
  ///
  /// In ru, this message translates to:
  /// **'Выдавливает всё под кистью в одном общем направлении — как штамп.'**
  String get toolSculptDrawAbout;

  /// No description provided for @toolSculptClayLabel.
  ///
  /// In ru, this message translates to:
  /// **'Глина'**
  String get toolSculptClayLabel;

  /// No description provided for @toolSculptClayAbout.
  ///
  /// In ru, this message translates to:
  /// **'Наращивает поверхность плоскими слоями — как глину пальцем.'**
  String get toolSculptClayAbout;

  /// No description provided for @toolSculptInflateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Надув'**
  String get toolSculptInflateLabel;

  /// No description provided for @toolSculptInflateAbout.
  ///
  /// In ru, this message translates to:
  /// **'Двигает каждую вершину по её собственной нормали: округлый участок раздувается, а не поднимается плоскостью.'**
  String get toolSculptInflateAbout;

  /// No description provided for @toolSculptSmoothLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сглаживание'**
  String get toolSculptSmoothLabel;

  /// No description provided for @toolSculptSmoothAbout.
  ///
  /// In ru, this message translates to:
  /// **'Выравнивает то, что под кистью, снимая неровности.'**
  String get toolSculptSmoothAbout;

  /// No description provided for @toolSculptFlattenLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выравнивание'**
  String get toolSculptFlattenLabel;

  /// No description provided for @toolSculptFlattenAbout.
  ///
  /// In ru, this message translates to:
  /// **'Притягивает всё под кистью к одной плоскости.'**
  String get toolSculptFlattenAbout;

  /// No description provided for @toolSculptGrabLabel.
  ///
  /// In ru, this message translates to:
  /// **'Захват'**
  String get toolSculptGrabLabel;

  /// No description provided for @toolSculptGrabAbout.
  ///
  /// In ru, this message translates to:
  /// **'Тянет вершины под кистью вслед за указателем.'**
  String get toolSculptGrabAbout;

  /// No description provided for @toolSculptPinchLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сжатие'**
  String get toolSculptPinchLabel;

  /// No description provided for @toolSculptPinchAbout.
  ///
  /// In ru, this message translates to:
  /// **'Стягивает вершины под кистью к её центру.'**
  String get toolSculptPinchAbout;

  /// No description provided for @toolSculptCreaseLabel.
  ///
  /// In ru, this message translates to:
  /// **'Складка'**
  String get toolSculptCreaseLabel;

  /// No description provided for @toolSculptCreaseAbout.
  ///
  /// In ru, this message translates to:
  /// **'Сжимает и вдавливает разом — так прорезается складка.'**
  String get toolSculptCreaseAbout;

  /// No description provided for @toolRetopoQuadLabel.
  ///
  /// In ru, this message translates to:
  /// **'Нарисовать квад'**
  String get toolRetopoQuadLabel;

  /// No description provided for @toolRetopoQuadAbout.
  ///
  /// In ru, this message translates to:
  /// **'Четыре клика по исходной модели: каждая точка либо прилипает к уже существующей вершине новой сетки, либо ложится на поверхность.'**
  String get toolRetopoQuadAbout;

  /// No description provided for @toolRetopoAutoLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ретопология'**
  String get toolRetopoAutoLabel;

  /// No description provided for @toolRetopoAutoAbout.
  ///
  /// In ru, this message translates to:
  /// **'Перестраивает всю поверхность квадами примерно в том количестве, что задано на панели, и обтягивает ими оригинал.'**
  String get toolRetopoAutoAbout;

  /// No description provided for @toolRetopoBakeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Запечь карты'**
  String get toolRetopoBakeLabel;

  /// No description provided for @toolRetopoBakeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Запекает поверхность исходной модели в развёртку новой — карту нормалей, карту затенения или обе.'**
  String get toolRetopoBakeAbout;

  /// No description provided for @toolPaintBrushLabel.
  ///
  /// In ru, this message translates to:
  /// **'Кисть'**
  String get toolPaintBrushLabel;

  /// No description provided for @toolPaintBrushAbout.
  ///
  /// In ru, this message translates to:
  /// **'Красит текстуру объекта через его развёртку: штрих поперёк шва ложится на оба острова.'**
  String get toolPaintBrushAbout;

  /// No description provided for @toolPaintFillLabel.
  ///
  /// In ru, this message translates to:
  /// **'Залить слой'**
  String get toolPaintFillLabel;

  /// No description provided for @toolPaintFillAbout.
  ///
  /// In ru, this message translates to:
  /// **'Заливает весь слой цветом с палитры.'**
  String get toolPaintFillAbout;

  /// No description provided for @toolPaintClearLabel.
  ///
  /// In ru, this message translates to:
  /// **'Очистить слой'**
  String get toolPaintClearLabel;

  /// No description provided for @toolPaintClearAbout.
  ///
  /// In ru, this message translates to:
  /// **'Опустошает слой, не трогая те, что под ним.'**
  String get toolPaintClearAbout;

  /// No description provided for @toolSimSelectLabel.
  ///
  /// In ru, this message translates to:
  /// **'Выделение'**
  String get toolSimSelectLabel;

  /// No description provided for @toolSimSelectAbout.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать вершины, на которых висит ткань, или объект для расчёта.'**
  String get toolSimSelectAbout;

  /// No description provided for @toolSimPinLabel.
  ///
  /// In ru, this message translates to:
  /// **'Закрепить выделение'**
  String get toolSimPinLabel;

  /// No description provided for @toolSimPinAbout.
  ///
  /// In ru, this message translates to:
  /// **'Удерживает выбранные вершины на месте, пока всё остальное падает.'**
  String get toolSimPinAbout;

  /// No description provided for @toolSimBakeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Запечь'**
  String get toolSimBakeLabel;

  /// No description provided for @toolSimBakeAbout.
  ///
  /// In ru, this message translates to:
  /// **'Считает весь клип и сохраняет его, чтобы по нему можно было перематывать.'**
  String get toolSimBakeAbout;

  /// No description provided for @toolRenderSnapshotLabel.
  ///
  /// In ru, this message translates to:
  /// **'Рендер'**
  String get toolRenderSnapshotLabel;

  /// No description provided for @toolRenderSnapshotAbout.
  ///
  /// In ru, this message translates to:
  /// **'Рендерит проект в размере, заданном на панели, по тайлу за раз и показывает результат.'**
  String get toolRenderSnapshotAbout;

  /// No description provided for @toolRenderSaveLabel.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить картинку'**
  String get toolRenderSaveLabel;

  /// No description provided for @toolRenderSaveAbout.
  ///
  /// In ru, this message translates to:
  /// **'Записывает последний рендер в PNG.'**
  String get toolRenderSaveAbout;

  /// No description provided for @settingsClearDataTitle.
  ///
  /// In ru, this message translates to:
  /// **'Очистить локальные данные?'**
  String get settingsClearDataTitle;

  /// No description provided for @settingsClear.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get settingsClear;

  /// No description provided for @settingsCameraNavigation.
  ///
  /// In ru, this message translates to:
  /// **'Навигация камерой'**
  String get settingsCameraNavigation;

  /// No description provided for @settingsKeys.
  ///
  /// In ru, this message translates to:
  /// **'Клавиши'**
  String get settingsKeys;

  /// No description provided for @settingsTransformTools.
  ///
  /// In ru, this message translates to:
  /// **'Перемещение, поворот и масштаб'**
  String get settingsTransformTools;

  /// No description provided for @settingsWorkspace.
  ///
  /// In ru, this message translates to:
  /// **'Рабочее пространство'**
  String get settingsWorkspace;

  /// No description provided for @settingsLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get settingsLanguage;

  /// No description provided for @settingsStepMove.
  ///
  /// In ru, this message translates to:
  /// **'Сдвиг'**
  String get settingsStepMove;

  /// No description provided for @settingsStepTurn.
  ///
  /// In ru, this message translates to:
  /// **'Поворот°'**
  String get settingsStepTurn;

  /// No description provided for @settingsStepScale.
  ///
  /// In ru, this message translates to:
  /// **'Масштаб'**
  String get settingsStepScale;

  /// No description provided for @settingsShowHome.
  ///
  /// In ru, this message translates to:
  /// **'Показывать «Домой» при запуске'**
  String get settingsShowHome;

  /// No description provided for @settingsSaveHistory.
  ///
  /// In ru, this message translates to:
  /// **'Сохранять проекты вместе с историей'**
  String get settingsSaveHistory;

  /// No description provided for @settingsLegal.
  ///
  /// In ru, this message translates to:
  /// **'Лицензия, приватность и остальное'**
  String get settingsLegal;

  /// No description provided for @settingsClearData.
  ///
  /// In ru, this message translates to:
  /// **'Очистить локальные данные'**
  String get settingsClearData;

  /// No description provided for @settingsClearDataBody.
  ///
  /// In ru, this message translates to:
  /// **'Удалятся настройки, список недавних файлов и автосохранение. Файлы проектов, сохранённые вами, не трогаются. Отменить нельзя.'**
  String get settingsClearDataBody;

  /// No description provided for @settingsCameraNavigationHelp.
  ///
  /// In ru, this message translates to:
  /// **'Какие кнопки и жесты вращают, двигают и приближают.'**
  String get settingsCameraNavigationHelp;

  /// No description provided for @settingsKeysHelp.
  ///
  /// In ru, this message translates to:
  /// **'Какой набор горячих клавиш действует.'**
  String get settingsKeysHelp;

  /// No description provided for @settingsTransformToolsHelp.
  ///
  /// In ru, this message translates to:
  /// **'Открывает ли клавиша преобразование сразу или готовит его к перетаскиванию.'**
  String get settingsTransformToolsHelp;

  /// No description provided for @settingsWorkspaceHelp.
  ///
  /// In ru, this message translates to:
  /// **'Какие экраны предлагает переключатель режимов.'**
  String get settingsWorkspaceHelp;

  /// No description provided for @settingsLanguageHelp.
  ///
  /// In ru, this message translates to:
  /// **'На каком языке написан интерфейс.'**
  String get settingsLanguageHelp;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In ru, this message translates to:
  /// **'Английский'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageRussian.
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системный'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsSnapSteps.
  ///
  /// In ru, this message translates to:
  /// **'Шаги привязки'**
  String get settingsSnapSteps;

  /// No description provided for @settingsShowHomeHelp.
  ///
  /// In ru, this message translates to:
  /// **'Стартовый экран с недавними моделями и карточками сценариев.'**
  String get settingsShowHomeHelp;

  /// No description provided for @settingsSaveHistoryHelp.
  ///
  /// In ru, this message translates to:
  /// **'Сохраняет внутри файла то, что ещё можно отменить.'**
  String get settingsSaveHistoryHelp;

  /// No description provided for @settingsLegalSection.
  ///
  /// In ru, this message translates to:
  /// **'Юридическое и данные'**
  String get settingsLegalSection;

  /// No description provided for @settingsClearDataHelp.
  ///
  /// In ru, this message translates to:
  /// **'Настройки, список недавних файлов и автосохранение. Сохранённые файлы проектов не трогаются.'**
  String get settingsClearDataHelp;

  /// No description provided for @settingsLegalHelp.
  ///
  /// In ru, this message translates to:
  /// **'Документы, под которыми вышла эта сборка, и сторонние лицензии.'**
  String get settingsLegalHelp;

  /// Палитра команд — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'ничего не найдено по «{said}»'**
  String commandPaletteNoMatch(String said);

  /// No description provided for @autorigTitle.
  ///
  /// In ru, this message translates to:
  /// **'Авториг'**
  String get autorigTitle;

  /// No description provided for @autorigCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать'**
  String get autorigCreate;

  /// No description provided for @autorigDragMarker.
  ///
  /// In ru, this message translates to:
  /// **'Перетащите маркер, чтобы уточнить сустав'**
  String get autorigDragMarker;

  /// No description provided for @autorigTemplate.
  ///
  /// In ru, this message translates to:
  /// **'Шаблон'**
  String get autorigTemplate;

  /// No description provided for @autorigHumanoid.
  ///
  /// In ru, this message translates to:
  /// **'Человек'**
  String get autorigHumanoid;

  /// No description provided for @autorigQuadruped.
  ///
  /// In ru, this message translates to:
  /// **'Четвероногое'**
  String get autorigQuadruped;

  /// No description provided for @autorigCustom.
  ///
  /// In ru, this message translates to:
  /// **'Свой'**
  String get autorigCustom;

  /// No description provided for @autorigComposition.
  ///
  /// In ru, this message translates to:
  /// **'Состав'**
  String get autorigComposition;

  /// No description provided for @autorigFingers.
  ///
  /// In ru, this message translates to:
  /// **'Пальцы рук'**
  String get autorigFingers;

  /// No description provided for @autorigToes.
  ///
  /// In ru, this message translates to:
  /// **'Пальцы ног'**
  String get autorigToes;

  /// No description provided for @autorigSpine.
  ///
  /// In ru, this message translates to:
  /// **'Позвоночник'**
  String get autorigSpine;

  /// No description provided for @autorigFaceBones.
  ///
  /// In ru, this message translates to:
  /// **'Кости лица'**
  String get autorigFaceBones;

  /// No description provided for @autorigIkChains.
  ///
  /// In ru, this message translates to:
  /// **'IK-цепи'**
  String get autorigIkChains;

  /// No description provided for @autorigController.
  ///
  /// In ru, this message translates to:
  /// **'Контроллер рига'**
  String get autorigController;

  /// No description provided for @autorigBinding.
  ///
  /// In ru, this message translates to:
  /// **'Привязка'**
  String get autorigBinding;

  /// No description provided for @autorigPrimaryWeights.
  ///
  /// In ru, this message translates to:
  /// **'Назначить основные веса'**
  String get autorigPrimaryWeights;

  /// No description provided for @autorigSymmetry.
  ///
  /// In ru, this message translates to:
  /// **'Симметрия'**
  String get autorigSymmetry;

  /// No description provided for @autorigBones.
  ///
  /// In ru, this message translates to:
  /// **'Костей'**
  String get autorigBones;

  /// No description provided for @autorigDeforming.
  ///
  /// In ru, this message translates to:
  /// **'Деформирующих'**
  String get autorigDeforming;

  /// No description provided for @autorigNone.
  ///
  /// In ru, this message translates to:
  /// **'Нет'**
  String get autorigNone;

  /// Авториг — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Маркеров {placed} из {total}'**
  String autorigMarkers(int placed, int total);

  /// No description provided for @brushSize.
  ///
  /// In ru, this message translates to:
  /// **'Размер'**
  String get brushSize;

  /// No description provided for @brushStrength.
  ///
  /// In ru, this message translates to:
  /// **'Сила'**
  String get brushStrength;

  /// No description provided for @sculptBrush.
  ///
  /// In ru, this message translates to:
  /// **'Кисть'**
  String get sculptBrush;

  /// No description provided for @sculptFalloffLinear.
  ///
  /// In ru, this message translates to:
  /// **'Линейное'**
  String get sculptFalloffLinear;

  /// No description provided for @sculptFalloffSmooth.
  ///
  /// In ru, this message translates to:
  /// **'Мягкое'**
  String get sculptFalloffSmooth;

  /// No description provided for @sculptFalloffSharp.
  ///
  /// In ru, this message translates to:
  /// **'Резкое'**
  String get sculptFalloffSharp;

  /// No description provided for @sculptSymmetryX.
  ///
  /// In ru, this message translates to:
  /// **'Симметрия (X)'**
  String get sculptSymmetryX;

  /// No description provided for @sculptSurface.
  ///
  /// In ru, this message translates to:
  /// **'Поверхность'**
  String get sculptSurface;

  /// No description provided for @sculptSubdivide.
  ///
  /// In ru, this message translates to:
  /// **'Подразделить'**
  String get sculptSubdivide;

  /// No description provided for @paintCanvas.
  ///
  /// In ru, this message translates to:
  /// **'Холст'**
  String get paintCanvas;

  /// No description provided for @paintNothingYet.
  ///
  /// In ru, this message translates to:
  /// **'Пока ничего не нарисовано'**
  String get paintNothingYet;

  /// No description provided for @paintLayers.
  ///
  /// In ru, this message translates to:
  /// **'Слои'**
  String get paintLayers;

  /// No description provided for @paintAddLayer.
  ///
  /// In ru, this message translates to:
  /// **'Добавить слой'**
  String get paintAddLayer;

  /// No description provided for @paintColour.
  ///
  /// In ru, this message translates to:
  /// **'Цвет'**
  String get paintColour;

  /// No description provided for @paintMask.
  ///
  /// In ru, this message translates to:
  /// **'Маска'**
  String get paintMask;

  /// No description provided for @paintMaskNone.
  ///
  /// In ru, this message translates to:
  /// **'Нет'**
  String get paintMaskNone;

  /// No description provided for @bakeRetopology.
  ///
  /// In ru, this message translates to:
  /// **'Ретопология'**
  String get bakeRetopology;

  /// No description provided for @bakeTargetQuads.
  ///
  /// In ru, this message translates to:
  /// **'Сколько квадов'**
  String get bakeTargetQuads;

  /// No description provided for @bakeRetopologize.
  ///
  /// In ru, this message translates to:
  /// **'Ретопологизировать'**
  String get bakeRetopologize;

  /// No description provided for @bakeMaps.
  ///
  /// In ru, this message translates to:
  /// **'Карты'**
  String get bakeMaps;

  /// No description provided for @bakeResolution.
  ///
  /// In ru, this message translates to:
  /// **'Разрешение'**
  String get bakeResolution;

  /// No description provided for @simKind.
  ///
  /// In ru, this message translates to:
  /// **'Вид'**
  String get simKind;

  /// No description provided for @simParameters.
  ///
  /// In ru, this message translates to:
  /// **'Параметры'**
  String get simParameters;

  /// No description provided for @simCollidesWith.
  ///
  /// In ru, this message translates to:
  /// **'Сталкивается с'**
  String get simCollidesWith;

  /// No description provided for @simNothingElse.
  ///
  /// In ru, this message translates to:
  /// **'В сцене больше ничего нет'**
  String get simNothingElse;

  /// No description provided for @simPinned.
  ///
  /// In ru, this message translates to:
  /// **'Закреплено'**
  String get simPinned;

  /// No description provided for @simClearPins.
  ///
  /// In ru, this message translates to:
  /// **'Снять закрепление'**
  String get simClearPins;

  /// No description provided for @simClearCache.
  ///
  /// In ru, this message translates to:
  /// **'Очистить кеш'**
  String get simClearCache;

  /// No description provided for @renderPasses.
  ///
  /// In ru, this message translates to:
  /// **'Проходы'**
  String get renderPasses;

  /// No description provided for @renderStart.
  ///
  /// In ru, this message translates to:
  /// **'Рендер'**
  String get renderStart;

  /// No description provided for @renderNothingYet.
  ///
  /// In ru, this message translates to:
  /// **'Пока ничего не отрендерено'**
  String get renderNothingYet;

  /// Скульптинг — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{count} граней'**
  String sculptFaces(int count);

  /// Рендер — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Отмена · {done}/{total}'**
  String renderCancelTiles(int done, int total);

  /// No description provided for @weightsBrush.
  ///
  /// In ru, this message translates to:
  /// **'Кисть'**
  String get weightsBrush;

  /// No description provided for @weightsPaint.
  ///
  /// In ru, this message translates to:
  /// **'Рисовать'**
  String get weightsPaint;

  /// No description provided for @weightsAssign.
  ///
  /// In ru, this message translates to:
  /// **'Назначить'**
  String get weightsAssign;

  /// No description provided for @weightsRadius.
  ///
  /// In ru, this message translates to:
  /// **'Радиус'**
  String get weightsRadius;

  /// No description provided for @weightsMirror.
  ///
  /// In ru, this message translates to:
  /// **'Зеркалить'**
  String get weightsMirror;

  /// No description provided for @weightsNormalize.
  ///
  /// In ru, this message translates to:
  /// **'Нормализовать'**
  String get weightsNormalize;

  /// No description provided for @weightsSelectedVertex.
  ///
  /// In ru, this message translates to:
  /// **'Выбранная вершина'**
  String get weightsSelectedVertex;

  /// No description provided for @weightsNoVertex.
  ///
  /// In ru, this message translates to:
  /// **'Под кистью пока нет вершины'**
  String get weightsNoVertex;

  /// No description provided for @weightsNoInfluences.
  ///
  /// In ru, this message translates to:
  /// **'На эту вершину ничто не влияет'**
  String get weightsNoInfluences;

  /// No description provided for @weightsBones.
  ///
  /// In ru, this message translates to:
  /// **'Кости'**
  String get weightsBones;

  /// No description provided for @weightsNoBones.
  ///
  /// In ru, this message translates to:
  /// **'Костей нет'**
  String get weightsNoBones;

  /// No description provided for @morphsNoShapeKeys.
  ///
  /// In ru, this message translates to:
  /// **'У этого объекта нет ключей формы'**
  String get morphsNoShapeKeys;

  /// No description provided for @morphsAddDriver.
  ///
  /// In ru, this message translates to:
  /// **'Добавить драйвер'**
  String get morphsAddDriver;

  /// No description provided for @morphsKeyShape.
  ///
  /// In ru, this message translates to:
  /// **'Поставить ключ на форму'**
  String get morphsKeyShape;

  /// No description provided for @morphsRemoveDriver.
  ///
  /// In ru, this message translates to:
  /// **'Удалить драйвер'**
  String get morphsRemoveDriver;

  /// No description provided for @morphsFrom.
  ///
  /// In ru, this message translates to:
  /// **'От°'**
  String get morphsFrom;

  /// No description provided for @morphsTo.
  ///
  /// In ru, this message translates to:
  /// **'До°'**
  String get morphsTo;

  /// No description provided for @retargetRootMotion.
  ///
  /// In ru, this message translates to:
  /// **'Движение корня'**
  String get retargetRootMotion;

  /// No description provided for @retargetCorrections.
  ///
  /// In ru, this message translates to:
  /// **'Поправки'**
  String get retargetCorrections;

  /// No description provided for @retargetLockFeet.
  ///
  /// In ru, this message translates to:
  /// **'Зафиксировать стопы'**
  String get retargetLockFeet;

  /// No description provided for @retargetGroundY.
  ///
  /// In ru, this message translates to:
  /// **'Уровень земли Y'**
  String get retargetGroundY;

  /// No description provided for @retargetFootTolerance.
  ///
  /// In ru, this message translates to:
  /// **'Допуск для стопы'**
  String get retargetFootTolerance;

  /// No description provided for @retargetApply.
  ///
  /// In ru, this message translates to:
  /// **'Применить ретаргет'**
  String get retargetApply;

  /// No description provided for @uvMethod.
  ///
  /// In ru, this message translates to:
  /// **'Метод'**
  String get uvMethod;

  /// No description provided for @uvMargin.
  ///
  /// In ru, this message translates to:
  /// **'Отступ'**
  String get uvMargin;

  /// No description provided for @uvIslands.
  ///
  /// In ru, this message translates to:
  /// **'Острова'**
  String get uvIslands;

  /// No description provided for @uvNoIslands.
  ///
  /// In ru, this message translates to:
  /// **'Островов нет'**
  String get uvNoIslands;

  /// No description provided for @transportKeys.
  ///
  /// In ru, this message translates to:
  /// **'Ключи'**
  String get transportKeys;

  /// No description provided for @transportCurves.
  ///
  /// In ru, this message translates to:
  /// **'Кривые'**
  String get transportCurves;

  /// No description provided for @transportLoop.
  ///
  /// In ru, this message translates to:
  /// **'Цикл'**
  String get transportLoop;

  /// Развёртка UV — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Остров {id}'**
  String uvIsland(int id);

  /// No description provided for @propDisplay.
  ///
  /// In ru, this message translates to:
  /// **'Отображение'**
  String get propDisplay;

  /// No description provided for @propMaterial.
  ///
  /// In ru, this message translates to:
  /// **'Материал'**
  String get propMaterial;

  /// No description provided for @propNormals.
  ///
  /// In ru, this message translates to:
  /// **'Нормали'**
  String get propNormals;

  /// No description provided for @propWire.
  ///
  /// In ru, this message translates to:
  /// **'Сетка'**
  String get propWire;

  /// No description provided for @propPerspective.
  ///
  /// In ru, this message translates to:
  /// **'Перспектива'**
  String get propPerspective;

  /// No description provided for @propOrthographic.
  ///
  /// In ru, this message translates to:
  /// **'Ортографическая'**
  String get propOrthographic;

  /// No description provided for @propView.
  ///
  /// In ru, this message translates to:
  /// **'Вид'**
  String get propView;

  /// No description provided for @propObjects.
  ///
  /// In ru, this message translates to:
  /// **'Объекты'**
  String get propObjects;

  /// No description provided for @propTransform.
  ///
  /// In ru, this message translates to:
  /// **'Преобразование'**
  String get propTransform;

  /// No description provided for @propSource.
  ///
  /// In ru, this message translates to:
  /// **'Источник'**
  String get propSource;

  /// No description provided for @propReimport.
  ///
  /// In ru, this message translates to:
  /// **'Переимпорт'**
  String get propReimport;

  /// No description provided for @propModifiers.
  ///
  /// In ru, this message translates to:
  /// **'Модификаторы'**
  String get propModifiers;

  /// No description provided for @propMorphs.
  ///
  /// In ru, this message translates to:
  /// **'Морфы'**
  String get propMorphs;

  /// No description provided for @propLastOperation.
  ///
  /// In ru, this message translates to:
  /// **'Последняя операция'**
  String get propLastOperation;

  /// No description provided for @propSelection.
  ///
  /// In ru, this message translates to:
  /// **'Выделение'**
  String get propSelection;

  /// No description provided for @propMesh.
  ///
  /// In ru, this message translates to:
  /// **'Меш'**
  String get propMesh;

  /// No description provided for @propHealth.
  ///
  /// In ru, this message translates to:
  /// **'Состояние'**
  String get propHealth;

  /// No description provided for @propBudget.
  ///
  /// In ru, this message translates to:
  /// **'Бюджет'**
  String get propBudget;

  /// No description provided for @importTitle.
  ///
  /// In ru, this message translates to:
  /// **'Импорт'**
  String get importTitle;

  /// No description provided for @importUnit.
  ///
  /// In ru, this message translates to:
  /// **'Единица'**
  String get importUnit;

  /// No description provided for @importUpAxis.
  ///
  /// In ru, this message translates to:
  /// **'Ось вверх'**
  String get importUpAxis;

  /// No description provided for @importWeld.
  ///
  /// In ru, this message translates to:
  /// **'Сварить совпадающие вершины'**
  String get importWeld;

  /// No description provided for @importWeldHelp.
  ///
  /// In ru, this message translates to:
  /// **'Строит настоящую топологию меша; оставьте выключенным, чтобы данные файла остались ровно такими, какими пришли.'**
  String get importWeldHelp;

  /// No description provided for @importRecalculateNormals.
  ///
  /// In ru, this message translates to:
  /// **'Пересчитать нормали'**
  String get importRecalculateNormals;

  /// No description provided for @importTriangulate.
  ///
  /// In ru, this message translates to:
  /// **'Триангулировать n-угольники'**
  String get importTriangulate;

  /// No description provided for @importLinkToSource.
  ///
  /// In ru, this message translates to:
  /// **'Связать с источником'**
  String get importLinkToSource;

  /// No description provided for @importLinkToSourceHelp.
  ///
  /// In ru, this message translates to:
  /// **'Запомнить, откуда это пришло, чтобы «Переимпорт» прочитал файл снова и сохранил преобразование, материалы и модификаторы.'**
  String get importLinkToSourceHelp;

  /// No description provided for @exportTitle.
  ///
  /// In ru, this message translates to:
  /// **'Экспорт'**
  String get exportTitle;

  /// No description provided for @exportTriangles.
  ///
  /// In ru, this message translates to:
  /// **'Треугольников'**
  String get exportTriangles;

  /// No description provided for @exportBakeTransforms.
  ///
  /// In ru, this message translates to:
  /// **'Запечь преобразования узлов'**
  String get exportBakeTransforms;

  /// No description provided for @exportBakeTransformsHelp.
  ///
  /// In ru, this message translates to:
  /// **'Переносит положение каждого объекта в его собственные вершины, чтобы файлу нечего было терять из иерархии.'**
  String get exportBakeTransformsHelp;

  /// No description provided for @exportApplyModifiers.
  ///
  /// In ru, this message translates to:
  /// **'Применить модификаторы'**
  String get exportApplyModifiers;

  /// No description provided for @exportApplyModifiersHelp.
  ///
  /// In ru, this message translates to:
  /// **'Пишет ту форму, которую вы видите, со свёрнутыми зеркалами и массивами. Выключено — пишется базовый меш.'**
  String get exportApplyModifiersHelp;

  /// No description provided for @exportSelectionOnly.
  ///
  /// In ru, this message translates to:
  /// **'Только выделенное'**
  String get exportSelectionOnly;

  /// No description provided for @exportSelectionOnlyHelp.
  ///
  /// In ru, this message translates to:
  /// **'Пишет то, что выделено, и всё, что под ним, оставляя остальной проект на месте.'**
  String get exportSelectionOnlyHelp;

  /// No description provided for @exportCompressTextures.
  ///
  /// In ru, this message translates to:
  /// **'Сжать текстуры (KTX2)'**
  String get exportCompressTextures;

  /// No description provided for @exportCompressTexturesHelp.
  ///
  /// In ru, this message translates to:
  /// **'Меньшие изображения, которые GPU читает без распаковки. Их понимает только читатель .f3d.'**
  String get exportCompressTexturesHelp;

  /// No description provided for @exportReady.
  ///
  /// In ru, this message translates to:
  /// **'готово к экспорту'**
  String get exportReady;

  /// No description provided for @exportShow.
  ///
  /// In ru, this message translates to:
  /// **'Показать'**
  String get exportShow;

  /// No description provided for @shortcutEdgeLoop.
  ///
  /// In ru, this message translates to:
  /// **'Выделить кольцо рёбер вдоль'**
  String get shortcutEdgeLoop;

  /// No description provided for @shortcutEdgeRing.
  ///
  /// In ru, this message translates to:
  /// **'Выделить кольцо рёбер поперёк'**
  String get shortcutEdgeRing;

  /// No description provided for @shortcutFinger.
  ///
  /// In ru, this message translates to:
  /// **'Палец'**
  String get shortcutFinger;

  /// No description provided for @shortcutFingerHeld.
  ///
  /// In ru, this message translates to:
  /// **'Палец, удержанный на месте'**
  String get shortcutFingerHeld;

  /// No description provided for @shortcutPen.
  ///
  /// In ru, this message translates to:
  /// **'Перо'**
  String get shortcutPen;

  /// No description provided for @shortcutPenOtherEnd.
  ///
  /// In ru, this message translates to:
  /// **'Обратная сторона пера'**
  String get shortcutPenOtherEnd;

  /// No description provided for @shortcutOrbit.
  ///
  /// In ru, this message translates to:
  /// **'Вращать'**
  String get shortcutOrbit;

  /// No description provided for @shortcutPan.
  ///
  /// In ru, this message translates to:
  /// **'Сдвигать'**
  String get shortcutPan;

  /// No description provided for @shortcutZoom.
  ///
  /// In ru, this message translates to:
  /// **'Приближать'**
  String get shortcutZoom;

  /// No description provided for @exportNothing.
  ///
  /// In ru, this message translates to:
  /// **'Нечего экспортировать'**
  String get exportNothing;

  /// Экспорт — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{triangles} из {budget} ({profile})'**
  String exportOfBudget(int triangles, int budget, String profile);

  /// No description provided for @shortcutEdgeLoopKeys.
  ///
  /// In ru, this message translates to:
  /// **'Alt и клик, в режиме меша'**
  String get shortcutEdgeLoopKeys;

  /// No description provided for @shortcutEdgeRingKeys.
  ///
  /// In ru, this message translates to:
  /// **'Ctrl или ⌘, вместе с Alt и кликом'**
  String get shortcutEdgeRingKeys;

  /// No description provided for @shortcutFingerKeys.
  ///
  /// In ru, this message translates to:
  /// **'Двигает камеру, каким бы инструментом ни целились'**
  String get shortcutFingerKeys;

  /// No description provided for @shortcutFingerHeldKeys.
  ///
  /// In ru, this message translates to:
  /// **'Открывает меню, не сдвинув камеру'**
  String get shortcutFingerHeldKeys;

  /// No description provided for @shortcutPenKeys.
  ///
  /// In ru, this message translates to:
  /// **'Рисует по модели, сильнее нажим — сильнее штрих'**
  String get shortcutPenKeys;

  /// No description provided for @shortcutPenOtherEndKeys.
  ///
  /// In ru, this message translates to:
  /// **'Тот же штрих, стирающий'**
  String get shortcutPenOtherEndKeys;

  /// No description provided for @shortcutPanKeys.
  ///
  /// In ru, this message translates to:
  /// **'Shift и то, чем вращают'**
  String get shortcutPanKeys;

  /// No description provided for @shortcutZoomKeys.
  ///
  /// In ru, this message translates to:
  /// **'Колесо или Ctrl с двумя пальцами'**
  String get shortcutZoomKeys;

  /// Импорт — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =1{1 предупреждение} few{{count} предупреждения} other{{count} предупреждений}}'**
  String importWarnings(int count);

  /// No description provided for @shortcutOrbitMiddle.
  ///
  /// In ru, this message translates to:
  /// **'Средняя кнопка, Alt с левой кнопкой или два пальца на трекпаде'**
  String get shortcutOrbitMiddle;

  /// No description provided for @shortcutOrbitLeft.
  ///
  /// In ru, this message translates to:
  /// **'Левая кнопка по пустому месту, средняя кнопка или два пальца на трекпаде'**
  String get shortcutOrbitLeft;

  /// No description provided for @actionSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get actionSave;

  /// No description provided for @actionExport.
  ///
  /// In ru, this message translates to:
  /// **'Экспорт'**
  String get actionExport;

  /// No description provided for @actionUndo.
  ///
  /// In ru, this message translates to:
  /// **'Отменить'**
  String get actionUndo;

  /// No description provided for @actionRedo.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get actionRedo;

  /// No description provided for @actionThisScreen.
  ///
  /// In ru, this message translates to:
  /// **'Этот экран'**
  String get actionThisScreen;

  /// No description provided for @actionCommandPalette.
  ///
  /// In ru, this message translates to:
  /// **'Палитра команд'**
  String get actionCommandPalette;

  /// No description provided for @actionFoldPanel.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть панель свойств'**
  String get actionFoldPanel;

  /// No description provided for @actionFoldRail.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть рельсу инструментов'**
  String get actionFoldRail;

  /// No description provided for @actionGrowSelection.
  ///
  /// In ru, this message translates to:
  /// **'Расширить выделение'**
  String get actionGrowSelection;

  /// No description provided for @actionShrinkSelection.
  ///
  /// In ru, this message translates to:
  /// **'Сузить выделение'**
  String get actionShrinkSelection;

  /// No description provided for @actionBrushNarrower.
  ///
  /// In ru, this message translates to:
  /// **'Кисть уже'**
  String get actionBrushNarrower;

  /// No description provided for @actionBrushWider.
  ///
  /// In ru, this message translates to:
  /// **'Кисть шире'**
  String get actionBrushWider;

  /// No description provided for @actionFrameSelection.
  ///
  /// In ru, this message translates to:
  /// **'Показать выделенное целиком'**
  String get actionFrameSelection;

  /// No description provided for @actionFrameAll.
  ///
  /// In ru, this message translates to:
  /// **'Показать всё целиком'**
  String get actionFrameAll;

  /// No description provided for @actionViewFront.
  ///
  /// In ru, this message translates to:
  /// **'Вид спереди'**
  String get actionViewFront;

  /// No description provided for @actionViewSide.
  ///
  /// In ru, this message translates to:
  /// **'Вид сбоку'**
  String get actionViewSide;

  /// No description provided for @actionViewTop.
  ///
  /// In ru, this message translates to:
  /// **'Вид сверху'**
  String get actionViewTop;

  /// No description provided for @actionPlayPause.
  ///
  /// In ru, this message translates to:
  /// **'Пуск и пауза'**
  String get actionPlayPause;

  /// No description provided for @actionSelectAll.
  ///
  /// In ru, this message translates to:
  /// **'Выделить всё'**
  String get actionSelectAll;

  /// No description provided for @actionSelectNone.
  ///
  /// In ru, this message translates to:
  /// **'Снять выделение'**
  String get actionSelectNone;

  /// No description provided for @actionInvertSelection.
  ///
  /// In ru, this message translates to:
  /// **'Инвертировать выделение'**
  String get actionInvertSelection;

  /// No description provided for @actionToggleObjectMesh.
  ///
  /// In ru, this message translates to:
  /// **'Объект и меш'**
  String get actionToggleObjectMesh;

  /// No description provided for @actionDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get actionDelete;

  /// No description provided for @matNoMaterials.
  ///
  /// In ru, this message translates to:
  /// **'Материалов нет'**
  String get matNoMaterials;

  /// No description provided for @matAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить материал'**
  String get matAdd;

  /// No description provided for @matUnassign.
  ///
  /// In ru, this message translates to:
  /// **'Снять назначение'**
  String get matUnassign;

  /// No description provided for @matOpenInEditor.
  ///
  /// In ru, this message translates to:
  /// **'Открыть в редакторе'**
  String get matOpenInEditor;

  /// No description provided for @matCutoff.
  ///
  /// In ru, this message translates to:
  /// **'Порог'**
  String get matCutoff;

  /// No description provided for @matAdvanced.
  ///
  /// In ru, this message translates to:
  /// **'Дополнительно'**
  String get matAdvanced;

  /// No description provided for @matEmissiveStrength.
  ///
  /// In ru, this message translates to:
  /// **'Сила свечения'**
  String get matEmissiveStrength;

  /// No description provided for @matNormalScale.
  ///
  /// In ru, this message translates to:
  /// **'Масштаб нормалей'**
  String get matNormalScale;

  /// No description provided for @matOcclusionStrength.
  ///
  /// In ru, this message translates to:
  /// **'Сила затенения'**
  String get matOcclusionStrength;

  /// No description provided for @matDoubleSided.
  ///
  /// In ru, this message translates to:
  /// **'Двусторонний'**
  String get matDoubleSided;

  /// No description provided for @sceneNoLights.
  ///
  /// In ru, this message translates to:
  /// **'Источников нет'**
  String get sceneNoLights;

  /// No description provided for @sceneRemoveLight.
  ///
  /// In ru, this message translates to:
  /// **'Убрать этот источник'**
  String get sceneRemoveLight;

  /// No description provided for @sceneAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get sceneAdd;

  /// No description provided for @sceneSource.
  ///
  /// In ru, this message translates to:
  /// **'Источник'**
  String get sceneSource;

  /// No description provided for @sceneIntensity.
  ///
  /// In ru, this message translates to:
  /// **'Яркость'**
  String get sceneIntensity;

  /// No description provided for @sceneRange.
  ///
  /// In ru, this message translates to:
  /// **'Дальность'**
  String get sceneRange;

  /// No description provided for @sceneCone.
  ///
  /// In ru, this message translates to:
  /// **'Конус'**
  String get sceneCone;

  /// No description provided for @sceneCastsShadow.
  ///
  /// In ru, this message translates to:
  /// **'Отбрасывает тень'**
  String get sceneCastsShadow;

  /// No description provided for @quickSetupTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настроить редактор'**
  String get quickSetupTitle;

  /// No description provided for @quickSetupHelp.
  ///
  /// In ru, this message translates to:
  /// **'Пять ответов, один раз. Каждый из них потом есть в настройках.'**
  String get quickSetupHelp;

  /// No description provided for @quickSetupCamera.
  ///
  /// In ru, this message translates to:
  /// **'Камера'**
  String get quickSetupCamera;

  /// No description provided for @quickSetupHowMuch.
  ///
  /// In ru, this message translates to:
  /// **'Сколько всего'**
  String get quickSetupHowMuch;

  /// No description provided for @quickSetupStart.
  ///
  /// In ru, this message translates to:
  /// **'Начать'**
  String get quickSetupStart;

  /// No description provided for @pivotHelp.
  ///
  /// In ru, this message translates to:
  /// **'Вокруг чего центрируется поворот или масштаб из полей выше'**
  String get pivotHelp;

  /// No description provided for @pivotMedian.
  ///
  /// In ru, this message translates to:
  /// **'Медиана'**
  String get pivotMedian;

  /// No description provided for @pivotIndividual.
  ///
  /// In ru, this message translates to:
  /// **'Каждый сам'**
  String get pivotIndividual;

  /// No description provided for @pivotCursor.
  ///
  /// In ru, this message translates to:
  /// **'3D-курсор'**
  String get pivotCursor;

  /// No description provided for @spaceHelp.
  ///
  /// In ru, this message translates to:
  /// **'В чьих осях задан поворот из полей выше'**
  String get spaceHelp;

  /// No description provided for @spaceGlobal.
  ///
  /// In ru, this message translates to:
  /// **'Глобальные'**
  String get spaceGlobal;

  /// No description provided for @spaceLocal.
  ///
  /// In ru, this message translates to:
  /// **'Локальные'**
  String get spaceLocal;

  /// No description provided for @modifierMirror.
  ///
  /// In ru, this message translates to:
  /// **'Зеркало'**
  String get modifierMirror;

  /// No description provided for @modifierArray.
  ///
  /// In ru, this message translates to:
  /// **'Массив'**
  String get modifierArray;

  /// No description provided for @modifierSmooth.
  ///
  /// In ru, this message translates to:
  /// **'Сглаживание'**
  String get modifierSmooth;

  /// No description provided for @modifierSubdivision.
  ///
  /// In ru, this message translates to:
  /// **'Подразделение'**
  String get modifierSubdivision;

  /// No description provided for @modifierBoolean.
  ///
  /// In ru, this message translates to:
  /// **'Булева операция'**
  String get modifierBoolean;

  /// No description provided for @modifierNone.
  ///
  /// In ru, this message translates to:
  /// **'Модификаторов нет'**
  String get modifierNone;

  /// No description provided for @modifierAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить модификатор'**
  String get modifierAdd;

  /// No description provided for @modifierAddShort.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get modifierAddShort;

  /// No description provided for @modifierRemove.
  ///
  /// In ru, this message translates to:
  /// **'Убрать'**
  String get modifierRemove;

  /// Стек модификаторов — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{before} → {after} треугольников'**
  String modifierTriangles(int before, int after);

  /// No description provided for @latheSegments.
  ///
  /// In ru, this message translates to:
  /// **'Сегментов'**
  String get latheSegments;

  /// No description provided for @latheClosed.
  ///
  /// In ru, this message translates to:
  /// **'Замкнутый профиль'**
  String get latheClosed;

  /// No description provided for @latheAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get latheAdd;

  /// No description provided for @latheTitle.
  ///
  /// In ru, this message translates to:
  /// **'Тело вращения'**
  String get latheTitle;

  /// No description provided for @saveAsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить как'**
  String get saveAsTitle;

  /// No description provided for @saveWithoutHistory.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить без истории'**
  String get saveWithoutHistory;

  /// No description provided for @saveWithoutHistoryHelp.
  ///
  /// In ru, this message translates to:
  /// **'После повторного открытия этого файла отмена будет недоступна.'**
  String get saveWithoutHistoryHelp;

  /// No description provided for @galleryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Галерея'**
  String get galleryTitle;

  /// No description provided for @galleryClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get galleryClose;

  /// No description provided for @gallerySearch.
  ///
  /// In ru, this message translates to:
  /// **'Искать в галерее'**
  String get gallerySearch;

  /// No description provided for @galleryAll.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get galleryAll;

  /// No description provided for @galleryNoCredit.
  ///
  /// In ru, this message translates to:
  /// **'Указание авторства не требуется'**
  String get galleryNoCredit;

  /// No description provided for @previewBudgets.
  ///
  /// In ru, this message translates to:
  /// **'Бюджеты'**
  String get previewBudgets;

  /// No description provided for @previewTitle.
  ///
  /// In ru, this message translates to:
  /// **'Превью'**
  String get previewTitle;

  /// No description provided for @previewClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть превью'**
  String get previewClose;

  /// No description provided for @previewWireframe.
  ///
  /// In ru, this message translates to:
  /// **'Показать сетку'**
  String get previewWireframe;

  /// No description provided for @previewNotBuilt.
  ///
  /// In ru, this message translates to:
  /// **'для этого экрана ещё не собрано'**
  String get previewNotBuilt;

  /// No description provided for @agentHide.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть панель агента'**
  String get agentHide;

  /// No description provided for @agentSession.
  ///
  /// In ru, this message translates to:
  /// **'Сессия'**
  String get agentSession;

  /// No description provided for @agentRenders.
  ///
  /// In ru, this message translates to:
  /// **'Рендеров'**
  String get agentRenders;

  /// No description provided for @agentToolCalls.
  ///
  /// In ru, this message translates to:
  /// **'Вызовов инструментов'**
  String get agentToolCalls;

  /// No description provided for @agentHistoryAuthor.
  ///
  /// In ru, this message translates to:
  /// **'История · автор'**
  String get agentHistoryAuthor;

  /// No description provided for @agentUndoSteps.
  ///
  /// In ru, this message translates to:
  /// **'Отменить шаги агента'**
  String get agentUndoSteps;

  /// No description provided for @agentContactSheet.
  ///
  /// In ru, this message translates to:
  /// **'КОНТАКТНЫЙ ЛИСТ'**
  String get agentContactSheet;

  /// No description provided for @agentInsteadOfNumbers.
  ///
  /// In ru, this message translates to:
  /// **'что агент получает вместо чисел'**
  String get agentInsteadOfNumbers;

  /// No description provided for @agentNoRenderYet.
  ///
  /// In ru, this message translates to:
  /// **'В этой сессии ещё не было вызова render/renderSheet'**
  String get agentNoRenderYet;

  /// No description provided for @graphNextImage.
  ///
  /// In ru, this message translates to:
  /// **'Следующее изображение'**
  String get graphNextImage;

  /// No description provided for @graphAddNode.
  ///
  /// In ru, this message translates to:
  /// **'Добавить узел'**
  String get graphAddNode;

  /// No description provided for @graphTitle.
  ///
  /// In ru, this message translates to:
  /// **'Граф текстур'**
  String get graphTitle;

  /// No description provided for @legalTitle.
  ///
  /// In ru, this message translates to:
  /// **'Юридическое'**
  String get legalTitle;

  /// No description provided for @legalClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get legalClose;

  /// No description provided for @legalDocument.
  ///
  /// In ru, this message translates to:
  /// **'Документ'**
  String get legalDocument;

  /// No description provided for @legalEnglishOnly.
  ///
  /// In ru, this message translates to:
  /// **'Эти документы публикуются только на английском, каким бы ни был язык интерфейса: одна подлинная версия, чтобы не было вопроса, какая из них обязывает.'**
  String get legalEnglishOnly;

  /// No description provided for @legalThirdParty.
  ///
  /// In ru, this message translates to:
  /// **'Сторонние лицензии'**
  String get legalThirdParty;

  /// No description provided for @budgetTriangles.
  ///
  /// In ru, this message translates to:
  /// **'Треугольники'**
  String get budgetTriangles;

  /// No description provided for @budgetJoints.
  ///
  /// In ru, this message translates to:
  /// **'Суставы'**
  String get budgetJoints;

  /// No description provided for @budgetTextureMemory.
  ///
  /// In ru, this message translates to:
  /// **'Память текстур'**
  String get budgetTextureMemory;

  /// No description provided for @budgetInfluences.
  ///
  /// In ru, this message translates to:
  /// **'Влияния'**
  String get budgetInfluences;

  /// No description provided for @consoleAll.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get consoleAll;

  /// No description provided for @consoleYou.
  ///
  /// In ru, this message translates to:
  /// **'Вы'**
  String get consoleYou;

  /// No description provided for @consoleAgent.
  ///
  /// In ru, this message translates to:
  /// **'Агент'**
  String get consoleAgent;

  /// No description provided for @consoleClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть консоль'**
  String get consoleClose;

  /// Превью — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{lights} источников · {shadowed}/{cap} с тенью'**
  String previewLights(int lights, int shadowed, int cap);

  /// Панель агента — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{agent} агента · {person} ваших'**
  String agentSteps(int agent, int person);

  /// Экспорт — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'и ещё {count}'**
  String exportAnywayMore(int count);

  /// Юридический экран — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Документы не загрузились: {error}'**
  String legalLoadFailed(String error);

  /// Оверлей метрик — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{fps} кадр/с'**
  String metricsFps(int fps);

  /// Оверлей метрик — ux-22. Число уже отформатировано.
  ///
  /// In ru, this message translates to:
  /// **'{count} вызовов отрисовки'**
  String metricsDrawCalls(String count);

  /// Оверлей метрик — ux-22. Число уже отформатировано.
  ///
  /// In ru, this message translates to:
  /// **'{count} треугольников'**
  String metricsTriangles(String count);

  /// Оверлей метрик — ux-22. Число уже отформатировано.
  ///
  /// In ru, this message translates to:
  /// **'{count} костей'**
  String metricsBones(String count);

  /// Заголовок разбивки по проходам кадра — gfx-01n.
  ///
  /// In ru, this message translates to:
  /// **'Проходы кадра'**
  String get metricsPasses;

  /// Одна строка разбивки по проходам — gfx-01n. Числа уже отформатированы.
  ///
  /// In ru, this message translates to:
  /// **'{name} · {ms} мс · {draws} выз. · {triangles} тр.'**
  String metricsPassLine(
    String name,
    String ms,
    String draws,
    String triangles,
  );

  /// Заголовок панели снимка кадра — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'Снимок кадра'**
  String get captureTitle;

  /// Кнопка, снимающая следующий кадр — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'Снять кадр'**
  String get captureTake;

  /// Снимок запрошен, ответа ещё нет — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'Снимаем…'**
  String get captureWaiting;

  /// Панель открыта, снимков не делали — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'Снимков ещё нет'**
  String get captureEmpty;

  /// Строка прохода в снимке — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'{name} · изображений: {images}'**
  String capturePassLine(String name, String images);

  /// Проход был в графе, но сказал, что делать нечего — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'{name} · не выполнялся'**
  String captureInactive(String name);

  /// Что проход читает, по именам ресурсов графа — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'читает {names}'**
  String captureReads(String names);

  /// Что проход пишет, по именам ресурсов графа — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'пишет {names}'**
  String captureWrites(String names);

  /// Ресурс, который проход оставил полностью чёрным — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'{name} вернулся чёрным'**
  String captureBlack(String name);

  /// Почему у ресурса нет пикселей — gfx-70n.
  ///
  /// In ru, this message translates to:
  /// **'{name}: {reason}'**
  String captureRefused(String name, String reason);

  /// Галерея — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось достучаться: {names}; всё остальное на месте'**
  String galleryUnreachable(String names);

  /// No description provided for @graphNextImageTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Следующее изображение'**
  String get graphNextImageTooltip;

  /// No description provided for @statusShowFolder.
  ///
  /// In ru, this message translates to:
  /// **'Показать папку'**
  String get statusShowFolder;

  /// No description provided for @envClearPanorama.
  ///
  /// In ru, this message translates to:
  /// **'Убрать панораму'**
  String get envClearPanorama;

  /// No description provided for @envAmbient.
  ///
  /// In ru, this message translates to:
  /// **'Окружающий свет'**
  String get envAmbient;

  /// No description provided for @animActions.
  ///
  /// In ru, this message translates to:
  /// **'Действия'**
  String get animActions;

  /// Строка состояния — ux-22. Число уже отформатировано.
  ///
  /// In ru, this message translates to:
  /// **'{density} тексел/см'**
  String statusTexelDensity(String density);

  /// Строка состояния — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{used} МБ из {budget}'**
  String statusTextureBudget(String used, String budget);

  /// Строка состояния — ux-22. Число уже отформатировано.
  ///
  /// In ru, this message translates to:
  /// **'{ms} мс'**
  String statusFrameTime(String ms);

  /// No description provided for @animSkeleton.
  ///
  /// In ru, this message translates to:
  /// **'Скелет'**
  String get animSkeleton;

  /// No description provided for @animConstraints.
  ///
  /// In ru, this message translates to:
  /// **'Ограничения'**
  String get animConstraints;

  /// No description provided for @crashTitle.
  ///
  /// In ru, this message translates to:
  /// **'Что-то пошло не так'**
  String get crashTitle;

  /// No description provided for @crashDismiss.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get crashDismiss;

  /// No description provided for @crashReport.
  ///
  /// In ru, this message translates to:
  /// **'Сообщить о проблеме'**
  String get crashReport;

  /// No description provided for @postBloom.
  ///
  /// In ru, this message translates to:
  /// **'Свечение'**
  String get postBloom;

  /// No description provided for @postExposure.
  ///
  /// In ru, this message translates to:
  /// **'Экспозиция'**
  String get postExposure;

  /// No description provided for @playStop.
  ///
  /// In ru, this message translates to:
  /// **'Стоп'**
  String get playStop;

  /// No description provided for @playReload.
  ///
  /// In ru, this message translates to:
  /// **'Перезапустить'**
  String get playReload;

  /// No description provided for @operationNothingDone.
  ///
  /// In ru, this message translates to:
  /// **'пока ничего не сделано'**
  String get operationNothingDone;

  /// No description provided for @operationHide.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть карточку'**
  String get operationHide;

  /// No description provided for @operationHideHelp.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть карточку, не отменяя действие'**
  String get operationHideHelp;

  /// No description provided for @operationNothingToAdjust.
  ///
  /// In ru, this message translates to:
  /// **'нечего настраивать'**
  String get operationNothingToAdjust;

  /// No description provided for @studioTitle.
  ///
  /// In ru, this message translates to:
  /// **'Студия материалов'**
  String get studioTitle;

  /// No description provided for @studioClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get studioClose;

  /// No description provided for @constraintsNone.
  ///
  /// In ru, this message translates to:
  /// **'Ограничений нет'**
  String get constraintsNone;

  /// No description provided for @constraintsRemove.
  ///
  /// In ru, this message translates to:
  /// **'Убрать это ограничение'**
  String get constraintsRemove;

  /// No description provided for @clipBlend.
  ///
  /// In ru, this message translates to:
  /// **'Смешение'**
  String get clipBlend;

  /// No description provided for @clipPreview.
  ///
  /// In ru, this message translates to:
  /// **'Превью'**
  String get clipPreview;

  /// No description provided for @boneMapTitle.
  ///
  /// In ru, this message translates to:
  /// **'Карта костей'**
  String get boneMapTitle;

  /// No description provided for @boneMapAuto.
  ///
  /// In ru, this message translates to:
  /// **'Сопоставить автоматически'**
  String get boneMapAuto;

  /// No description provided for @animPickAction.
  ///
  /// In ru, this message translates to:
  /// **'Выберите или добавьте действие, чтобы увидеть таймлайн'**
  String get animPickAction;

  /// No description provided for @animPickTrack.
  ///
  /// In ru, this message translates to:
  /// **'Выберите дорожку в режиме ключей, чтобы увидеть кривую'**
  String get animPickTrack;

  /// No description provided for @startFrom.
  ///
  /// In ru, this message translates to:
  /// **'Начать с'**
  String get startFrom;

  /// No description provided for @dialogClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get dialogClose;

  /// No description provided for @nameField.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get nameField;

  /// No description provided for @healthNothingWrong.
  ///
  /// In ru, this message translates to:
  /// **'С ним всё в порядке'**
  String get healthNothingWrong;

  /// No description provided for @clipSearch.
  ///
  /// In ru, this message translates to:
  /// **'Искать клипы'**
  String get clipSearch;

  /// No description provided for @clipNoSource.
  ///
  /// In ru, this message translates to:
  /// **'Источник ещё не импортирован'**
  String get clipNoSource;

  /// No description provided for @actionsNone.
  ///
  /// In ru, this message translates to:
  /// **'Действий нет'**
  String get actionsNone;

  /// No description provided for @actionsAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get actionsAdd;

  /// No description provided for @weightsPickBone.
  ///
  /// In ru, this message translates to:
  /// **'Выберите кость, чтобы проверить сгиб'**
  String get weightsPickBone;

  /// Карточка падения — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Команда: {name}'**
  String crashCommand(String name);

  /// Карточка падения — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Последние команды: {names}'**
  String crashRecent(String names);

  /// Игровой экран — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{template}  ·  WASD — идти, тянуть — смотреть, Esc — выйти'**
  String playHint(String template);

  /// Полоса кеша симуляции — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Кеш симуляции: запечено {baked} из {target} кадров'**
  String simCacheSemantics(int baked, int target);

  /// Полоса кеша симуляции — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{baked} / {target} кадров в кеше'**
  String simCacheReadout(int baked, int target);

  /// Панель состояния меша — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'{message}, выделить их'**
  String healthSelectThem(String message);

  /// Полоса зон LOD — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Порог LOD {index}'**
  String lodThreshold(int index);

  /// Библиотека клипов — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Ни один клип не подходит под «{query}»'**
  String clipNoMatch(String query);

  /// Ретопология — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Печётся карт: {count}…'**
  String bakingMaps(int count);

  /// No description provided for @outlinerToTopLevel.
  ///
  /// In ru, this message translates to:
  /// **'на верхний уровень'**
  String get outlinerToTopLevel;

  /// No description provided for @retargetImportSource.
  ///
  /// In ru, this message translates to:
  /// **'Импортируйте исходный клип'**
  String get retargetImportSource;

  /// No description provided for @skeletonNoJoints.
  ///
  /// In ru, this message translates to:
  /// **'Суставов нет'**
  String get skeletonNoJoints;

  /// Режим сцены — ux-22.
  ///
  /// In ru, this message translates to:
  /// **'Источник {number} · {kind}'**
  String sceneLightNamed(int number, String kind);

  /// No description provided for @healthTriangulate.
  ///
  /// In ru, this message translates to:
  /// **'Триангулировать'**
  String get healthTriangulate;

  /// No description provided for @healthFill.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get healthFill;

  /// No description provided for @healthMerge.
  ///
  /// In ru, this message translates to:
  /// **'Слить'**
  String get healthMerge;

  /// No description provided for @healthRecalculate.
  ///
  /// In ru, this message translates to:
  /// **'Пересчитать'**
  String get healthRecalculate;

  /// No description provided for @healthFix.
  ///
  /// In ru, this message translates to:
  /// **'Исправить'**
  String get healthFix;

  /// No description provided for @budgetProfile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get budgetProfile;

  /// No description provided for @importBounds.
  ///
  /// In ru, this message translates to:
  /// **'Габариты'**
  String get importBounds;

  /// No description provided for @propWhat.
  ///
  /// In ru, this message translates to:
  /// **'Что'**
  String get propWhat;

  /// No description provided for @envNone.
  ///
  /// In ru, this message translates to:
  /// **'Нет'**
  String get envNone;

  /// No description provided for @envStudio.
  ///
  /// In ru, this message translates to:
  /// **'Студия'**
  String get envStudio;

  /// No description provided for @envDaylight.
  ///
  /// In ru, this message translates to:
  /// **'Дневной свет'**
  String get envDaylight;

  /// No description provided for @envSunset.
  ///
  /// In ru, this message translates to:
  /// **'Закат'**
  String get envSunset;
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
