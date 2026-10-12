/// A GLB on a product page, with a buy button under it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: BuyButton()));

class BuyButton extends StatelessWidget {
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
