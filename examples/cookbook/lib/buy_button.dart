/// A GLB on a product page, with a buy button under it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: BuyButton()));

/// The product page: the robot on an orbit camera filling the space above, and
/// a buy button below it that answers with a snack bar. The scene is one widget
/// in an ordinary column, laid out like any other.
class BuyButton extends StatelessWidget {
  /// Takes nothing: the model, the camera and the button are fixed in [build].
  const BuyButton({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Expanded(
          child: Scene3D(
            children: <Widget>[
              const OrbitCamera3D(distance: 5.0, pitch: 0.2),
              const Light3D.sun(),
              Model3D(source: 'assets_src/models/RobotExpressive.glb'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('In your cart'))),
            icon: const Icon(Icons.shopping_cart),
            label: const Text('Buy for 19 €'),
          ),
        ),
      ],
    ),
  );
}
