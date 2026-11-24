/// T3 - reader value types. No Flutter widgets, no storage access.
library;

import 'package:flutter/material.dart';

import '../../data/storage/book_store.dart' show FontSettings;

enum ReaderMode { edit, view }

/// folded = one page, unfolded = two-page spread.
enum ReaderLayout { folded, unfolded }

/// Fonts offered in the picker. Only Roboto ships with Flutter's Material
/// fonts on Android; the others fall back to the platform font when not
/// installed. To bundle them, add the font files + a `fonts:` section to
/// pubspec.yaml using these exact family names.
const readerFontFamilies = <String>[
  'Georgia',
  'Arial',
  'Roboto',
  'Lora',
  'Merriweather',
];

const readerFontFallback = <String>['Georgia', 'Times New Roman', 'serif'];

/// Typography for one book. Purely presentational: never touches TXT content.
@immutable
class TypographySettings {
  const TypographySettings({
    this.family = 'Georgia',
    this.size = 18,
    this.weight = 400,
    this.lineHeight = 1.5,
    this.paragraphSpacing = 8,
    this.align = TextAlign.left,
    this.color,
  });

  final String family;
  final double size;
  final int weight;
  final double lineHeight;
  final double paragraphSpacing;
  final TextAlign align;

  /// Null = use the theme's text colour.
  final Color? color;

  static const minSize = 10.0, maxSize = 40.0;
  static const minLineHeight = 1.0, maxLineHeight = 2.5;
  static const maxParagraphSpacing = 32.0;

  TypographySettings copyWith({
    String? family,
    double? size,
    int? weight,
    double? lineHeight,
    double? paragraphSpacing,
    TextAlign? align,
    Color? color,
    bool clearColor = false,
  }) => TypographySettings(
    family: family ?? this.family,
    size: (size ?? this.size).clamp(minSize, maxSize).toDouble(),
    weight: weight ?? this.weight,
    lineHeight: (lineHeight ?? this.lineHeight)
        .clamp(minLineHeight, maxLineHeight)
        .toDouble(),
    paragraphSpacing: (paragraphSpacing ?? this.paragraphSpacing)
        .clamp(0, maxParagraphSpacing)
        .toDouble(),
    align: align ?? this.align,
    color: clearColor ? null : (color ?? this.color),
  );

  FontWeight get fontWeight =>
      FontWeight.values[((weight.clamp(100, 900)) ~/ 100) - 1];

  TextStyle toTextStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return base.copyWith(
      fontFamily: family,
      fontFamilyFallback: readerFontFallback,
      fontSize: size,
      fontWeight: fontWeight,
      height: lineHeight,
      color: color ?? base.color,
    );
  }

  FontSettings toStored() => FontSettings(
    family: family,
    size: size,
    lineHeight: lineHeight,
    weight: weight,
    paragraphSpacing: paragraphSpacing,
    align: align.name == 'start' || align.name == 'end' ? 'left' : align.name,
    // ignore: deprecated_member_use
    colorValue: color?.value,
  );

  factory TypographySettings.fromStored(FontSettings f) => TypographySettings(
    family: f.family ?? 'Georgia',
    size: f.size.clamp(minSize, maxSize).toDouble(),
    weight: f.weight.clamp(100, 900),
    lineHeight: f.lineHeight.clamp(minLineHeight, maxLineHeight).toDouble(),
    paragraphSpacing: f.paragraphSpacing
        .clamp(0, maxParagraphSpacing)
        .toDouble(),
    align: TextAlign.values.firstWhere(
      (a) => a.name == f.align,
      orElse: () => TextAlign.left,
    ),
    color: f.colorValue == null ? null : Color(f.colorValue!),
  );

  @override
  bool operator ==(Object o) =>
      o is TypographySettings &&
      o.family == family &&
      o.size == size &&
      o.weight == weight &&
      o.lineHeight == lineHeight &&
      o.paragraphSpacing == paragraphSpacing &&
      o.align == align &&
      o.color == color;

  @override
  int get hashCode => Object.hash(
    family,
    size,
    weight,
    lineHeight,
    paragraphSpacing,
    align,
    color,
  );
}

/// Which 1-based page numbers are visible at once. [right] is null for an
/// odd final page in unfolded layout (the right side is rendered blank).
@immutable
class Spread {
  const Spread(this.left, [this.right]);
  final int left;
  final int? right;

  List<int> get pages => [left, if (right != null) right!];

  @override
  bool operator ==(Object o) =>
      o is Spread && o.left == left && o.right == right;
  @override
  int get hashCode => Object.hash(left, right);
  @override
  String toString() => 'Spread($left, $right)';
}

/// Pure layout maths, unit-tested without any widgets.
///
/// Unfolded spreads are (1,2) (3,4) (5,6)... so left pages are always odd.
/// With an odd page count the last spread is (n, null).
class SpreadMath {
  const SpreadMath._();

  /// Page that anchors the visible spread for [current].
  static int anchorFor(int current, ReaderLayout layout) =>
      layout == ReaderLayout.folded
      ? current
      : (current.isOdd ? current : current - 1);

  static Spread spreadFor(int current, int pageCount, ReaderLayout layout) {
    if (layout == ReaderLayout.folded) return Spread(current);
    final l = anchorFor(current, layout);
    return Spread(l, l + 1 <= pageCount ? l + 1 : null);
  }

  static int step(ReaderLayout layout) => layout == ReaderLayout.folded ? 1 : 2;

  /// Anchor page after moving [delta] steps, clamped to the valid range.
  static int move(int current, int delta, int pageCount, ReaderLayout layout) {
    if (pageCount <= 0) return 1;
    final next = anchorFor(current, layout) + delta * step(layout);
    final last = anchorFor(pageCount, layout);
    return next.clamp(1, last).toInt();
  }

  static bool canGoBack(int current, ReaderLayout layout) =>
      anchorFor(current, layout) > 1;

  static bool canGoForward(int current, int pageCount, ReaderLayout layout) =>
      anchorFor(current, layout) < anchorFor(pageCount, layout);

  /// Text for the page indicator, e.g. "Page 3 of 9" or "Pages 3-4 of 9".
  static String label(Spread s, int pageCount) => s.right == null
      ? 'Page ${s.left} of $pageCount'
      : 'Pages ${s.left}\u2013${s.right} of $pageCount';
}
