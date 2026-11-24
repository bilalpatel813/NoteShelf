/// T3 - reader entry points.
///
///  * [BookReaderView]   embeddable body (pages + nav + status). T4 integrates here.
///  * [ReaderScreen]     full screen: app bar, shortcuts, unsaved-change guard.
///  * [BookStoreReaderStorage] adapts T2's BookStore to [ReaderStorage].
///  * [openReader]       wire into the bookshelf: `T2Actions(ref, openBook: openReader(ref))`.
// ignore_for_file: deprecated_member_use
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../data/storage/book_store.dart';
import '../../data/storage/t2_actions.dart' show bookStoreProvider, describeStorageError;
import 'reader_controller.dart';
import 'reader_models.dart';
import 'reader_widgets.dart';
import 'typography_panel.dart';

/// Thin adapter: every call goes straight to T2's BookStore.
class BookStoreReaderStorage implements ReaderStorage {
  BookStoreReaderStorage(this.store);
  final BookStore store;

  @override
  Future<List<PageInfo>> pageInfos(String bookId) => store.pageInfos(bookId);
  @override
  Future<BookPage?> readPage(String bookId, int n) => store.readPage(bookId, n);
  @override
  Future<BookPage> createPage(String bookId, {int? atNumber}) =>
      store.createPage(bookId, atNumber: atNumber);
  @override
  Future<void> writePage(BookPage page, {bool force = false}) =>
      store.writePage(page, force: force);
  @override
  Future<void> deletePage(String bookId, int n) => store.deletePage(bookId, n);
  @override
  Future<BookPage> renamePage(String bookId, int n, String heading) =>
      store.renamePage(bookId, n, heading);
  @override
  Future<FontSettings> getFontSettings(String bookId) => store.getFontSettings(bookId);
  @override
  Future<void> setFontSettings(String bookId, FontSettings f) => store.setFontSettings(bookId, f);
  @override
  Future<void> markOpened(String bookId, {int? page}) => store.markOpened(bookId, page: page);
}

/// For `T2Actions(ref, openBook: openReader(ref))` in main.dart.
Future<void> Function(BuildContext, Book) openReader(Ref ref) => (context, book) {
      final storage = BookStoreReaderStorage(ref.read(bookStoreProvider));
      return Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ReaderScreen(book: book, storage: storage)),
      );
    };

// =============================================================================
// Embeddable body
// =============================================================================

/// The reader without a Scaffold. Give it an opened [ReaderController]; pass a
/// different [animator] to change page-turn visuals without touching editing.
class BookReaderView extends StatelessWidget {
  const BookReaderView({
    super.key,
    required this.controller,
    this.animator = const SlidePageTurnAnimator(),
  });

  final ReaderController controller;
  final PageTurnAnimator animator;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.loading) return const Center(child: CircularProgressIndicator());
        if (controller.loadError != null) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(describeStorageError(controller.loadError!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: controller.open, child: const Text('Try again')),
            ]),
          );
        }
        final scope = PageTurnScope(
          anchor: controller.spread.left,
          previousAnchor: _lastAnchor(controller),
          layout: controller.layout,
          canGoBack: controller.canGoBack,
          canGoForward: controller.canGoForward,
          goBack: controller.previous,
          goForward: controller.next,
          buildSpread: (ctx, anchor, {required interactive}) =>
              SpreadView(controller: controller, anchor: anchor, interactive: interactive),
        );
        Widget pages = DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12)],
          ),
          child: ClipRect(child: animator.build(context, scope)),
        );
        if (!controller.isEdit) {
          // Swiping is only safe in View mode (it would fight text selection in Edit).
          pages = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) controller.next();
              if (v > 200) controller.previous();
            },
            child: pages,
          );
        }
        return Column(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(12), child: pages)),
          PageNavBar(controller: controller),
        ]);
      },
    );
  }

  // Remember the previous anchor so animators can derive direction.
  static final Expando<int> _prev = Expando<int>('prevAnchor');
  static final Expando<int> _cur = Expando<int>('curAnchor');
  static int _lastAnchor(ReaderController c) {
    final now = c.spread.left;
    final cur = _cur[c];
    if (cur != now) {
      _prev[c] = cur ?? now;
      _cur[c] = now;
    }
    return _prev[c] ?? now;
  }
}

