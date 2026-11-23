import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/contracts.dart';
import '../../core/models/book.dart';
import '../../core/theme/app_theme.dart';
import 'book_card.dart';
import 'bookshelf_providers.dart';

enum _BookAction { open, select, info, delete }

class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen> {
  static const double _wideBreakpoint = 720;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _desktop => switch (Theme.of(context).platform) {
        TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macos => true,
        _ => false,
      };

  // ----------------------------------------------------------------- actions

  void _openBook(Book book) => ref.read(bookshelfActionsProvider).openBook(context, book);

  void _onCardTap(Book book) {
    final ctrl = ref.read(shelfControllerProvider.notifier);
    final selecting = ref.read(shelfControllerProvider).selecting;
    if (_desktop) {
      final kb = HardwareKeyboard.instance;
      final multi = kb.isControlPressed || kb.isMetaPressed || kb.isShiftPressed;
      multi ? ctrl.toggleSelect(book.id) : ctrl.selectOnly(book.id);
    } else if (selecting) {
      ctrl.toggleSelect(book.id);
    } else {
      _openBook(book);
    }
  }

  Future<void> _showContextMenu(Book book, Offset position) async {
    final selected = ref.read(shelfControllerProvider).selectedIds.contains(book.id);
    final entries = <(_BookAction, IconData, String)>[
      (_BookAction.open, Icons.menu_book_outlined, 'Open'),
      (
        _BookAction.select,
        selected ? Icons.check_box_outline_blank : Icons.check_box_outlined,
        selected ? 'Deselect' : 'Select'
      ),
      (_BookAction.info, Icons.info_outline, 'Book info'),
      (_BookAction.delete, Icons.delete_outline, 'Delete'),
    ];

    _BookAction? choice;
    if (_desktop) {
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      choice = await showMenu<_BookAction>(
        context: context,
        position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
        items: [
          for (final e in entries)
            PopupMenuItem(
              value: e.$1,
              child: Row(children: [Icon(e.$2, size: 20), const SizedBox(width: 12), Text(e.$3)]),
            ),
        ],
      );
    } else {
      choice = await showModalBottomSheet<_BookAction>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(book.subject),
            ),
            for (final e in entries)
              ListTile(
                leading: Icon(e.$2),
                title: Text(e.$3),
                onTap: () => Navigator.pop(ctx, e.$1),
              ),
          ]),
        ),
      );
    }
    if (choice == null || !mounted) return;
    final ctrl = ref.read(shelfControllerProvider.notifier);
    switch (choice) {
      case _BookAction.open:
        _openBook(book);
      case _BookAction.select:
        ctrl.toggleSelect(book.id);
      case _BookAction.info:
        _showInfo(book);
      case _BookAction.delete:
        await _confirmDelete([book]);
    }
  }

  void _showInfo(Book book) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ]),
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(book.title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          row('Subject', book.subject),
          row('Pages', '${book.pageCount}'),
          row('Last page', '${book.lastOpenedPage}'),
          row('Last opened', formatLastOpened(book.lastOpenedAt)),
          row('Reading mode', book.preferredReadingMode.name),
          row('Folder', book.folderRef),
          row('ID', book.id),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _confirmDelete(List<Book> books) async {
    final label = books.length == 1 ? '"${books.first.title}"' : '${books.length} books';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $label?'),
        content: const Text('This removes the book from your shelf.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // T2 decides what "delete" means for files on disk.
    final repo = ref.read(bookRepositoryProvider);
    for (final b in books) {
      await repo.deleteBook(b.id);
    }
    ref.read(shelfControllerProvider.notifier).clearSelection();
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final shelf = ref.watch(shelfControllerProvider);
    final ctrl = ref.read(shelfControllerProvider.notifier);
    final books = ref.watch(visibleBooksProvider);
    final actions = ref.read(bookshelfActionsProvider);
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final palette = ShelfPalette.of(context);
    final visible = books.valueOrNull ?? const <Book>[];

    final PreferredSizeWidget appBar;
    if (shelf.selecting) {
      final selectedBooks = visible.where((b) => shelf.selectedIds.contains(b.id)).toList();
      appBar = AppBar(
        leading: IconButton(
          tooltip: 'Clear selection',
          icon: const Icon(Icons.close),
          onPressed: ctrl.clearSelection,
        ),
        title: Text('${shelf.selectedIds.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Select all',
            icon: const Icon(Icons.select_all),
            onPressed: () => ctrl.selectAll(visible.map((b) => b.id)),
          ),
          if (selectedBooks.length == 1)
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.menu_book),
              onPressed: () => _openBook(selectedBooks.first),
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: selectedBooks.isEmpty ? null : () => _confirmDelete(selectedBooks),
          ),
        ],
      );
    } else {
      final mode = ref.watch(themeModeProvider);
      final isDark = mode == ThemeMode.dark ||
          (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
      appBar = AppBar(
        title: const Row(children: [
          Icon(Icons.auto_stories),
          SizedBox(width: 10),
          Text('BookNotes'),
        ]),
        actions: [
          if (wide) ...[
            FilledButton.icon(
              onPressed: () => actions.newBook(context),
              icon: const Icon(Icons.add),
              label: const Text('New Book'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: palette.plaqueText),
              onPressed: () => actions.importFolder(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('Import Folder'),
            ),
          ] else
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => actions.importFolder(context),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'import', child: Text('Import Folder')),
              ],
            ),
          IconButton(
            tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .set(isDark ? ThemeMode.light : ThemeMode.dark),
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): ctrl.clearSelection},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: appBar,
          floatingActionButton: (!wide && !shelf.selecting)
              ? FloatingActionButton.extended(
                  onPressed: () => actions.newBook(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New Book'),
                )
              : null,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [palette.wallTop, palette.wallBottom],
              ),
            ),
            child: Column(children: [
              _toolbar(shelf, ctrl, wide),
              Expanded(
                child: books.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Could not load your library: $e')),
                  data: (list) => list.isEmpty
                      ? _emptyState(shelf.query.isNotEmpty, actions)
                      : _shelf(list, shelf, ctrl, wide),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(ShelfState shelf, ShelfController ctrl, bool wide) {
    final onWall = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 14, wide ? 40 : 16, 6),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: TextField(
                controller: _search,
                onChanged: ctrl.setQuery,
                decoration: InputDecoration(
                  hintText: 'Search title or subject',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: shelf.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            ctrl.setQuery('');
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<BookSort>(
          tooltip: 'Sort books',
          onSelected: ctrl.setSort,
          itemBuilder: (_) => [
            for (final s in BookSort.values)
              PopupMenuItem(
                value: s,
                child: Row(children: [
                  Text(s.label),
                  const Spacer(),
                  if (s == shelf.sort)
                    Icon(shelf.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
                ]),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sort, color: onWall),
              if (wide) ...[
                const SizedBox(width: 6),
                Text('Sort: ${shelf.sort.label}', style: TextStyle(color: onWall)),
              ],
              Icon(shelf.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16, color: onWall),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _emptyState(bool searching, BookshelfActions actions) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(searching ? Icons.search_off : Icons.auto_stories, size: 56),
          const SizedBox(height: 12),
          Text(
            searching ? 'No books match your search' : 'Your shelf is empty',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(searching
              ? 'Try a different title or subject.'
              : 'Create a new book or import a folder to get started.'),
          if (!searching) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => actions.newBook(context),
              icon: const Icon(Icons.add),
              label: const Text('New Book'),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _shelf(List<Book> books, ShelfState shelf, ShelfController ctrl, bool wide) {
    final desktop = _desktop;
    return LayoutBuilder(builder: (context, box) {
      const gap = 20.0;
      final pad = wide ? 40.0 : 16.0;
      final target = box.maxWidth >= 1200 ? 180.0 : (wide ? 165.0 : 130.0);
      final usable = box.maxWidth - pad * 2;
      final cols = math.max(1, ((usable + gap) / (target + gap)).floor());
      final cardW = (usable - gap * (cols - 1)) / cols;
      final rowCount = (books.length / cols).ceil();

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: ctrl.clearSelection,
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 12, bottom: 100),
          itemCount: rowCount,
          itemBuilder: (context, row) {
            final slice = books.skip(row * cols).take(cols).toList();
            return _ShelfRow(
              cardWidth: cardW,
              cols: cols,
              hPad: pad,
              gap: gap,
              children: [
                for (final b in slice)
                  BookCard(
                    key: ValueKey(b.id),
                    book: b,
                    width: cardW,
                    desktop: desktop,
                    selected: shelf.selectedIds.contains(b.id),
                    onTap: () => _onCardTap(b),
                    onDoubleTap: () => _openBook(b),
                    onOpen: () => _openBook(b),
                    onContextMenu: (pos) => _showContextMenu(b, pos),
                  ),
              ],
            );
          },
        ),
      );
    });
  }
}

/// One shelf: books standing on a wooden plank that also carries their labels.
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.cardWidth,
    required this.cols,
    required this.hPad,
    required this.gap,
    required this.children,
  });

  final double cardWidth, hPad, gap;
  final int cols;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = ShelfPalette.of(context);
    final coverH = cardWidth * 1.5;
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          right: 0,
          top: coverH - 6,
          height: BookCard.labelHeight + 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [palette.woodLight, palette.woodDark],
              ),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.22), width: 2),
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 6)),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cols; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(
                width: cardWidth,
                child: i < children.length ? children[i] : null,
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
