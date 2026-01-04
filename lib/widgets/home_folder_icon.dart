import 'package:flutter/material.dart';

class HomeFolderIcon extends StatelessWidget {
  const HomeFolderIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.folder_outlined, size: size, color: iconColor),
          Icon(Icons.home, size: size * 0.55, color: iconColor),
        ],
      ),
    );
  }
}
