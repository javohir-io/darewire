import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'y2k.dart';

/// The DAREWIRE wordmark: bold type, with "WIRE" in the theme colour. Flat, no gradient or glow.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final style = T.wide(size * 0.8).copyWith(letterSpacing: size * 0.02);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: EdgeInsets.only(right: size * 0.3), child: Sparkle(size: size * 1.05)),
      Text('DARE', style: style),
      Text('WIRE', style: style.copyWith(color: C.primaryHi)),
    ]);
  }
}
