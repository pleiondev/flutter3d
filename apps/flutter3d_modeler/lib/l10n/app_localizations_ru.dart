// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'flutter3d modeller';

  @override
  String get unsavedChangesTitle => 'Несохранённые изменения';

  @override
  String get unsavedChangesBody =>
      'В этой модели есть изменения, которые не были сохранены.';

  @override
  String get keepEditing => 'Продолжить редактирование';

  @override
  String get discard => 'Не сохранять';

  @override
  String get saveAndClose => 'Сохранить и закрыть';

  @override
  String get restoreUnsavedChangesTitle =>
      'Восстановить несохранённые изменения?';

  @override
  String restoreUnsavedChangesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объекта).',
      many:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объектов).',
      few:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объекта).',
      one:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объект).',
    );
    return '$_temp0';
  }

  @override
  String get restore => 'Восстановить';

  @override
  String get exportAnywayTitle => 'Всё равно экспортировать?';

  @override
  String exportAnywayMoreIssues(int count) {
    return 'и ещё $count';
  }

  @override
  String get cancel => 'Отмена';

  @override
  String get exportAnyway => 'Всё равно экспортировать';

  @override
  String get addPrimitiveTooltip => 'Добавить примитив';

  @override
  String get add => 'Добавить';

  @override
  String get open => 'Открыть';

  @override
  String get save => 'Сохранить';

  @override
  String get exportTooltip => 'Экспортировать копию';

  @override
  String get export => 'Экспорт';

  @override
  String get materialStudioSemanticsLabel => 'Материал-студия';

  @override
  String get materialStudioTooltip =>
      'Материал-студия — предпросмотр материала';

  @override
  String get keyboardShortcuts => 'Горячие клавиши';

  @override
  String get keyboardShortcutsTooltip => 'Горячие клавиши (?)';

  @override
  String get startScreenSemanticsLabel => 'Стартовый экран';

  @override
  String get startScreenTooltip =>
      'Стартовый экран — открыть файл или начать новый проект';

  @override
  String get reportProblem => 'Сообщить о проблеме';

  @override
  String get sectionDisplay => 'Отображение';

  @override
  String get sectionView => 'Вид';

  @override
  String get sectionObjects => 'Объекты';

  @override
  String get sectionTransform => 'Трансформация';

  @override
  String get sectionModifiers => 'Модификаторы';

  @override
  String get sectionLastOperation => 'Последняя операция';

  @override
  String get sectionSelection => 'Выделение';

  @override
  String get sectionMesh => 'Меш';

  @override
  String get sectionBudget => 'Бюджет';

  @override
  String get rowWhat => 'Что';

  @override
  String get rowVertices => 'Вершины';

  @override
  String get rowFaces => 'Грани';

  @override
  String get rowTriangles => 'Треугольники';

  @override
  String get rowProfile => 'Профиль';

  @override
  String get shadingMaterial => 'Материал';

  @override
  String get shadingNormals => 'Нормали';

  @override
  String get shadingWire => 'Каркас';

  @override
  String get lensPerspective => 'Перспектива';

  @override
  String get lensOrthographic => 'Ортографическая';

  @override
  String get viewFront => 'Спереди';

  @override
  String get viewBack => 'Сзади';

  @override
  String get viewLeft => 'Слева';

  @override
  String get viewRight => 'Справа';

  @override
  String get viewTop => 'Сверху';

  @override
  String get viewBottom => 'Снизу';

  @override
  String get recoverUnsavedChangesTitle =>
      'Восстановить несохранённые изменения?';

  @override
  String get recoverUnsavedChangesBody =>
      'Найдена автосохранённая версия новее последнего сохранённого файла. Восстановить её или открыть файл в том виде, в каком он был сохранён?';

  @override
  String get openSavedFile => 'Открыть сохранённый файл';

  @override
  String get restoreAutosave => 'Восстановить автосохранение';

  @override
  String get startTitle => 'Начало';

  @override
  String get openFile => 'Открыть файл';

  @override
  String get newProject => 'Новый проект';

  @override
  String get recent => 'Недавние';

  @override
  String get tutorial => 'Обучение';

  @override
  String get close => 'Закрыть';

  @override
  String sceneStatusLabel(int lightCount, int shadowedCount, int shadowCap) {
    return 'Источников $lightCount · теневых $shadowedCount из $shadowCap';
  }

  @override
  String get sceneEnvironmentSectionLabel => 'Окружение';

  @override
  String get sceneShadowsSectionLabel => 'Тени';

  @override
  String get sceneShadowsToggleLabel => 'Тени';

  @override
  String get sceneSourcesSectionLabel => 'Источники';

  @override
  String get scenePostSectionLabel => 'Пост';

  @override
  String get bakeTextureButtonLabel => 'Запечь 2048²';

  @override
  String get resetPoseButtonLabel => 'Сбросить позу';

  @override
  String get toolObjectSelectLabel => 'Выделение';

  @override
  String get toolObjectSelectAbout =>
      'Клик по объекту берёт его в работу; с Shift — добавляет к уже выбранному.';

  @override
  String get toolObjectMoveLabel => 'Перемещение';

  @override
  String get toolObjectMoveAbout =>
      'Тяните стрелку, чтобы двигать вдоль одной оси, или центр — чтобы свободно.';

  @override
  String get toolObjectRotateLabel => 'Поворот';

  @override
  String get toolObjectRotateAbout =>
      'Тяните кольцо, чтобы повернуть вокруг этой оси.';

  @override
  String get toolObjectScaleLabel => 'Масштаб';

  @override
  String get toolObjectScaleAbout =>
      'Тяните ручку, чтобы растянуть или сжать — по одной оси или сразу по трём от центра.';

  @override
  String get toolObjectAddLabel => 'Добавить куб';

  @override
  String get toolObjectAddAbout =>
      'Ставит новый куб в начале координат, всё ещё параметрический: размеры и разбиение правятся в панели.';

  @override
  String get toolObjectDuplicateLabel => 'Дублировать';

  @override
  String get toolObjectDuplicateAbout =>
      'Копирует выделенное и выделяет копию, оставляя оригинал на месте.';

  @override
  String get toolObjectBakeLabel => 'Превратить в меш';

  @override
  String get toolObjectBakeAbout =>
      'Превращает форму, помнящую свои параметры, в обычную правимую геометрию. Поля размеров и разбиения исчезают.';

  @override
  String get toolObjectLatheLabel => 'Добавить тело вращения';

  @override
  String get toolObjectLatheAbout =>
      'Вращает нарисованный профиль вокруг оси — так делаются ваза, бутылка или колесо.';

  @override
  String get toolObjectOriginLabel => 'Опорную точку вниз';

  @override
  String get toolObjectOriginAbout =>
      'Опускает точку, вокруг которой объект поворачивается и масштабируется, к самой нижней вершине — объект встаёт на пол.';

  @override
  String get toolObjectApplyLabel => 'Применить трансформацию';

  @override
  String get toolObjectApplyAbout =>
      'Вживляет положение, поворот и масштаб в сами вершины и обнуляет трансформацию.';

  @override
  String get toolObjectDeleteLabel => 'Удалить';

  @override
  String get toolObjectDeleteAbout => 'Убирает выделенное. Отмена возвращает.';

  @override
  String get toolMeshSelectLabel => 'Выделение';

  @override
  String get toolMeshSelectAbout =>
      'Клик по вершине, ребру или грани; с Shift — добавляет к уже выбранному.';

  @override
  String get toolMeshLassoLabel => 'Лассо';

  @override
  String get toolMeshLassoAbout =>
      'Обведите нужное от руки вместо того, чтобы кликать каждую часть.';

  @override
  String get toolMeshLinkedLabel => 'Выделить связное';

  @override
  String get toolMeshLinkedAbout =>
      'Берёт всё, что соединено с уже выбранным, — целую оболочку меша, если их несколько.';

  @override
  String get toolMeshMoveLabel => 'Перемещение';

  @override
  String get toolMeshMoveAbout =>
      'Двигает выбранные элементы. Число, набранное во время перетаскивания, задаёт расстояние точно.';

  @override
  String get toolMeshRotateLabel => 'Поворот';

  @override
  String get toolMeshRotateAbout =>
      'Поворачивает выбранные элементы вокруг центра выделения.';

  @override
  String get toolMeshScaleLabel => 'Масштаб';

  @override
  String get toolMeshScaleAbout =>
      'Растягивает или сжимает выбранные элементы относительно центра выделения.';

  @override
  String get toolMeshExtrudeLabel => 'Выдавливание';

  @override
  String get toolMeshExtrudeAbout =>
      'Вытягивает новую геометрию из выбранных граней и оставляет стенку, соединяющую её с тем, откуда она вышла.';

  @override
  String get toolMeshLoopCutLabel => 'Кольцевой разрез';

  @override
  String get toolMeshLoopCutAbout =>
      'Добавляет кольцо рёбер вокруг всего меша — там, где следующему изгибу нужно место.';

  @override
  String get toolMeshBevelLabel => 'Фаска';

  @override
  String get toolMeshBevelAbout =>
      'Заменяет острое ребро узкой полоской, чтобы свет ложился на неё как на настоящем предмете.';

  @override
  String get toolMeshInsetLabel => 'Врезка';

  @override
  String get toolMeshInsetAbout =>
      'Сжимает грань внутрь и застраивает оставшееся кольцо — так делаются панель, окно или утопленная кнопка.';

  @override
  String get toolMeshBridgeLabel => 'Мост';

  @override
  String get toolMeshBridgeAbout =>
      'Соединяет две открытые границы кольцом четырёхугольников: две половины трубы становятся одной поверхностью.';

  @override
  String get toolMeshSlideLabel => 'Сдвиг рёбер';

  @override
  String get toolMeshSlideAbout =>
      'Двигает петлю вдоль пересекающих её рёбер: шов переезжает, но ни одна грань не меняется.';

  @override
  String get toolMeshTriangulateLabel => 'Триангуляция';

  @override
  String get toolMeshTriangulateAbout =>
      'Режет каждую грань на треугольники — то, что читает игровой движок, и то, чем сначала должна стать грань больше чем с четырьмя углами.';

  @override
  String get toolMeshSeparateLabel => 'Отделить';

  @override
  String get toolMeshSeparateAbout =>
      'Выносит выбранные грани в отдельный объект.';

  @override
  String get toolMeshDissolveLabel => 'Растворить рёбра';

  @override
  String get toolMeshDissolveAbout =>
      'Убирает выбранные рёбра, сохраняя поверхность: разделённые ими грани сливаются в одну.';

  @override
  String get toolMeshFillHolesLabel => 'Заполнить дыры';

  @override
  String get toolMeshFillHolesAbout =>
      'Закрывает каждую открытую границу — те щели, из-за которых модель просвечивает с одной стороны.';

  @override
  String get toolMeshMergeLabel => 'Сшить по расстоянию';

  @override
  String get toolMeshMergeAbout =>
      'Сплавляет вершины, лежащие одна на другой, — то, чем полны скан и STL.';

  @override
  String get toolMeshNormalsLabel => 'Пересчитать нормали';

  @override
  String get toolMeshNormalsAbout =>
      'Разворачивает каждую грань наружу, чтобы поверхность перестала читаться вывернутой.';

  @override
  String get toolMeshFlipLabel => 'Развернуть нормали';

  @override
  String get toolMeshFlipAbout =>
      'Поворачивает выбранные грани в другую сторону — для оболочки, которую и правда смотрят изнутри.';

  @override
  String get toolMeshDeleteLabel => 'Удалить';

  @override
  String get toolMeshDeleteAbout =>
      'Убирает выбранные вершины, рёбра или грани и всё, что на них держалось.';

  @override
  String get toolPoseSelectLabel => 'Выделение';

  @override
  String get toolPoseSelectAbout => 'Клик по суставу скелета берёт его в позу.';

  @override
  String get toolPoseKeyLabel => 'Ключ позы';

  @override
  String get toolPoseKeyAbout =>
      'Записывает позу с экрана в клип, на кадре, где стоит бегунок.';

  @override
  String get toolPoseDeleteKeyLabel => 'Удалить ключ';

  @override
  String get toolPoseDeleteKeyAbout =>
      'Убирает ключ этого кадра, оставляя соседние вести движение сквозь него.';

  @override
  String get toolPoseAutoRigLabel => 'Автоскелет…';

  @override
  String get toolPoseAutoRigAbout =>
      'Строит скелет по горсти точек, которые вы расставляете на модели.';

  @override
  String get toolWeightsPaintLabel => 'Красить веса';

  @override
  String get toolWeightsPaintAbout =>
      'Кистью задаёт, насколько сильно выбранный сустав тянет поверхность под курсором.';

  @override
  String get toolWeightsAssignLabel => 'Привязать к суставу';

  @override
  String get toolWeightsAssignAbout =>
      'Отдаёт выбранному суставу каждую вершину, которой коснулась кисть, — на полную силу.';

  @override
  String get toolWeightsMirrorLabel => 'Отзеркалить';

  @override
  String get toolWeightsMirrorAbout =>
      'Копирует веса одной стороны на другую: симметричная модель красится один раз.';

  @override
  String get toolWeightsNormalizeLabel => 'Нормализовать';

  @override
  String get toolWeightsNormalizeAbout =>
      'Сводит тяги каждой вершины в сумму, равную единице, и отбрасывает самые слабые сверх её собственного предела.';

  @override
  String get toolRetargetImportLabel => 'Импортировать клип-источник';

  @override
  String get toolRetargetImportAbout =>
      'Читает клип из другого файла, чтобы вести этим ригом.';

  @override
  String get toolRetargetAutoMapLabel => 'Сопоставить кости автоматически';

  @override
  String get toolRetargetAutoMapAbout =>
      'Угадывает по именам, какая кость источника какой кости этого рига соответствует.';

  @override
  String get toolRetargetApplyLabel => 'Применить перенос';

  @override
  String get toolRetargetApplyAbout =>
      'Записывает перенесённое движение на этот риг как собственный клип.';

  @override
  String get toolMorphsAddLabel => 'Добавить форму';

  @override
  String get toolMorphsAddAbout =>
      'Берёт меш как он есть сейчас — как форму, к которой будет вести ползунок.';

  @override
  String get toolMorphsKeyLabel => 'Ключ формы';

  @override
  String get toolMorphsKeyAbout =>
      'Записывает веса форм как они есть в клип, на кадре бегунка.';

  @override
  String get toolMorphsDeleteLabel => 'Удалить форму';

  @override
  String get toolMorphsDeleteAbout =>
      'Убирает выбранную форму и ползунок, который её вёл.';

  @override
  String get primitiveBox => 'Куб';

  @override
  String get primitivePlane => 'Плоскость';

  @override
  String get primitiveSphere => 'Сфера';

  @override
  String get primitiveCylinder => 'Цилиндр';

  @override
  String get primitiveTorus => 'Тор';

  @override
  String get openTooltip => 'Открыть файл — заменяет всё, что открыто сейчас';

  @override
  String get importTooltip =>
      'Импортировать файл — добавляет его к тому, что уже открыто';

  @override
  String get import => 'Импорт';

  @override
  String get saveTooltipDirty => 'Сохранить — есть несохранённые изменения';

  @override
  String get saveTooltipClean => 'Сохранить — всё записано';

  @override
  String get saveToCabinet => 'Сохранить в кабинет';

  @override
  String get splitViewportSemanticsLabel => 'Разделить вьюпорт';

  @override
  String get splitViewportOn =>
      'Разделить вьюпорт — один документ с двух камер';

  @override
  String get splitViewportOff => 'Снова один вьюпорт';

  @override
  String get play => 'Играть';

  @override
  String get playTooltip => 'Играть — походить по документу в шаблоне';

  @override
  String playBlockedTooltip(String reason) {
    return 'Играть — $reason';
  }

  @override
  String get preview => 'Предпросмотр';

  @override
  String get previewTooltip => 'Предпросмотр — как это нарисует игра';

  @override
  String get settings => 'Настройки';

  @override
  String get settingsTooltip =>
      'Настройки — навигация, клавиши, рабочее пространство, язык';

  @override
  String agentSessionSemanticsLabel(int count) {
    return 'Сеанс агента, вызовов: $count';
  }

  @override
  String agentSessionTooltip(String client, int count) {
    return '$client · вызовов: $count';
  }

  @override
  String get exportCopyTooltip => 'Экспортировать копию';

  @override
  String get reportProblemTooltip => 'Сообщить о проблеме';

  @override
  String get startScreenLabel => 'Начальный экран';

  @override
  String get more => 'Ещё';

  @override
  String get foldPropertiesPanel => 'Свернуть панель свойств';

  @override
  String get foldToolRail => 'Свернуть панель инструментов';

  @override
  String get legalEntry =>
      'Юридическое: лицензия, приватность и сторонние лицензии';

  @override
  String get runACommand => 'Выполнить команду';

  @override
  String get gallery => 'Галерея';

  @override
  String get galleryTooltip =>
      'Галерея — вставить готовую модель рядом с открытым';

  @override
  String get toolSculptDrawLabel => 'Лепка';

  @override
  String get toolSculptDrawAbout =>
      'Выдавливает всё под кистью в одном общем направлении — как штамп.';

  @override
  String get toolSculptClayLabel => 'Глина';

  @override
  String get toolSculptClayAbout =>
      'Наращивает поверхность плоскими слоями — как глину пальцем.';

  @override
  String get toolSculptInflateLabel => 'Надув';

  @override
  String get toolSculptInflateAbout =>
      'Двигает каждую вершину по её собственной нормали: округлый участок раздувается, а не поднимается плоскостью.';

  @override
  String get toolSculptSmoothLabel => 'Сглаживание';

  @override
  String get toolSculptSmoothAbout =>
      'Выравнивает то, что под кистью, снимая неровности.';

  @override
  String get toolSculptFlattenLabel => 'Выравнивание';

  @override
  String get toolSculptFlattenAbout =>
      'Притягивает всё под кистью к одной плоскости.';

  @override
  String get toolSculptGrabLabel => 'Захват';

  @override
  String get toolSculptGrabAbout =>
      'Тянет вершины под кистью вслед за указателем.';

  @override
  String get toolSculptPinchLabel => 'Сжатие';

  @override
  String get toolSculptPinchAbout =>
      'Стягивает вершины под кистью к её центру.';

  @override
  String get toolSculptCreaseLabel => 'Складка';

  @override
  String get toolSculptCreaseAbout =>
      'Сжимает и вдавливает разом — так прорезается складка.';

  @override
  String get toolRetopoQuadLabel => 'Нарисовать квад';

  @override
  String get toolRetopoQuadAbout =>
      'Четыре клика по исходной модели: каждая точка либо прилипает к уже существующей вершине новой сетки, либо ложится на поверхность.';

  @override
  String get toolRetopoAutoLabel => 'Ретопология';

  @override
  String get toolRetopoAutoAbout =>
      'Перестраивает всю поверхность квадами примерно в том количестве, что задано на панели, и обтягивает ими оригинал.';

  @override
  String get toolRetopoBakeLabel => 'Запечь карты';

  @override
  String get toolRetopoBakeAbout =>
      'Запекает поверхность исходной модели в развёртку новой — карту нормалей, карту затенения или обе.';

  @override
  String get toolPaintBrushLabel => 'Кисть';

  @override
  String get toolPaintBrushAbout =>
      'Красит текстуру объекта через его развёртку: штрих поперёк шва ложится на оба острова.';

  @override
  String get toolPaintFillLabel => 'Залить слой';

  @override
  String get toolPaintFillAbout => 'Заливает весь слой цветом с палитры.';

  @override
  String get toolPaintClearLabel => 'Очистить слой';

  @override
  String get toolPaintClearAbout =>
      'Опустошает слой, не трогая те, что под ним.';

  @override
  String get toolSimSelectLabel => 'Выделение';

  @override
  String get toolSimSelectAbout =>
      'Выбрать вершины, на которых висит ткань, или объект для расчёта.';

  @override
  String get toolSimPinLabel => 'Закрепить выделение';

  @override
  String get toolSimPinAbout =>
      'Удерживает выбранные вершины на месте, пока всё остальное падает.';

  @override
  String get toolSimBakeLabel => 'Запечь';

  @override
  String get toolSimBakeAbout =>
      'Считает весь клип и сохраняет его, чтобы по нему можно было перематывать.';

  @override
  String get toolRenderSnapshotLabel => 'Рендер';

  @override
  String get toolRenderSnapshotAbout =>
      'Рендерит проект в размере, заданном на панели, по тайлу за раз и показывает результат.';

  @override
  String get toolRenderSaveLabel => 'Сохранить картинку';

  @override
  String get toolRenderSaveAbout => 'Записывает последний рендер в PNG.';

  @override
  String get settingsClearDataTitle => 'Очистить локальные данные?';

  @override
  String get settingsClear => 'Очистить';

  @override
  String get settingsCameraNavigation => 'Навигация камерой';

  @override
  String get settingsKeys => 'Клавиши';

  @override
  String get settingsTransformTools => 'Перемещение, поворот и масштаб';

  @override
  String get settingsWorkspace => 'Рабочее пространство';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsStepMove => 'Сдвиг';

  @override
  String get settingsStepTurn => 'Поворот°';

  @override
  String get settingsStepScale => 'Масштаб';

  @override
  String get settingsShowHome => 'Показывать «Домой» при запуске';

  @override
  String get settingsSaveHistory => 'Сохранять проекты вместе с историей';

  @override
  String get settingsLegal => 'Лицензия, приватность и остальное';

  @override
  String get settingsClearData => 'Очистить локальные данные';

  @override
  String get settingsClearDataBody =>
      'Удалятся настройки, список недавних файлов и автосохранение. Файлы проектов, сохранённые вами, не трогаются. Отменить нельзя.';

  @override
  String get settingsCameraNavigationHelp =>
      'Какие кнопки и жесты вращают, двигают и приближают.';

  @override
  String get settingsKeysHelp => 'Какой набор горячих клавиш действует.';

  @override
  String get settingsTransformToolsHelp =>
      'Открывает ли клавиша преобразование сразу или готовит его к перетаскиванию.';

  @override
  String get settingsWorkspaceHelp =>
      'Какие экраны предлагает переключатель режимов.';

  @override
  String get settingsLanguageHelp => 'На каком языке написан интерфейс.';

  @override
  String get settingsLanguageEnglish => 'Английский';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageSystem => 'Системный';

  @override
  String get settingsSnapSteps => 'Шаги привязки';

  @override
  String get settingsShowHomeHelp =>
      'Стартовый экран с недавними моделями и карточками сценариев.';

  @override
  String get settingsSaveHistoryHelp =>
      'Сохраняет внутри файла то, что ещё можно отменить.';

  @override
  String get settingsLegalSection => 'Юридическое и данные';

  @override
  String get settingsClearDataHelp =>
      'Настройки, список недавних файлов и автосохранение. Сохранённые файлы проектов не трогаются.';

  @override
  String get settingsLegalHelp =>
      'Документы, под которыми вышла эта сборка, и сторонние лицензии.';

  @override
  String commandPaletteNoMatch(String said) {
    return 'ничего не найдено по «$said»';
  }

  @override
  String get autorigTitle => 'Авториг';

  @override
  String get autorigCreate => 'Создать';

  @override
  String get autorigDragMarker => 'Перетащите маркер, чтобы уточнить сустав';

  @override
  String get autorigTemplate => 'Шаблон';

  @override
  String get autorigHumanoid => 'Человек';

  @override
  String get autorigQuadruped => 'Четвероногое';

  @override
  String get autorigCustom => 'Свой';

  @override
  String get autorigComposition => 'Состав';

  @override
  String get autorigFingers => 'Пальцы рук';

  @override
  String get autorigToes => 'Пальцы ног';

  @override
  String get autorigSpine => 'Позвоночник';

  @override
  String get autorigFaceBones => 'Кости лица';

  @override
  String get autorigIkChains => 'IK-цепи';

  @override
  String get autorigController => 'Контроллер рига';

  @override
  String get autorigBinding => 'Привязка';

  @override
  String get autorigPrimaryWeights => 'Назначить основные веса';

  @override
  String get autorigSymmetry => 'Симметрия';

  @override
  String get autorigBones => 'Костей';

  @override
  String get autorigDeforming => 'Деформирующих';

  @override
  String get autorigNone => 'Нет';

  @override
  String autorigMarkers(int placed, int total) {
    return 'Маркеров $placed из $total';
  }

  @override
  String get brushSize => 'Размер';

  @override
  String get brushStrength => 'Сила';

  @override
  String get sculptBrush => 'Кисть';

  @override
  String get sculptFalloffLinear => 'Линейное';

  @override
  String get sculptFalloffSmooth => 'Мягкое';

  @override
  String get sculptFalloffSharp => 'Резкое';

  @override
  String get sculptSymmetryX => 'Симметрия (X)';

  @override
  String get sculptSurface => 'Поверхность';

  @override
  String get sculptSubdivide => 'Подразделить';

  @override
  String get paintCanvas => 'Холст';

  @override
  String get paintNothingYet => 'Пока ничего не нарисовано';

  @override
  String get paintLayers => 'Слои';

  @override
  String get paintAddLayer => 'Добавить слой';

  @override
  String get paintColour => 'Цвет';

  @override
  String get paintMask => 'Маска';

  @override
  String get paintMaskNone => 'Нет';

  @override
  String get bakeRetopology => 'Ретопология';

  @override
  String get bakeTargetQuads => 'Сколько квадов';

  @override
  String get bakeRetopologize => 'Ретопологизировать';

  @override
  String get bakeMaps => 'Карты';

  @override
  String get bakeResolution => 'Разрешение';

  @override
  String get simKind => 'Вид';

  @override
  String get simParameters => 'Параметры';

  @override
  String get simCollidesWith => 'Сталкивается с';

  @override
  String get simNothingElse => 'В сцене больше ничего нет';

  @override
  String get simPinned => 'Закреплено';

  @override
  String get simClearPins => 'Снять закрепление';

  @override
  String get simClearCache => 'Очистить кеш';

  @override
  String get renderPasses => 'Проходы';

  @override
  String get renderStart => 'Рендер';

  @override
  String get renderNothingYet => 'Пока ничего не отрендерено';

  @override
  String sculptFaces(int count) {
    return '$count граней';
  }

  @override
  String renderCancelTiles(int done, int total) {
    return 'Отмена · $done/$total';
  }

  @override
  String get weightsBrush => 'Кисть';

  @override
  String get weightsPaint => 'Рисовать';

  @override
  String get weightsAssign => 'Назначить';

  @override
  String get weightsRadius => 'Радиус';

  @override
  String get weightsMirror => 'Зеркалить';

  @override
  String get weightsNormalize => 'Нормализовать';

  @override
  String get weightsSelectedVertex => 'Выбранная вершина';

  @override
  String get weightsNoVertex => 'Под кистью пока нет вершины';

  @override
  String get weightsNoInfluences => 'На эту вершину ничто не влияет';

  @override
  String get weightsBones => 'Кости';

  @override
  String get weightsNoBones => 'Костей нет';

  @override
  String get morphsNoShapeKeys => 'У этого объекта нет ключей формы';

  @override
  String get morphsAddDriver => 'Добавить драйвер';

  @override
  String get morphsKeyShape => 'Поставить ключ на форму';

  @override
  String get morphsRemoveDriver => 'Удалить драйвер';

  @override
  String get morphsFrom => 'От°';

  @override
  String get morphsTo => 'До°';

  @override
  String get retargetRootMotion => 'Движение корня';

  @override
  String get retargetCorrections => 'Поправки';

  @override
  String get retargetLockFeet => 'Зафиксировать стопы';

  @override
  String get retargetGroundY => 'Уровень земли Y';

  @override
  String get retargetFootTolerance => 'Допуск для стопы';

  @override
  String get retargetApply => 'Применить ретаргет';

  @override
  String get uvMethod => 'Метод';

  @override
  String get uvMargin => 'Отступ';

  @override
  String get uvIslands => 'Острова';

  @override
  String get uvNoIslands => 'Островов нет';

  @override
  String get transportKeys => 'Ключи';

  @override
  String get transportCurves => 'Кривые';

  @override
  String get transportLoop => 'Цикл';

  @override
  String uvIsland(int id) {
    return 'Остров $id';
  }

  @override
  String get propDisplay => 'Отображение';

  @override
  String get propMaterial => 'Материал';

  @override
  String get propNormals => 'Нормали';

  @override
  String get propWire => 'Сетка';

  @override
  String get propPerspective => 'Перспектива';

  @override
  String get propOrthographic => 'Ортографическая';

  @override
  String get propView => 'Вид';

  @override
  String get propObjects => 'Объекты';

  @override
  String get propTransform => 'Преобразование';

  @override
  String get propSource => 'Источник';

  @override
  String get propReimport => 'Переимпорт';

  @override
  String get propModifiers => 'Модификаторы';

  @override
  String get propMorphs => 'Морфы';

  @override
  String get propLastOperation => 'Последняя операция';

  @override
  String get propSelection => 'Выделение';

  @override
  String get propMesh => 'Меш';

  @override
  String get propHealth => 'Состояние';

  @override
  String get propBudget => 'Бюджет';

  @override
  String get importTitle => 'Импорт';

  @override
  String get importUnit => 'Единица';

  @override
  String get importUpAxis => 'Ось вверх';

  @override
  String get importWeld => 'Сварить совпадающие вершины';

  @override
  String get importWeldHelp =>
      'Строит настоящую топологию меша; оставьте выключенным, чтобы данные файла остались ровно такими, какими пришли.';

  @override
  String get importRecalculateNormals => 'Пересчитать нормали';

  @override
  String get importTriangulate => 'Триангулировать n-угольники';

  @override
  String get importLinkToSource => 'Связать с источником';

  @override
  String get importLinkToSourceHelp =>
      'Запомнить, откуда это пришло, чтобы «Переимпорт» прочитал файл снова и сохранил преобразование, материалы и модификаторы.';

  @override
  String get exportTitle => 'Экспорт';

  @override
  String get exportTriangles => 'Треугольников';

  @override
  String get exportBakeTransforms => 'Запечь преобразования узлов';

  @override
  String get exportBakeTransformsHelp =>
      'Переносит положение каждого объекта в его собственные вершины, чтобы файлу нечего было терять из иерархии.';

  @override
  String get exportApplyModifiers => 'Применить модификаторы';

  @override
  String get exportApplyModifiersHelp =>
      'Пишет ту форму, которую вы видите, со свёрнутыми зеркалами и массивами. Выключено — пишется базовый меш.';

  @override
  String get exportSelectionOnly => 'Только выделенное';

  @override
  String get exportSelectionOnlyHelp =>
      'Пишет то, что выделено, и всё, что под ним, оставляя остальной проект на месте.';

  @override
  String get exportCompressTextures => 'Сжать текстуры (KTX2)';

  @override
  String get exportCompressTexturesHelp =>
      'Меньшие изображения, которые GPU читает без распаковки. Их понимает только читатель .f3d.';

  @override
  String get exportReady => 'готово к экспорту';

  @override
  String get exportShow => 'Показать';

  @override
  String get shortcutEdgeLoop => 'Выделить кольцо рёбер вдоль';

  @override
  String get shortcutEdgeRing => 'Выделить кольцо рёбер поперёк';

  @override
  String get shortcutFinger => 'Палец';

  @override
  String get shortcutFingerHeld => 'Палец, удержанный на месте';

  @override
  String get shortcutPen => 'Перо';

  @override
  String get shortcutPenOtherEnd => 'Обратная сторона пера';

  @override
  String get shortcutOrbit => 'Вращать';

  @override
  String get shortcutPan => 'Сдвигать';

  @override
  String get shortcutZoom => 'Приближать';

  @override
  String get exportNothing => 'Нечего экспортировать';

  @override
  String exportOfBudget(int triangles, int budget, String profile) {
    return '$triangles из $budget ($profile)';
  }

  @override
  String get shortcutEdgeLoopKeys => 'Alt и клик, в режиме меша';

  @override
  String get shortcutEdgeRingKeys => 'Ctrl или ⌘, вместе с Alt и кликом';

  @override
  String get shortcutFingerKeys =>
      'Двигает камеру, каким бы инструментом ни целились';

  @override
  String get shortcutFingerHeldKeys => 'Открывает меню, не сдвинув камеру';

  @override
  String get shortcutPenKeys =>
      'Рисует по модели, сильнее нажим — сильнее штрих';

  @override
  String get shortcutPenOtherEndKeys => 'Тот же штрих, стирающий';

  @override
  String get shortcutPanKeys => 'Shift и то, чем вращают';

  @override
  String get shortcutZoomKeys => 'Колесо или Ctrl с двумя пальцами';

  @override
  String importWarnings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count предупреждений',
      few: '$count предупреждения',
      one: '1 предупреждение',
    );
    return '$_temp0';
  }

  @override
  String get shortcutOrbitMiddle =>
      'Средняя кнопка, Alt с левой кнопкой или два пальца на трекпаде';

  @override
  String get shortcutOrbitLeft =>
      'Левая кнопка по пустому месту, средняя кнопка или два пальца на трекпаде';

  @override
  String get actionSave => 'Сохранить';

  @override
  String get actionExport => 'Экспорт';

  @override
  String get actionUndo => 'Отменить';

  @override
  String get actionRedo => 'Повторить';

  @override
  String get actionThisScreen => 'Этот экран';

  @override
  String get actionCommandPalette => 'Палитра команд';

  @override
  String get actionFoldPanel => 'Свернуть панель свойств';

  @override
  String get actionFoldRail => 'Свернуть рельсу инструментов';

  @override
  String get actionGrowSelection => 'Расширить выделение';

  @override
  String get actionShrinkSelection => 'Сузить выделение';

  @override
  String get actionBrushNarrower => 'Кисть уже';

  @override
  String get actionBrushWider => 'Кисть шире';

  @override
  String get actionFrameSelection => 'Показать выделенное целиком';

  @override
  String get actionFrameAll => 'Показать всё целиком';

  @override
  String get actionViewFront => 'Вид спереди';

  @override
  String get actionViewSide => 'Вид сбоку';

  @override
  String get actionViewTop => 'Вид сверху';

  @override
  String get actionPlayPause => 'Пуск и пауза';

  @override
  String get actionSelectAll => 'Выделить всё';

  @override
  String get actionSelectNone => 'Снять выделение';

  @override
  String get actionInvertSelection => 'Инвертировать выделение';

  @override
  String get actionToggleObjectMesh => 'Объект и меш';

  @override
  String get actionDelete => 'Удалить';

  @override
  String get matNoMaterials => 'Материалов нет';

  @override
  String get matAdd => 'Добавить материал';

  @override
  String get matUnassign => 'Снять назначение';

  @override
  String get matOpenInEditor => 'Открыть в редакторе';

  @override
  String get matCutoff => 'Порог';

  @override
  String get matAdvanced => 'Дополнительно';

  @override
  String get matEmissiveStrength => 'Сила свечения';

  @override
  String get matNormalScale => 'Масштаб нормалей';

  @override
  String get matOcclusionStrength => 'Сила затенения';

  @override
  String get matDoubleSided => 'Двусторонний';

  @override
  String get sceneNoLights => 'Источников нет';

  @override
  String get sceneRemoveLight => 'Убрать этот источник';

  @override
  String get sceneAdd => 'Добавить';

  @override
  String get sceneSource => 'Источник';

  @override
  String get sceneIntensity => 'Яркость';

  @override
  String get sceneRange => 'Дальность';

  @override
  String get sceneCone => 'Конус';

  @override
  String get sceneCastsShadow => 'Отбрасывает тень';

  @override
  String get quickSetupTitle => 'Настроить редактор';

  @override
  String get quickSetupHelp =>
      'Пять ответов, один раз. Каждый из них потом есть в настройках.';

  @override
  String get quickSetupCamera => 'Камера';

  @override
  String get quickSetupHowMuch => 'Сколько всего';

  @override
  String get quickSetupStart => 'Начать';

  @override
  String get pivotHelp =>
      'Вокруг чего центрируется поворот или масштаб из полей выше';

  @override
  String get pivotMedian => 'Медиана';

  @override
  String get pivotIndividual => 'Каждый сам';

  @override
  String get pivotCursor => '3D-курсор';

  @override
  String get spaceHelp => 'В чьих осях задан поворот из полей выше';

  @override
  String get spaceGlobal => 'Глобальные';

  @override
  String get spaceLocal => 'Локальные';

  @override
  String get modifierMirror => 'Зеркало';

  @override
  String get modifierArray => 'Массив';

  @override
  String get modifierSmooth => 'Сглаживание';

  @override
  String get modifierSubdivision => 'Подразделение';

  @override
  String get modifierBoolean => 'Булева операция';

  @override
  String get modifierNone => 'Модификаторов нет';

  @override
  String get modifierAdd => 'Добавить модификатор';

  @override
  String get modifierAddShort => 'Добавить';

  @override
  String get modifierRemove => 'Убрать';

  @override
  String modifierTriangles(int before, int after) {
    return '$before → $after треугольников';
  }

  @override
  String get latheSegments => 'Сегментов';

  @override
  String get latheClosed => 'Замкнутый профиль';

  @override
  String get latheAdd => 'Добавить';

  @override
  String get latheTitle => 'Тело вращения';

  @override
  String get saveAsTitle => 'Сохранить как';

  @override
  String get saveWithoutHistory => 'Сохранить без истории';

  @override
  String get saveWithoutHistoryHelp =>
      'После повторного открытия этого файла отмена будет недоступна.';

  @override
  String get galleryTitle => 'Галерея';

  @override
  String get galleryClose => 'Закрыть';

  @override
  String get gallerySearch => 'Искать в галерее';

  @override
  String get galleryAll => 'Все';

  @override
  String get galleryNoCredit => 'Указание авторства не требуется';

  @override
  String get previewBudgets => 'Бюджеты';

  @override
  String get previewTitle => 'Превью';

  @override
  String get previewClose => 'Закрыть превью';

  @override
  String get previewWireframe => 'Показать сетку';

  @override
  String get previewNotBuilt => 'для этого экрана ещё не собрано';

  @override
  String get agentHide => 'Скрыть панель агента';

  @override
  String get agentSession => 'Сессия';

  @override
  String get agentRenders => 'Рендеров';

  @override
  String get agentToolCalls => 'Вызовов инструментов';

  @override
  String get agentHistoryAuthor => 'История · автор';

  @override
  String get agentUndoSteps => 'Отменить шаги агента';

  @override
  String get agentContactSheet => 'КОНТАКТНЫЙ ЛИСТ';

  @override
  String get agentInsteadOfNumbers => 'что агент получает вместо чисел';

  @override
  String get agentNoRenderYet =>
      'В этой сессии ещё не было вызова render/renderSheet';

  @override
  String get graphNextImage => 'Следующее изображение';

  @override
  String get graphAddNode => 'Добавить узел';

  @override
  String get graphTitle => 'Граф текстур';

  @override
  String get legalTitle => 'Юридическое';

  @override
  String get legalClose => 'Закрыть';

  @override
  String get legalDocument => 'Документ';

  @override
  String get legalEnglishOnly =>
      'Эти документы публикуются только на английском, каким бы ни был язык интерфейса: одна подлинная версия, чтобы не было вопроса, какая из них обязывает.';

  @override
  String get legalThirdParty => 'Сторонние лицензии';

  @override
  String get budgetTriangles => 'Треугольники';

  @override
  String get budgetJoints => 'Суставы';

  @override
  String get budgetTextureMemory => 'Память текстур';

  @override
  String get budgetInfluences => 'Влияния';

  @override
  String get consoleAll => 'Все';

  @override
  String get consoleYou => 'Вы';

  @override
  String get consoleAgent => 'Агент';

  @override
  String get consoleClose => 'Закрыть консоль';

  @override
  String previewLights(int lights, int shadowed, int cap) {
    return '$lights источников · $shadowed/$cap с тенью';
  }

  @override
  String agentSteps(int agent, int person) {
    return '$agent агента · $person ваших';
  }

  @override
  String exportAnywayMore(int count) {
    return 'и ещё $count';
  }

  @override
  String legalLoadFailed(String error) {
    return 'Документы не загрузились: $error';
  }

  @override
  String metricsFps(int fps) {
    return '$fps кадр/с';
  }

  @override
  String metricsDrawCalls(String count) {
    return '$count вызовов отрисовки';
  }

  @override
  String metricsTriangles(String count) {
    return '$count треугольников';
  }

  @override
  String metricsBones(String count) {
    return '$count костей';
  }

  @override
  String galleryUnreachable(String names) {
    return 'Не удалось достучаться: $names; всё остальное на месте';
  }

  @override
  String get graphNextImageTooltip => 'Следующее изображение';
}
