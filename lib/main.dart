import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/theme/app_theme.dart";
import "data/storage/t2_actions.dart";
import "data/storage/txt_repositories.dart";
import "features/bookshelf/bookshelf_providers.dart";
import "features/bookshelf/bookshelf_screen.dart";
import "features/reader/reader_screen.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await TxtStorage.open(); // T2: TXT/folder-backed storage
  runApp(
    ProviderScope(
      overrides: [
        bookRepositoryProvider.overrideWithValue(storage.books),
        pageRepositoryProvider.overrideWithValue(storage.pages),
        // New Book + Import Folder from T2; openBook from T3 (reader).
        bookshelfActionsProvider.overrideWith(
          (ref) => T2Actions(ref, openBook: openReader(ref)),
        ),
      ],
      child: const BookNotesApp(),
    ),
  );
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
