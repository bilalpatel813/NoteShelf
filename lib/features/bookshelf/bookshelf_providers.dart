import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/contracts.dart';
import '../../core/models/book.dart';

// ---------------------------------------------------------------------------
// INTEGRATION PROVIDERS - later tasks override these in ProviderScope.
// ---------------------------------------------------------------------------

/// Must be overridden with the TXT/folder-backed repository (see main.dart).
/// There is deliberately no demo default: a missing override fails loudly
/// instead of silently showing sample data.
final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => throw UnimplementedError(
    'bookRepositoryProvider must be overridden (main.dart)',
  ),
);

/// T2: override with the TXT page repository. Not used by the bookshelf.
final pageRepositoryProvider = Provider<PageRepository>(
  (ref) => throw UnimplementedError('T2 must override pageRepositoryProvider'),
);

/// Must be overridden with T2Actions (New Book / Import Folder) + T3 openReader.
final bookshelfActionsProvider = Provider<BookshelfActions>(
  (ref) => throw UnimplementedError(
    'bookshelfActionsProvider must be overridden (main.dart)',
  ),
);

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

final booksStreamProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(bookRepositoryProvider).watchBooks(),
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void set(ThemeMode m) => state = m;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

enum BookSort {
  recent('Last opened'),
  title('Title'),
  subject('Subject'),
  pages('Page count');

  const BookSort(this.label);
  final String label;
}

@immutable
class ShelfState {
  const ShelfState({
    this.query = '',
    this.sort = BookSort.recent,
    this.ascending = false,
    this.selectedIds = const {},
  });

  final String query;
  final BookSort sort;
  final bool ascending;
  final Set<String> selectedIds;

  bool get selecting => selectedIds.isNotEmpty;

  ShelfState copyWith({
    String? query,
    BookSort? sort,
    bool? ascending,
    Set<String>? selectedIds,
  }) => ShelfState(
    query: query ?? this.query,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    selectedIds: selectedIds ?? this.selectedIds,
  );
}

class ShelfController extends Notifier<ShelfState> {
  @override
  ShelfState build() => const ShelfState();

  void setQuery(String q) => state = state.copyWith(query: q);

  void setSort(BookSort s) {
    if (s == state.sort) {
      state = state.copyWith(ascending: !state.ascending);
    } else {
      state = state.copyWith(
        sort: s,
        ascending: s == BookSort.title || s == BookSort.subject,
      );
    }
  }

  void toggleSelect(String id) {
    final next = {...state.selectedIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(selectedIds: next);
  }

  void selectOnly(String id) => state = state.copyWith(selectedIds: {id});
  void selectAll(Iterable<String> ids) =>
      state = state.copyWith(selectedIds: {...ids});
  void clearSelection() => state = state.copyWith(selectedIds: const {});
}

final shelfControllerProvider = NotifierProvider<ShelfController, ShelfState>(
  ShelfController.new,
);

/// Books after search filter + sort.
final visibleBooksProvider = Provider<AsyncValue<List<Book>>>((ref) {
  final shelf = ref.watch(shelfControllerProvider);
  return ref.watch(booksStreamProvider).whenData((all) {
    final q = shelf.query.trim().toLowerCase();
    final list = all
        .where(
          (b) =>
              q.isEmpty ||
              b.title.toLowerCase().contains(q) ||
              b.subject.toLowerCase().contains(q),
        )
        .toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    int cmp(Book a, Book b) => switch (shelf.sort) {
      BookSort.recent => (a.lastOpenedAt ?? epoch).compareTo(
        b.lastOpenedAt ?? epoch,
      ),
      BookSort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      BookSort.subject =>
        a.subject.toLowerCase() == b.subject.toLowerCase()
            ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
            : a.subject.toLowerCase().compareTo(b.subject.toLowerCase()),
      BookSort.pages => a.pageCount.compareTo(b.pageCount),
    };
    list.sort((a, b) => shelf.ascending ? cmp(a, b) : cmp(b, a));
    return list;
  });
});
