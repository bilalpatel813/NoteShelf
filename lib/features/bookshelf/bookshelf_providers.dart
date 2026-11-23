import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/contracts.dart';
import '../../core/models/book.dart';
import '../../data/in_memory_book_repository.dart';

// ---------------------------------------------------------------------------
// INTEGRATION PROVIDERS - later tasks override these in ProviderScope.
// ---------------------------------------------------------------------------

/// T2: override with the TXT/folder-backed repository.
final bookRepositoryProvider = Provider<BookRepository>((ref) {
  final repo = InMemoryBookRepository.withSamples();
  ref.onDispose(repo.dispose);
  return repo;
});

/// T2: override with the TXT page repository. Not used by the bookshelf.
final pageRepositoryProvider = Provider<PageRepository>(
  (ref) => throw UnimplementedError('T2 must override pageRepositoryProvider'),
);

/// T2 (New Book / Import Folder) and T3 (open reader): override with real flows.
final bookshelfActionsProvider =
    Provider<BookshelfActions>((ref) => DemoBookshelfActions(ref));

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

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

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
  }) =>
      ShelfState(
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
  void selectAll(Iterable<String> ids) => state = state.copyWith(selectedIds: {...ids});
  void clearSelection() => state = state.copyWith(selectedIds: const {});
}

final shelfControllerProvider =
    NotifierProvider<ShelfController, ShelfState>(ShelfController.new);

/// Books after search filter + sort.
final visibleBooksProvider = Provider<AsyncValue<List<Book>>>((ref) {
  final shelf = ref.watch(shelfControllerProvider);
  return ref.watch(booksStreamProvider).whenData((all) {
    final q = shelf.query.trim().toLowerCase();
    final list = all
        .where((b) =>
            q.isEmpty ||
            b.title.toLowerCase().contains(q) ||
            b.subject.toLowerCase().contains(q))
        .toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    int cmp(Book a, Book b) => switch (shelf.sort) {
          BookSort.recent =>
            (a.lastOpenedAt ?? epoch).compareTo(b.lastOpenedAt ?? epoch),
          BookSort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          BookSort.subject => a.subject.toLowerCase() == b.subject.toLowerCase()
              ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
              : a.subject.toLowerCase().compareTo(b.subject.toLowerCase()),
          BookSort.pages => a.pageCount.compareTo(b.pageCount),
        };
    list.sort((a, b) => shelf.ascending ? cmp(a, b) : cmp(b, a));
    return list;
  });
});

// ---------------------------------------------------------------------------
// Placeholder actions (demo only; replaced by T2 / T3)
// ---------------------------------------------------------------------------

class DemoBookshelfActions implements BookshelfActions {
  DemoBookshelfActions(this._ref);
  final Ref _ref;

  @override
  Future<void> newBook(BuildContext context) async {
    final req = await showDialog<NewBookRequest>(
      context: context,
      builder: (_) => const _NewBookDialog(),
    );
    if (req != null) await _ref.read(bookRepositoryProvider).createBook(req);
  }

  @override
  Future<void> importFolder(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Folder'),
        content: const Text(
          'Integration point for T2: pick a folder, then call '
          'BookRepository.importFolder(path).',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Future<void> openBook(BuildContext context, Book book) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Reader integration point (T3): would open "${book.title}" '
          'at page ${book.lastOpenedPage}.'),
    ));
    await _ref.read(bookRepositoryProvider).markOpened(book.id);
  }
}

class _NewBookDialog extends StatefulWidget {
  const _NewBookDialog();
  @override
  State<_NewBookDialog> createState() => _NewBookDialogState();
}

class _NewBookDialogState extends State<_NewBookDialog> {
  static const _colors = [0xFF7A2E2E, 0xFF1F3A5F, 0xFF2F4A2A, 0xFF5B2A63, 0xFF5A4630, 0xFF0F5D5A];
  final _title = TextEditingController();
  final _subject = TextEditingController();
  int _color = _colors.first;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    final s = _subject.text.trim();
    Navigator.pop(
      context,
      NewBookRequest(title: t, subject: s.isEmpty ? 'General' : s, coverColorValue: _color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Book'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, children: [
            for (final c in _colors)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(c),
                  child: _color == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create book')),
      ],
    );
  }
}
