/// T3 - ReaderController: the single owner of page text while a book is open.
///
/// Why text is never lost when navigating:
///  * Every page that has been shown keeps its own [TextEditingController]
///    here (not in a widget), keyed by the page's stable id. Page widgets only
///    attach to it, so rebuilding / animating / disposing a widget cannot drop
///    text.
///  * Structural changes (add / delete / rename) first flush every dirty page.
///    If a flush fails the operation is aborted and the text stays in memory.
///  * A failed save never clears the dirty flag; it is retried on the next
///    edit, on [retrySave], or on [flush] when the reader is closed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/models/book.dart';
import '../../data/storage/book_store.dart' show FontSettings, PageInfo;
import '../../data/storage/storage_backend.dart'
    show StorageErrorKind, StorageException;
import 'reader_models.dart';

/// The slice of T2 the reader needs. [BookStoreReaderStorage] adapts T2's
/// BookStore; tests supply a fake.
abstract interface class ReaderStorage {
  Future<List<PageInfo>> pageInfos(String bookId);
  Future<BookPage?> readPage(String bookId, int pageNumber);
  Future<BookPage> createPage(String bookId, {int? atNumber});
  Future<void> writePage(BookPage page, {bool force = false});
  Future<void> deletePage(String bookId, int pageNumber);
  Future<BookPage> renamePage(String bookId, int pageNumber, String heading);
  Future<FontSettings> getFontSettings(String bookId);
  Future<void> setFontSettings(String bookId, FontSettings fonts);
  Future<void> markOpened(String bookId, {int? page});
}

enum SaveStatus { saved, dirty, saving, error }

/// State of one page's text.
class PageBuffer {
  PageBuffer({
    required this.id,
    required this.number,
    required this.fileName,
    required this.heading,
  }) : text = TextEditingController();

  final String id; // stable across renumbering
  int number; // 1-based, changes after insert/delete
  String fileName;
  String heading;
  final TextEditingController text;

  bool loaded = false;
  String savedText = '';
  Object? error; // last load/save error
  bool conflict = false;
  bool saving = false;

  bool get dirty => loaded && text.text != savedText;

