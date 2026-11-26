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
    final minecraft = design.theme == BookTheme.minecraft;
    final ink =
        base.computeLuminance() > .5 ? Colors.black87 : const Color(0xFFFFEBC4);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: base),
          if (minecraft)
            const Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: .25,
                widthFactor: 1,
                child: ColoredBox(color: Color(0xFF68943E)),
              ),
            ),
          IgnorePointer(
            child: CustomPaint(
              painter: _TexturePainter(design.texture, minecraft: minecraft),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              width * .15,
              width * .12,
              width * .08,
              width * .1,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: design.decoration == CoverDecoration.none
                    ? null
                    : Border.all(
                        color: ink.withValues(alpha: .7),
                        width:
                            design.decoration == CoverDecoration.ornate ? 2 : 1,
                      ),
              ),
              child: Padding(
                padding: EdgeInsets.all(width * .055),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (design.decoration == CoverDecoration.ornate)
                      Icon(Icons.auto_awesome, color: ink, size: width * .1),
                    if (coverIcon(design.icon) case final icon?) ...[
                      if (design.icon == CoverIcon.quill)
                        SizedBox(
                          width: width * .18,
                          height: width * .18,
                          child: CustomPaint(painter: _QuillPainter(ink)),
                        )
                      else
                        Icon(icon, color: ink, size: width * .18),
                      SizedBox(height: width * .05),
                    ],
                    Flexible(
                      child: Text(
                        book.title,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: width * .1,
                          height: 1.12,
                          fontWeight: FontWeight.bold,
                          fontFamily:
                              design.theme == BookTheme.pixelated || minecraft
                                  ? 'monospace'
                                  : 'serif',
                        ),
                      ),
                    ),
                    if (design.subtitle.isNotEmpty) ...[
                      SizedBox(height: width * .05),
                      Text(
                        design.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: width * .065),
                      ),
                    ],
                    if (design.author.isNotEmpty) ...[
                      SizedBox(height: width * .06),
                      Text(
                        design.author,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: width * .065),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (design.bookmark)
            Positioned(
              top: 0,
              right: width * .12,
              child: Icon(
                Icons.bookmark,
                size: width * .2,
                color: const Color(0xFFC95B56),
              ),
            ),
        ],
      ),
    );
  }
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
    this.minecraft = false,
    this.paper = false,
    this.dark = false,
  });
  final BookTexture texture;
  final bool minecraft, paper, dark;
  @override
  void paint(Canvas canvas, Size size) {
    if (texture == BookTexture.none) return;
    final paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(
        alpha: paper ? .045 : .09,
      );
    if (texture == BookTexture.ruled) {
      for (double y = 30; y < size.height; y += 26) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else {
      final step = texture == BookTexture.pixels ? 14.0 : 9.0;
      for (double y = 0; y < size.height; y += step) {
        for (double x = 0; x < size.width; x += step) {
          final n = ((x ~/ step) * 17 + (y ~/ step) * 31) % 7;
          if (n > 2) continue;
          final w = texture == BookTexture.pixels ? step * .7 : 1.0;
          canvas.drawRect(
            Rect.fromLTWH(x, y, w, texture == BookTexture.pixels ? w : 2),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TexturePainter oldDelegate) =>
      texture != oldDelegate.texture ||
      minecraft != oldDelegate.minecraft ||
      paper != oldDelegate.paper ||
      dark != oldDelegate.dark;
}

class _QuillPainter extends CustomPainter {
  const _QuillPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .91)
      ..quadraticBezierTo(size.width * .17, size.height * .22, size.width * .9,
          size.height * .08)
      ..quadraticBezierTo(size.width * .85, size.height * .65, size.width * .14,
          size.height * .91)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
        Offset(size.width * .12, size.height * .94),
        Offset(size.width * .75, size.height * .24),
        Paint()
          ..color = Colors.black54
          ..strokeWidth = size.width * .045);
  }

  @override
  bool shouldRepaint(_QuillPainter oldDelegate) => color != oldDelegate.color;
}
