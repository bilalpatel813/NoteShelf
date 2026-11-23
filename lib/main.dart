import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/theme/app_theme.dart";
import "features/bookshelf/bookshelf_providers.dart";
import "features/bookshelf/bookshelf_screen.dart";

void main() {
  runApp(const ProviderScope(child: BookNotesApp()));
}

class BookNotesApp extends ConsumerWidget {
  const BookNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: "BookNotes",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const BookshelfScreen(),
    );
  }
}
