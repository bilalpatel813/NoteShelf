# BookNotes - T1 (foundation + bookshelf)

## Setup (generates the Windows/Android platform folders)
```
flutter create --platforms=windows,android --project-name booknotes --org com.booknotes .
# then keep this repo's lib/, test/, pubspec.yaml (overwrite if flutter create replaced them)
flutter pub get
flutter run -d windows      # or: flutter run -d <android-device-id>
flutter test
```
Requires Flutter 3.27+ (uses `Color.withValues`) and Dart 3.3+.

## Layout
```
lib/main.dart
lib/core/models/book.dart              Book, BookPage, BookCoverRef, ReadingMode
lib/core/contracts/contracts.dart      BookRepository, PageRepository, BookshelfActions, NewBookRequest
lib/core/theme/app_theme.dart          light/dark ThemeData + ShelfPalette
lib/data/in_memory_book_repository.dart  sample data (T2 replaces)
lib/features/bookshelf/bookshelf_providers.dart  providers, state, demo actions
lib/features/bookshelf/bookshelf_screen.dart     responsive shelf, search/sort, selection, menus
lib/features/bookshelf/book_card.dart            cover + card + hover + gestures
test/bookshelf_test.dart
```

## Integration points (override in `ProviderScope(overrides: [...])`)
| Provider | Owner | Replace with |
|---|---|---|
| `bookRepositoryProvider` | T2 | TXT/folder-backed `BookRepository` |
| `pageRepositoryProvider` | T2 | TXT-backed `PageRepository` |
| `bookshelfActionsProvider` | T2 (newBook, importFolder), T3 (openBook) | real flows |

## Manual test checklist
- Windows: hover shows Open / more buttons; click selects (Ctrl/Shift multi-select); double-click opens; right-click menu; Esc clears selection.
- Android: tap opens; long-press shows menu -> Select; then tap toggles; app bar shows selection actions.
- Resize the window from 360 px to 1400 px: columns reflow; narrow layout shows FAB + overflow menu.
- Search "kerala", sort by each option (re-tap to flip direction), toggle light/dark.
