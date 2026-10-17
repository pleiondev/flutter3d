/// A car's fuel in a crash: how hard a blow its tank is built to stand
/// whole, and what a crash past that spills to burn.
library;

/// A car's fuel cell as a crash meets it: whole through a blow up to
/// [standsTo], the change in speed a crash test drives it through; broken
/// past that, and its fuel let go.
///
/// **A standard's number, not a game's.** A crash that ends a car's run in
/// fire is one harder than the test its tank was built to pass: a game
/// asks [breaksAt] with the speed a crash took out of the car, and lights
/// what the tank spilt with a burner fed that much fuel and no more
/// (`Fires.setBurner`'s `fuel`), which goes out when it is burnt rather
/// than when a timer says.
final class FuelCell {
  const FuelCell({required this.standsTo});

  /// A single-seat racing car's: its survival cell, the fuel cell inside
  /// it, stands the FIA's frontal impact test of a Formula One chassis, a
  /// solid barrier met at 15 m/s.
  static const FuelCell racing = FuelCell(standsTo: 15.0);

  /// A road car's: its fuel system holds through a frontal barrier crash
  /// at 48 km/h, 13.3 m/s, as FMVSS No. 301 tests it.
  static const FuelCell road = FuelCell(standsTo: 48.0 / 3.6);

  /// The change in speed, m/s, a crash may take out of the car with its
  /// fuel cell whole.
  final double standsTo;

  /// Whether a crash that took [deltaV] m/s out of the car breaks it.
  bool breaksAt(double deltaV) => deltaV > standsTo;
}
