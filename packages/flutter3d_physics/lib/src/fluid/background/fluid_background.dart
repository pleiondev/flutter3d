// Another isolate where there are isolates, none where there are not.
export 'fluid_background_none.dart'
    if (dart.library.isolate) 'fluid_background_io.dart';
