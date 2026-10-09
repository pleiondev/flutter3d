/// `MODELS_EDITOR`: whether a model may be saved back from `/app/`.
///
/// **410, not 404.** With editing off, `POST /api/v1/models/<id>/source` is a
/// route that existed and was retired on purpose, and the viewer build that
/// could have called it is the view-only one. A 404 would read as a model
/// that is missing, which is the answer this service keeps for "not yours";
/// a 410 with its reason says what happened instead. It is answered before
/// the model is looked up, so it is the same for every id and says nothing
/// about which models exist.
library;

import 'package:shelf/shelf.dart';

import '../config.dart';
import 'request.dart';

/// The answer to a save-back while editing is off, or null when it is on.
Response? sourceSaveRefusal(Config config) => config.editor
    ? null
    : json(410, {
        'error':
            'Editing models on this site is switched off; they open to be '
            'viewed. Download the file to edit it in the modeller on your '
            'own machine, and upload it again.',
      });
