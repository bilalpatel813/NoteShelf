import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/book_design.dart';
import '../../core/theme/book_visuals.dart';

/// Adds reader-only details without changing the shared paper or its texture.
class ReaderPageSurface extends StatelessWidget {
  const ReaderPageSurface({
    super.key,
    required this.design,
    required this.child,
    this.leftSide = false,
    this.blank = false,
  });

  final BookDesign? design;
  final Widget child;
  final bool leftSide;
  final bool blank;

  @override
  Widget build(BuildContext context) => BookPageSurface(
        design: design,
        blank: blank,
        child: design == null
            ? child
            : Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _PageDecorationPainter(
                        theme: design!.theme,
                        leftSide: leftSide,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                  ),
                  child,
                ],
              ),
      );
}

class _PageDecorationPainter extends CustomPainter {
  const _PageDecorationPainter({
    required this.theme,
    required this.leftSide,
    required this.dark,
  });

  final BookTheme theme;
  final bool leftSide;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 40 || size.height < 40) return;

    final width = math.min(18.0, size.width * .08);
    final binding = Rect.fromLTWH(
      leftSide ? size.width - width : 0,
      0,
      width,
      size.height,
    );
    canvas.drawRect(
      binding,
      Paint()
        ..shader = LinearGradient(
          begin: leftSide ? Alignment.centerRight : Alignment.centerLeft,
          end: leftSide ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            Colors.black.withValues(alpha: dark ? .22 : .12),
            Colors.transparent,
          ],
        ).createShader(binding),
    );

    final accent = switch (theme) {
      BookTheme.basic =>
        dark ? const Color(0xFFB9A38B) : const Color(0xFF9B8061),
      BookTheme.medieval =>
        dark ? const Color(0xFFD6B77A) : const Color(0xFF96733E),
      BookTheme.minecraft =>
        dark ? const Color(0xFF9DBB75) : const Color(0xFF648044),
      BookTheme.diary =>
        dark ? const Color(0xFFD7A3A1) : const Color(0xFFCC8F8B),
      BookTheme.pixelated =>
        dark ? const Color(0xFFB6A7D6) : const Color(0xFF807197),
    };
    final paint = Paint()
      ..color = accent.withValues(alpha: dark ? .42 : .38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    switch (theme) {
      case BookTheme.basic:
        break;
      case BookTheme.medieval:
        canvas.drawRect(
          Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(11, 11, size.width - 22, size.height - 22),
          paint,
        );
      case BookTheme.diary:
        final x = leftSide ? size.width - 16 : 16.0;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      case BookTheme.minecraft:
      case BookTheme.pixelated:
        paint.style = PaintingStyle.fill;
        const block = 4.0;
        for (var i = 0; i < 3; i++) {
          final offset = 7.0 + i * 7;
          canvas.drawRect(Rect.fromLTWH(offset, 7, block, block), paint);
          canvas.drawRect(
            Rect.fromLTWH(size.width - offset - block, 7, block, block),
            paint,
          );
          canvas.drawRect(
            Rect.fromLTWH(offset, size.height - 11, block, block),
            paint,
          );
          canvas.drawRect(
            Rect.fromLTWH(
              size.width - offset - block,
              size.height - 11,
              block,
              block,
            ),
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_PageDecorationPainter oldDelegate) =>
      theme != oldDelegate.theme ||
      leftSide != oldDelegate.leftSide ||
      dark != oldDelegate.dark;
}
