// Where there are no isolates to put work on (the web): none.
import '../capillary.dart';
import '../fluid_medium.dart';
import '../free_surface.dart';

/// Never made here: the same face as where there are isolates, so the code
/// that asks for one reads the same.
abstract final class FluidBackground implements ModeSolver {
  /// How many requests have not come back yet.
  int get outstanding;

  /// Works out a meniscus elsewhere; never called here.
  void meniscus(
    FluidMedium medium,
    double radius,
    double g,
    void Function(TubeMeniscus meniscus) done,
  );
}

/// None here: what would be put off is worked out at once.
FluidBackground? get fluidBackground => null;
