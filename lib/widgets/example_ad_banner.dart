import 'package:flutter/material.dart';

class ExampleAdBanner extends StatelessWidget {
  const ExampleAdBanner({
    super.key,
    this.height,
    this.heightFactor = 0.18,
  });

  final double? height;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final targetHeight = height ?? screenHeight * heightFactor;
    final bannerHeight =
        targetHeight.clamp(120.0, 180.0).toDouble();
    return Container(
      height: bannerHeight,
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
