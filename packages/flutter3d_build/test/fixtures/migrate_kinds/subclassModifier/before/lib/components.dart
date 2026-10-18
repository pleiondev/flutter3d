import 'package:flutter3d_kinds/flutter3d_kinds.dart';

class Spinner extends Component {
  @override
  void update(double dt) {}
}

abstract class Mover extends Component {}

class Walker extends Mover {}

class Twin<T> implements Component {
  @override
  void update(double dt) {}
}

class Listed with Marker implements Comparable<Listed>, Component {
  @override
  int compareTo(Listed other) => 0;

  @override
  void update(double dt) {}
}

class Taken extends Walker implements Component {}

base class AlreadyBase extends Component {}

final class AlreadyFinal extends Component {}

interface class Shape extends Component {}

mixin Marker {}

mixin Ticking on Component {}

class Shield extends Badge {
  Shield() : super('shield');
}

class Medal implements Badge {
  @override
  String get text => 'medal';
}
