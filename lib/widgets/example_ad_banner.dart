import 'package:flutter/material.dart';

class ExampleAdBanner extends StatelessWidget {
  const ExampleAdBanner({super.key, this.height = 72});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      alignment: Alignment.center,
      child: Text(
        'AdSense banner (example)',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}