  SaveStatus get status {
    if (saving) return SaveStatus.saving;
    if (error != null) return SaveStatus.error;
    return dirty ? SaveStatus.dirty : SaveStatus.saved;
  }
}

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.book,
    required this.storage,
    this.autosaveDelay = const Duration(milliseconds: 1500),
    ReaderLayout? initialLayout,
    this.mode = ReaderMode.edit, // edit by default
  }) : layout =
           initialLayout ??
           (book.preferredReadingMode == ReadingMode.twoPageSpread
               ? ReaderLayout.unfolded
               : ReaderLayout.folded);

  final Book book;
  final ReaderStorage storage;
  final Duration autosaveDelay;

  // ------------------------------------------------------------------ state

  ReaderMode mode;
  ReaderLayout layout;
  TypographySettings typography = const TypographySettings();

  bool loading = true;
  Object? loadError;

  /// Last error from add/delete/rename/typography save (not page saves).
  Object? operationError;

  int _current = 1;
  List<PageBuffer> _pages = [];
  Timer? _autosave;
  Timer? _openedTimer;
  Future<void> _saveChain = Future.value();
  bool _disposed = false;

  int get pageCount => _pages.length;
  int get currentPage => _current;
  bool get isEdit => mode == ReaderMode.edit;
  Spread get spread => SpreadMath.spreadFor(_current, pageCount, layout);
  List<PageBuffer> get pages => List.unmodifiable(_pages);

  PageBuffer? bufferFor(int number) =>
      number >= 1 && number <= _pages.length ? _pages[number - 1] : null;

  bool get hasUnsavedChanges => _pages.any((p) => p.dirty || p.saving);
  bool get hasSaveError => _pages.any((p) => p.error != null && p.dirty);

  SaveStatus get overallStatus {
    if (_pages.any((p) => p.saving)) return SaveStatus.saving;
    if (_pages.any((p) => p.error != null && p.dirty)) return SaveStatus.error;
    if (_pages.any((p) => p.dirty)) return SaveStatus.dirty;
    return SaveStatus.saved;
  }

  bool get canGoBack => SpreadMath.canGoBack(_current, layout);
  bool get canGoForward => SpreadMath.canGoForward(_current, pageCount, layout);

  // ------------------------------------------------------------------- open

  Future<void> open() async {
    loading = true;
    loadError = null;
    _notify();
    try {
      final infos = await storage.pageInfos(book.id);
      _pages = [for (final i in infos) _bufferFromInfo(i)];
      if (_pages.isEmpty) {
        // A book must have a page to write on.
        await storage.createPage(book.id);
        _pages = [
          for (final i in await storage.pageInfos(book.id)) _bufferFromInfo(i),
        ];
      }
      _current = SpreadMath.anchorFor(
        book.lastOpenedPage.clamp(1, _pages.length).toInt(),
        layout,
      );
      try {
        typography = TypographySettings.fromStored(
          await storage.getFontSettings(book.id),
        );
      } catch (_) {
        typography = const TypographySettings(); // fall back; not fatal
      }
      await _loadVisible();
      loading = false;
      _scheduleOpened();
    } catch (e) {
      loadError = e;
      loading = false;
    }
    _notify();
  }

  PageBuffer _bufferFromInfo(PageInfo i) => PageBuffer(
    id: i.id,
    number: i.number,
    fileName: i.fileName,
    heading: i.heading,
  )..text.addListener(_onTextChanged);

  // Called for every keystroke in any page's controller.
  void _onTextChanged() {
    if (_disposed) return;
    _scheduleAutosave();
    _notify();
  }

  // ------------------------------------------------------------ page loading

  Future<void> _loadVisible() async {
    for (final n in spread.pages) {
      await ensureLoaded(n);
    }
  }

  /// Loads a page's text once. Never replaces text the user has typed.
  Future<void> ensureLoaded(int number) async {
    final b = bufferFor(number);
    if (b == null || b.loaded) return;
    try {
      final p = await storage.readPage(book.id, b.number);
      if (p == null) {
        b.error = const StorageException(
          StorageErrorKind.notFound,
          'Page not found',
        );
        return;
      }
      b.fileName = p.fileName;
      b.savedText = p.content;
      b.text.removeListener(_onTextChanged);
      b.text.text = p.content;
      b.text.addListener(_onTextChanged);
      b.loaded = true;
      b.error = null;
    } catch (e) {
      b.error = e;
    }
    _notify();
  }

  /// Re-reads a page that failed to load or has a conflict, discarding the
  /// in-memory text of THAT page only. Only called from an explicit user action.
  Future<void> reloadPage(int number) async {
    final b = bufferFor(number);
    if (b == null) return;
    b.loaded = false;
    b.conflict = false;
    b.error = null;
    await ensureLoaded(number);
  }

  // -------------------------------------------------------------- navigation

  Future<void> goTo(int number) async {
    if (pageCount == 0) return;
    final target = SpreadMath.anchorFor(
      number.clamp(1, pageCount).toInt(),
      layout,
    );
    if (target == _current) return;
    _current = target;
    await _loadVisible();
    _scheduleOpened();
    _notify();
  }

  Future<void> next() => goTo(SpreadMath.move(_current, 1, pageCount, layout));
  Future<void> previous() =>
      goTo(SpreadMath.move(_current, -1, pageCount, layout));

  // ------------------------------------------------------------ mode/layout

  void setMode(ReaderMode m) {
    if (m == mode) return;
    mode = m;
    if (m == ReaderMode.view) unawaited(flush()); // save as we leave edit
    _notify();
  }

  Future<void> setLayout(ReaderLayout l) async {
    if (l == layout) return;
    layout = l;
    _current = SpreadMath.anchorFor(_current, layout);
    await _loadVisible();
    _notify();
  }

  // ------------------------------------------------------------------- save

  void _scheduleAutosave() {
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, () => unawaited(flush()));
  }

  /// Saves every dirty page. Returns true when nothing is left unsaved.
  /// Saves run one after another; concurrent calls queue behind each other.
  Future<bool> flush({bool force = false}) {
    _autosave?.cancel();
    final done = _saveChain.then((_) => _flushNow(force));
    _saveChain = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<bool> _flushNow(bool force) async {
    var ok = true;
    for (final b in List.of(_pages)) {
      if (!b.dirty) continue;
      if (b.conflict && !force) {
        ok = false; // needs an explicit user decision
        continue;
      }
      ok = await _savePage(b, force: force) && ok;
    }
    return ok;
  }

  Future<bool> _savePage(PageBuffer b, {required bool force}) async {
    final snapshot = b.text.text; // what we are writing
    b.saving = true;
    _notify();
    try {
      await storage.writePage(
        BookPage(
          bookId: book.id,
          number: b.number,
          fileName: b.fileName,
          content: snapshot,
        ),
        force: force,
      );
      b.savedText = snapshot; // text typed during the write stays dirty
      b.error = null;
      b.conflict = false;
      return true;
    } on StorageException catch (e) {
      b.error = e;
      b.conflict = e.kind == StorageErrorKind.conflict;
      return false;
    } catch (e) {
      b.error = e;
      return false;
    } finally {
      b.saving = false;
      _notify();
    }
  }

  /// User chose "Save again" after an error.
  Future<bool> retrySave() => flush();

  /// User chose "Overwrite" after an external-change conflict.
  Future<bool> overwriteConflicts() => flush(force: true);

  /// Throws away unsaved edits of all pages (user chose "Discard").
  void discardUnsaved() {
    _autosave?.cancel();
    for (final b in _pages) {
      if (!b.loaded) continue;
      b.text.removeListener(_onTextChanged);
      b.text.text = b.savedText;
      b.text.addListener(_onTextChanged);
      b.error = null;
      b.conflict = false;
    }
    _notify();
  }

  // ------------------------------------------------------ structural changes

  /// Adds an empty page after the current page (or spread) and goes to it.
  Future<bool> addPage() => _structural(() async {
    final at = (spread.right ?? spread.left) + 1;
    final known = {for (final b in _pages) b.id};
    await storage.createPage(book.id, atNumber: at);
    final infos = await storage.pageInfos(book.id);
    _rebuild(infos);
    final created = _pages.firstWhere(
      (b) => !known.contains(b.id),
      orElse: () => _pages.last,
    );
    created.loaded = true; // brand new => empty, nothing to read
    created.savedText = '';
    _current = SpreadMath.anchorFor(created.number, layout);
    await _loadVisible();
    _scheduleOpened();
  });

  /// Deletes page [number]. The last remaining page cannot be deleted.
  Future<bool> deletePage(int number) async {
    if (pageCount <= 1 || bufferFor(number) == null) {
      operationError = const StorageException(
        StorageErrorKind.invalidData,
        'A book needs at least one page. Clear its text instead.',
      );
      _notify();
      return false;
    }
    return _structural(() async {
      // Its text goes away with it (_rebuild disposes its buffer); the other
      // pages were already flushed by _structural.
      await storage.deletePage(book.id, number);
      final infos = await storage.pageInfos(book.id);
      _rebuild(infos);
      _current = SpreadMath.anchorFor(
        (number > pageCount ? pageCount : number).clamp(1, pageCount).toInt(),
        layout,
      );
      await _loadVisible();
      _scheduleOpened();
    });
  }

  Future<bool> renameHeading(int number, String heading) async {
    final h = heading.trim();
    final b = bufferFor(number);
    if (b == null || h.isEmpty || h == b.heading) return b != null;
    return _structural(() async {
      final renamed = await storage.renamePage(book.id, number, h);
      b.fileName = renamed.fileName;
      b.heading = h;
    });
  }

  /// Flushes everything, runs [op], reports failure through [operationError].
  Future<bool> _structural(Future<void> Function() op) async {
    operationError = null;
    if (!await flush()) {
      operationError =
          _firstPageError() ??
          const StorageException(
            StorageErrorKind.io,
            'Unsaved changes could not be saved.',
          );
      _notify();
      return false;
    }
    try {
      await op();
      _notify();
      return true;
    } catch (e) {
      operationError = e;
      _notify();
      return false;
    }
  }

  Object? _firstPageError() {
    for (final b in _pages) {
      if (b.error != null) return b.error;
    }
    return null;
  }

  /// Re-maps buffers onto fresh page infos by stable id so text survives
  /// renumbering; ids that vanished are disposed, new ids get new buffers.
  void _rebuild(List<PageInfo> infos) {
    final byId = {for (final b in _pages) b.id: b};
    final next = <PageBuffer>[];
    for (final i in infos) {
      final existing = byId.remove(i.id);
      if (existing != null) {
        existing
          ..number = i.number
          ..fileName = i.fileName
          ..heading = i.heading;
        next.add(existing);
      } else {
        next.add(_bufferFromInfo(i));
      }
    }
    for (final gone in byId.values) {
      gone.text.dispose();
    }
    _pages = next;
  }

  // -------------------------------------------------------------- typography

  Future<void> setTypography(TypographySettings t) async {
    if (t == typography) return;
    typography = t;
    _notify();
    try {
      await storage.setFontSettings(book.id, t.toStored());
    } catch (e) {
      operationError = e; // applied on screen, but not persisted
      _notify();
    }
  }

  void clearOperationError() {
    operationError = null;
    _notify();
  }

  // -------------------------------------------------------------- last opened

  void _scheduleOpened() {
    _openedTimer?.cancel();
    _openedTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_markOpened()),
    );
  }

  Future<void> _markOpened() async {
    try {
      await storage.markOpened(book.id, page: _current);
    } catch (_) {
      // Remembering the page is best-effort and must never disturb reading.
    }
  }

  // --------------------------------------------------------------- lifecycle

  /// Call when the reader closes: saves and records the page. Returns true when
  /// everything was saved (the caller decides what to do if not).
  Future<bool> close() async {
    _openedTimer?.cancel();
    final ok = await flush();
    await _markOpened();
    return ok;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autosave?.cancel();
    _openedTimer?.cancel();
    for (final b in _pages) {
      b.text.dispose();
    }
    super.dispose();
  }
}
