import 'dart:developer' as developer;

import 'package:flutter3d_core/formats.dart';

/// [request] decoded in place: the browser has no isolates, and
/// `decodeModelInIsolate` does not ask for one there.
Future<ModelDocument> decodeOnIsolate(
  ModelLoadRequest request,
  developer.TimelineTask task,
) => decodeModel(request);