// =============================================================================
// Full screen
// =============================================================================

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.storage,
    this.animator = const SlidePageTurnAnimator(),
    this.autosaveDelay = const Duration(milliseconds: 1500),
  });

  final Book book;
  final ReaderStorage storage;
  final PageTurnAnimator animator;
  final Duration autosaveDelay;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  late final ReaderController c;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = ReaderController(
        book: widget.book, storage: widget.storage, autosaveDelay: widget.autosaveDelay);
    c.addListener(_onChange);
    unawaited(c.open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  // Save when the app is backgrounded (Android) or minimised.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) unawaited(c.flush());
  }

  Object? _shownOpError;
  void _onChange() {
    final e = c.operationError;
    if (e != null && !identical(e, _shownOpError) && mounted) {
      _shownOpError = e;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeStorageError(e))));
      c.clearOperationError();
    }
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    try {
      var ok = await c.close();
      while (!ok && mounted) {
        final choice = await _unsavedDialog();
        if (choice == _Choice.stay || choice == null) return;
        if (choice == _Choice.discard) {
          c.discardUnsaved();
          break;
        }
        ok = choice == _Choice.overwrite ? await c.overwriteConflicts() : await c.retrySave();
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  Future<_Choice?> _unsavedDialog() {
    final conflict = c.pages.any((p) => p.conflict);
    final err = c.pages.map((p) => p.error).whereType<Object>().firstOrNull;
    return showDialog<_Choice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Your changes are not saved'),
        content: Text(err == null ? 'Saving did not finish.' : describeStorageError(err)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, _Choice.stay), child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _Choice.discard),
              child: const Text('Discard changes')),
          if (conflict)
            TextButton(
                onPressed: () => Navigator.pop(ctx, _Choice.overwrite),
                child: const Text('Overwrite file')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _Choice.retry), child: const Text('Try again')),
        ],
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts() => {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => c.flush(),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
            c.setMode(c.isEdit ? ReaderMode.view : ReaderMode.edit),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): c.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): c.previous,
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): c.next,
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): c.previous,
        if (!c.isEdit) ...{
          const SingleActivator(LogicalKeyboardKey.arrowRight): c.next,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): c.previous,
          const SingleActivator(LogicalKeyboardKey.pageDown): c.next,
          const SingleActivator(LogicalKeyboardKey.pageUp): c.previous,
        },
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) unawaited(_requestClose());
        },
        child: CallbackShortcuts(
          bindings: _shortcuts(),
          child: Focus(
            autofocus: !c.isEdit,
            child: Scaffold(
              appBar: AppBar(
                leading: BackButton(onPressed: _requestClose),
                title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
                actions: _actions(context),
              ),
              body: Column(children: [
                if (c.hasSaveError) _saveErrorBanner(context),
                Expanded(child: BookReaderView(controller: c, animator: widget.animator)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) => [
        if (c.isEdit) Center(child: SaveStatusChip(controller: c)),
        if (c.isEdit)
          IconButton(
            tooltip: 'Save (Ctrl+S)',
            icon: const Icon(Icons.save_outlined),
            onPressed: c.hasUnsavedChanges ? () => c.flush() : null,
          ),
        IconButton(
          tooltip: c.isEdit ? 'Switch to View mode (Ctrl+E)' : 'Switch to Edit mode (Ctrl+E)',
          icon: Icon(c.isEdit ? Icons.menu_book_outlined : Icons.edit_outlined),
          onPressed: () => c.setMode(c.isEdit ? ReaderMode.view : ReaderMode.edit),
        ),
        IconButton(
          tooltip: c.layout == ReaderLayout.folded ? 'Unfold (two pages)' : 'Fold (one page)',
          icon: Icon(c.layout == ReaderLayout.folded
              ? Icons.auto_stories_outlined
              : Icons.crop_portrait),
          onPressed: () => c.setLayout(
              c.layout == ReaderLayout.folded ? ReaderLayout.unfolded : ReaderLayout.folded),
        ),
        IconButton(
          tooltip: 'Fonts and text',
          icon: const Icon(Icons.text_fields),
          onPressed: () => showTypographySheet(context, c),
        ),
      ];

  Widget _saveErrorBanner(BuildContext context) {
    final err = c.pages.where((p) => p.error != null && p.dirty).first;
    final conflict = err.conflict;
    final e = err.error!;
    return MaterialBanner(
      content: Text(
        'Could not save page ${err.number}. Your text is kept here. ${describeStorageError(e)}',
      ),
      leading: const Icon(Icons.error_outline),
      actions: [
        TextButton(onPressed: () => c.retrySave(), child: const Text('Try again')),
        if (conflict) ...[
          TextButton(
              onPressed: () => c.overwriteConflicts(), child: const Text('Overwrite file')),
          TextButton(
              onPressed: () => c.reloadPage(err.number),
              child: const Text('Reload from file')),
        ],
      ],
    );
  }
}

enum _Choice { stay, discard, retry, overwrite }
