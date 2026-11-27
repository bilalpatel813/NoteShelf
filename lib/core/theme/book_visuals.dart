import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/book_design.dart';

IconData? coverIcon(CoverIcon icon) => switch (icon) {
      CoverIcon.none => null,
      CoverIcon.quill => Icons.edit,
      CoverIcon.star => Icons.star_outline,
      CoverIcon.flower => Icons.local_florist_outlined,
      CoverIcon.moon => Icons.nightlight_round,
      CoverIcon.book => Icons.menu_book,
    };

/// Generated closed cover. Image covers are handled by the caller.
class DesignedBookCover extends StatelessWidget {
  const DesignedBookCover({super.key, required this.book, required this.width});
  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final design = book.cover.design!;
    final base = Color(book.cover.colorValue);
    final ink = base.computeLuminance() > .35
        ? Colors.black87
        : const Color(0xFFFFEBC4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : width;
        final availableHeight =
            constraints.hasBoundedHeight ? constraints.maxHeight : width * 1.5;
        final unit = math.min(availableWidth, availableHeight / 1.5);
        if (unit <= 0) return const SizedBox.shrink();
        final pixel = design.theme == BookTheme.pixelated ||
            design.theme == BookTheme.minecraft;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: base),
              IgnorePointer(
                child: CustomPaint(
                  painter: _CoverArtworkPainter(
                    design.theme,
                    design.decoration,
                    ink,
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _TexturePainter(design.texture, scale: unit / 120),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  availableWidth * .20,
                  availableHeight * .22,
                  availableWidth * .12,
                  availableHeight * .16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (coverIcon(design.icon) case final icon?) ...[
                      if (design.icon == CoverIcon.quill)
                        SizedBox(
                          width: unit * .18,
                          height: unit * .18,
                          child: CustomPaint(painter: _QuillPainter(ink)),
                        )
                      else if (pixel && design.icon == CoverIcon.star)
                        SizedBox(
                          width: unit * .18,
                          height: unit * .18,
                          child: CustomPaint(painter: _PixelStarPainter(ink)),
                        )
                      else
                        Icon(icon, color: ink, size: unit * .18),
                      SizedBox(height: unit * .045),
                    ],
                    Flexible(
                      child: Text(
                        book.title,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: unit * .1,
                          height: 1.12,
                          fontWeight: FontWeight.bold,
                          fontFamily: pixel ? 'monospace' : 'serif',
                        ),
                      ),
                    ),
                    if (design.subtitle.isNotEmpty) ...[
                      SizedBox(height: unit * .045),
                      Text(
                        design.subtitle,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: unit * .065),
                      ),
                    ],
                    if (design.author.isNotEmpty) ...[
                      SizedBox(height: unit * .05),
                      Text(
                        design.author,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: unit * .065),
                      ),
                    ],
                  ],
                ),
              ),
              if (design.bookmark)
                Positioned(
                  top: 0,
                  right: availableWidth * .13,
                  width: unit * .12,
                  height: unit * .23,
                  child: CustomPaint(painter: _RibbonPainter()),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// All motifs are drawn here rather than using third-party artwork or assets.
class _CoverArtworkPainter extends CustomPainter {
  const _CoverArtworkPainter(this.theme, this.decoration, this.ink);
  final BookTheme theme;
  final CoverDecoration decoration;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 150);
    final shade = Paint()..color = Colors.black.withValues(alpha: .13);
    final highlight = Paint()..color = ink.withValues(alpha: .18);

    switch (theme) {
      case BookTheme.basic:
        canvas.drawRect(const Rect.fromLTWH(12, 0, 3, 150), shade);
        canvas.drawRect(const Rect.fromLTWH(15, 0, 1, 150), highlight);
        break;
      case BookTheme.medieval:
        canvas.drawRect(const Rect.fromLTWH(12, 0, 7, 150), shade);
        for (final y in [24.0, 75.0, 126.0]) {
          canvas.drawRect(Rect.fromLTWH(11, y, 9, 3), highlight);
          canvas.drawCircle(Offset(15.5, y + 1.5), 1, Paint()..color = ink);
        }
        break;
      case BookTheme.minecraft:
        final grass = Paint()..color = const Color(0xFF668B45);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 17), grass);
        for (var x = 0; x < 10; x++) {
          final depth = [4.0, 8.0, 3.0, 6.0, 4.0, 9.0, 3.0, 7.0, 4.0, 6.0][x];
          canvas.drawRect(Rect.fromLTWH(x * 10.0, 17, 10, depth), grass);
        }
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < 10; x++) {
            if ((x * 7 + y * 3) % 4 == 0) {
              canvas.drawRect(
                Rect.fromLTWH(x * 10.0, 119 + y * 10.0, 6, 6),
                shade,
              );
            }
          }
        }
        for (var y = 0; y < 15; y++) {
          canvas.drawRect(
            Rect.fromLTWH(11, y * 10.0, 7, 10),
            y.isEven ? shade : highlight,
          );
        }
        break;
      case BookTheme.diary:
        canvas.drawRect(const Rect.fromLTWH(12, 0, 6, 150), highlight);
        for (var y = 15.0; y < 145; y += 13) {
          canvas.drawCircle(Offset(15, y), 1.3, shade);
          canvas.drawLine(
            Offset(12, y),
            Offset(17, y),
            Paint()
              ..color = ink.withValues(alpha: .55)
              ..strokeWidth = .7,
          );
        }
        final heart = Paint()..color = ink.withValues(alpha: .55);
        for (final x in [29.0, 83.0]) {
          final path = Path()
            ..moveTo(x, 19)
            ..cubicTo(x - 6, 14, x - 7, 20, x, 25)
            ..cubicTo(x + 7, 20, x + 6, 14, x, 19)
            ..close();
          canvas.drawPath(path, heart);
        }
        // A small clasp sits outside the writing and title area.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(92, 67, 7, 16),
            const Radius.circular(2),
          ),
          Paint()..color = ink.withValues(alpha: .65),
        );
        break;
      case BookTheme.pixelated:
        for (var i = 0; i < 8; i++) {
          canvas.drawRect(
            Rect.fromLTWH(20 + i * 10.0, 0, 10, i.isEven ? 8 : 14),
            shade,
          );
          canvas.drawRect(
            Rect.fromLTWH(
              20 + i * 10.0,
              i.isEven ? 141 : 135,
              10,
              i.isEven ? 9 : 15,
            ),
            highlight,
          );
        }
        final gold = Paint()..color = const Color(0xFFE9C85E);
        for (final x in [19.0, 84.0]) {
          for (final y in [10.0, 129.0]) {
            canvas.drawRect(Rect.fromLTWH(x, y, 9, 4), gold);
            canvas.drawRect(Rect.fromLTWH(x, y, 4, 11), gold);
          }
        }
        for (var y = 8.0; y < 145; y += 16) {
          canvas.drawRect(Rect.fromLTWH(11, y, 7, 8), gold);
        }
        break;
    }

    if (decoration != CoverDecoration.none) {
      final border = Paint()
        ..color = ink.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = decoration == CoverDecoration.ornate ? 1.2 : .7;
      final rect = const Rect.fromLTRB(19, 12, 93, 138);
      canvas.drawRect(rect, border);
      if (decoration == CoverDecoration.ornate) {
        canvas.drawRect(rect.deflate(3), border..strokeWidth = .45);
        final ornament = Paint()..color = ink.withValues(alpha: .8);
        for (final x in [22.0, 90.0]) {
          for (final y in [15.0, 135.0]) {
            final diamond = Path()
              ..moveTo(x, y - 2)
              ..lineTo(x + 2, y)
              ..lineTo(x, y + 2)
              ..lineTo(x - 2, y)
              ..close();
            canvas.drawPath(diamond, ornament);
          }
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverArtworkPainter oldDelegate) =>
      theme != oldDelegate.theme ||
      decoration != oldDelegate.decoration ||
      ink != oldDelegate.ink;
}

class _PixelStarPainter extends CustomPainter {
  const _PixelStarPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const rows = ['00100', '01110', '11111', '01110', '01010'];
    final paint = Paint()..color = color;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y][x] == '1') {
          canvas.drawRect(
            Rect.fromLTWH(
              x * size.width / 5,
              y * size.height / 5,
              size.width / 5,
              size.height / 5,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelStarPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ribbon = Path()
      ..lineTo(0, size.height)
      ..lineTo(size.width / 2, size.height * .75)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = const Color(0xFFC95B56));
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => false;
}

/// Presentation only: never intercepts editing or page-turn gestures.
class BookPageSurface extends StatelessWidget {
  const BookPageSurface({
    super.key,
    required this.design,
    required this.child,
    this.blank = false,
  });
  final BookDesign? design;
  final Widget child;
  final bool blank;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark
        ? const Color(0xFF2B2622)
        : switch (design?.theme) {
            BookTheme.medieval => const Color(0xFFF4E8CE),
            BookTheme.diary => const Color(0xFFFFF4F2),
            BookTheme.minecraft ||
            BookTheme.pixelated =>
              const Color(0xFFF6EFDD),
            _ => const Color(0xFFFBF4E4),
          };
    return ColoredBox(
      color: blank ? color.withValues(alpha: .6) : color,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (design != null && design!.texture != BookTexture.none)
            IgnorePointer(
              child: CustomPaint(
                painter: _TexturePainter(
                  design!.texture,
                  paper: true,
                  dark: dark,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _TexturePainter extends CustomPainter {
  const _TexturePainter(
    this.texture, {
    this.paper = false,
    this.dark = false,
    this.scale = 1,
  });
  final BookTexture texture;
  final bool paper, dark;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    if (texture == BookTexture.none) return;
    final paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(
        alpha: paper ? .045 : .09,
      );
    final spacingScale =
        paper ? 1.0 : math.max(scale, math.max(size.width, size.height) / 2400);
    if (texture == BookTexture.ruled) {
      for (double y = 30 * spacingScale;
          y < size.height;
          y += 26 * spacingScale) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else {
      final step = (texture == BookTexture.pixels ? 14.0 : 9.0) * spacingScale;
      for (double y = 0; y < size.height; y += step) {
        for (double x = 0; x < size.width; x += step) {
          final n = ((x ~/ step) * 17 + (y ~/ step) * 31) % 7;
          if (n > 2) continue;
          final w = texture == BookTexture.pixels ? step * .7 : spacingScale;
          canvas.drawRect(
            Rect.fromLTWH(
              x,
              y,
              w,
              texture == BookTexture.pixels ? w : 2 * spacingScale,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TexturePainter oldDelegate) =>
      texture != oldDelegate.texture ||
      paper != oldDelegate.paper ||
      dark != oldDelegate.dark ||
      scale != oldDelegate.scale;
}

class _QuillPainter extends CustomPainter {
  const _QuillPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .91)
      ..quadraticBezierTo(
        size.width * .17,
        size.height * .22,
        size.width * .9,
        size.height * .08,
      )
      ..quadraticBezierTo(
        size.width * .85,
        size.height * .65,
        size.width * .14,
        size.height * .91,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(size.width * .12, size.height * .94),
      Offset(size.width * .75, size.height * .24),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = size.width * .045,
    );
  }

  @override
  bool shouldRepaint(_QuillPainter oldDelegate) => color != oldDelegate.color;
}
