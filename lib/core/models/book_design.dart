import 'package:flutter/foundation.dart';

enum BookTheme { basic, medieval, minecraft, diary, pixelated }

enum CoverIcon { none, quill, star, flower, moon, book }

enum CoverDecoration { none, frame, ornate }

enum BookTexture { none, grain, ruled, pixels }

/// Per-book choices. Presets are values, never mutable shared state.
@immutable
class BookDesign {
  const BookDesign({
    this.theme = BookTheme.basic,
    this.subtitle = '',
    this.author = '',
    this.icon = CoverIcon.none,
    this.decoration = CoverDecoration.frame,
    this.texture = BookTexture.grain,
    this.bookmark = false,
  });

  final BookTheme theme;
  final String subtitle, author;
  final CoverIcon icon;
  final CoverDecoration decoration;
  final BookTexture texture;
  final bool bookmark;

  factory BookDesign.preset(BookTheme theme) => switch (theme) {
    BookTheme.basic => const BookDesign(),
    BookTheme.medieval => const BookDesign(
      theme: BookTheme.medieval,
      icon: CoverIcon.quill,
      decoration: CoverDecoration.ornate,
    ),
    BookTheme.minecraft => const BookDesign(
      theme: BookTheme.minecraft,
      icon: CoverIcon.quill,
      texture: BookTexture.pixels,
    ),
    BookTheme.diary => const BookDesign(
      theme: BookTheme.diary,
      icon: CoverIcon.flower,
      texture: BookTexture.ruled,
      bookmark: true,
    ),
    BookTheme.pixelated => const BookDesign(
      theme: BookTheme.pixelated,
      icon: CoverIcon.star,
      texture: BookTexture.pixels,
    ),
  };

  BookDesign copyWith({
    BookTheme? theme,
    String? subtitle,
    String? author,
    CoverIcon? icon,
    CoverDecoration? decoration,
    BookTexture? texture,
    bool? bookmark,
  }) => BookDesign(
    theme: theme ?? this.theme,
    subtitle: subtitle ?? this.subtitle,
    author: author ?? this.author,
    icon: icon ?? this.icon,
    decoration: decoration ?? this.decoration,
    texture: texture ?? this.texture,
    bookmark: bookmark ?? this.bookmark,
  );

  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'subtitle': subtitle,
    'author': author,
    'icon': icon.name,
    'decoration': decoration.name,
    'texture': texture.name,
    'bookmark': bookmark,
  };

  factory BookDesign.fromJson(Map raw) {
    T choice<T extends Enum>(List<T> values, Object? value, T fallback) =>
        values.where((e) => e.name == value).firstOrNull ?? fallback;
    final theme = choice(BookTheme.values, raw['theme'], BookTheme.basic);
    final defaults = BookDesign.preset(theme);
    return BookDesign(
      theme: theme,
      subtitle: raw['subtitle'] is String ? raw['subtitle'] as String : '',
      author: raw['author'] is String ? raw['author'] as String : '',
      icon: choice(CoverIcon.values, raw['icon'], defaults.icon),
      decoration: choice(
        CoverDecoration.values,
        raw['decoration'],
        defaults.decoration,
      ),
      texture: choice(BookTexture.values, raw['texture'], defaults.texture),
      bookmark: raw['bookmark'] is bool
          ? raw['bookmark'] as bool
          : defaults.bookmark,
    );
  }
}
