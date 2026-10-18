import 'package:flutter3d_kinds/flutter3d_kinds.dart';

base class Spinner extends Component {
  @override
  void update(double dt) {}
}

abstract base class Mover extends Component {}

base class Walker extends Mover {}

base class Twin<T> extends Component {
  @override
  void update(double dt) {}
}

base class Listed extends Component with Marker implements Comparable<Listed> {
  @override
  int compareTo(Listed other) => 0;

  @override
  void update(double dt) {}
}

// TODO(flutter3d-1.0): `Component` is a `base` class in 1.0.0-rc.1: a class below it is `base`, `final` or `sealed` itself, and extends it rather than implementing it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Component-base
class Taken extends Walker implements Component {}

base class AlreadyBase extends Component {}

final class AlreadyFinal extends Component {}

// TODO(flutter3d-1.0): `Component` is a `base` class in 1.0.0-rc.1: a class below it is `base`, `final` or `sealed` itself, and extends it rather than implementing it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Component-base
interface class Shape extends Component {}

mixin Marker {}

base mixin Ticking on Component {}

// TODO(flutter3d-1.0): `Badge` is a `final` class: hold one in a field of your own class instead of extending it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Badge-final
class Shield extends Badge {
  Shield() : super('shield');
}

// TODO(flutter3d-1.0): `Badge` is a `final` class: hold one in a field of your own class instead of extending it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Badge-final
class Medal implements Badge {
  @override
  String get text => 'medal';
}
