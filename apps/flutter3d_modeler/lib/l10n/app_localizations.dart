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
