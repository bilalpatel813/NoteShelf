import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/book.dart';
import '../../core/theme/app_theme.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatLastOpened(DateTime? d, [DateTime? now]) {
  if (d == null) return 'Never opened';
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return 'Opened today';
  if (days == 1) return 'Opened yesterday';
  if (days < 14) return 'Opened $days days ago';
  return 'Opened ${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// A book standing on the shelf: cover, hover actions, selection badge and a
/// label (title, subject, pages, last opened) printed on the shelf front.
///
/// Gesture rules (decided by the parent via callbacks):
///  * Windows: click selects, double-click opens, right-click menu, hover buttons.
///  * Android: tap opens (or toggles while selecting), long-press menu.
class BookCard extends StatefulWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.width,
    required this.selected,
    required this.desktop,
    required this.onTap,
    required this.onOpen,
    required this.onContextMenu,
    this.onDoubleTap,
  });

  static const labelHeight = 68.0;

  final Book book;
  final double width;
  final bool selected;
  final bool desktop;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback onOpen;
  final void Function(Offset globalPosition) onContextMenu;

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = ShelfPalette.of(context);
    final book = widget.book;
    final showHover = widget.desktop && _hover;
    final labelStyle = TextStyle(color: palette.plaqueText, fontSize: 11.5, height: 1.25);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.desktop ? widget.onDoubleTap : null,
        onLongPressStart: widget.desktop ? null : (d) => widget.onContextMenu(d.globalPosition),
        onSecondaryTapUp: (d) => widget.onContextMenu(d.globalPosition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: widget.width,
              height: widget.width * 1.5,
              child: AnimatedScale(
                scale: showHover ? 1.04 : 1,
                alignment: Alignment.bottomCenter,
                duration: const Duration(milliseconds: 140),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    BookCoverView(book: book, width: widget.width),
                    if (widget.selected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: palette.accent, width: 3),
                            ),
                          ),
                        ),
                      ),
                    if (widget.selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: palette.accent,
                          child: const Icon(Icons.check, size: 16, color: Colors.black87),
                        ),
                      ),
                    if (showHover)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                tooltip: 'Open',
                                color: Colors.white,
                                icon: const Icon(Icons.menu_book),
                                onPressed: widget.onOpen,
                              ),
                              Builder(
                                builder: (ctx) => IconButton(
                                  tooltip: 'More options',
                                  color: Colors.white,
                                  icon: const Icon(Icons.more_vert),
                                  onPressed: () {
                                    final box = ctx.findRenderObject() as RenderBox;
                                    widget.onContextMenu(box.localToGlobal(box.size.center(Offset.zero)));
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: widget.width,
              height: BookCard.labelHeight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, left: 2, right: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(book.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
                    Text('${book.pageCount} ${book.pageCount == 1 ? 'page' : 'pages'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
                    Text(formatLastOpened(book.lastOpenedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle.copyWith(color: palette.plaqueText.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leather-style cover: generated from colour + title, or an image file.
class BookCoverView extends StatelessWidget {
  const BookCoverView({super.key, required this.book, required this.width});
  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final base = Color(book.cover.colorValue);
    final hsl = HSLColor.fromColor(base);
    final dark = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
    final light = hsl.withLightness((hsl.lightness + 0.07).clamp(0.0, 1.0)).toColor();
    const gold = Color(0xFFE8CF94);

    Widget generated() => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [dark, light, base]),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(width * 0.16, width * 0.12, width * 0.08, width * 0.1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.2),
              ),
              child: Padding(
                padding: EdgeInsets.all(width * 0.06),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.title,
                      textAlign: TextAlign.center,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamilyFallback: AppTheme.serifFallback,
                        fontWeight: FontWeight.w700,
                        fontSize: width * 0.105,
                        height: 1.2,
                        color: gold,
                        shadows: const [Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 1)],
                      ),
                    ),
                    SizedBox(height: width * 0.06),
                    Container(width: width * 0.3, height: 1.2, color: gold.withValues(alpha: 0.6)),
                    SizedBox(height: width * 0.05),
                    Text(
                      book.subject,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamilyFallback: AppTheme.serifFallback,
                        fontStyle: FontStyle.italic,
                        fontSize: width * 0.065,
                        color: gold.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    final imagePath = book.cover.imagePath;
    final face = imagePath == null
        ? generated()
        : Image.file(File(imagePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => generated());

    const radius = BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(6));
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(3, 4))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(fit: StackFit.expand, children: [
          face,
          // Spine crease + highlight on the left edge.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width * 0.11,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.25),
                  ],
                  stops: const [0, 0.65, 1],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
