/// T2 - the storage engine behind TxtBookRepository / TxtPageRepository.
///
/// On-disk layout (internal library; linked folders look the same):
///
///   BookNotes/
///     library.json            registry: which books exist + snapshot for the shelf
///     Books/<Folder>/
///       booknotes.json        book metadata + ORDERED page list (authoritative order)
///       Motion-001.txt        page files: "<heading>-<number>.txt"
///       Force-002.txt
///       cover.png             optional, referenced by a relative name
///     Trash/                  deleted internal books (purged after 30 days)
///     CoverCache/             cover copies for SAF-linked books (Image.file needs a path)
///
/// Conventions owned by T2:
///  * folderRef   : absolute directory path, or a `content://` SAF URI.
///  * cover.imagePath handed to the UI is ALWAYS an absolute file path
///    (BookCard uses Image.file). booknotes.json stores the portable relative
///    file name instead.
///  * BookPage.fileName : "<sanitized heading>-<NNN>.txt", NNN = 1-based number.
///  * Page identity is a stable id in booknotes.json; file names are derived
///    from (heading, position) and are re-numbered after insert/delete/move.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/contracts/contracts.dart' show NewBookRequest;
import '../../core/models/book.dart';
import 'storage_backend.dart';

const metaFileName = 'booknotes.json';
const _registryFile = 'library.json';
const _trashRetention = Duration(days: 30);
const _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};

// ===========================================================================
// Naming helpers (pure functions, unit-tested)
// ===========================================================================

const _reservedNames = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Makes [input] safe as a file/folder name on Windows and Android.
String sanitizeFileStem(
  String input, {
  String fallback = 'Untitled',
  int maxLength = 60,
}) {
  var s = input.replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > maxLength) {
    var cut = maxLength;
    final unit = s.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF)
      cut--; // do not split a surrogate pair
    s = s.substring(0, cut);
  }
  s = s.replaceAll(
    RegExp(r'^[.\s]+|[.\s]+$'),
    '',
  ); // no leading/trailing dots or spaces
  if (s.isEmpty) return fallback;
  if (_reservedNames.contains(s.split('.').first.toLowerCase())) s = '_$s';
  return s;
}

bool isSupportedPageFile(String name) =>
    !name.startsWith('.') && name.toLowerCase().endsWith('.txt');

class ParsedPageName {
  const ParsedPageName(this.heading, this.number);
  final String heading;

  /// Number found in the file name, or null when there is none.
  final int? number;
}

/// Understands "Motion-001.txt" (our scheme) and common hand-made names:
/// "01 Intro.txt", "Page 2.txt", "page2.txt", "Chapter_03.txt".
ParsedPageName parsePageFileName(String fileName) {
  var stem = fileName;
  final dot = stem.lastIndexOf('.');
  if (dot > 0 && stem.substring(dot).toLowerCase() == '.txt')
    stem = stem.substring(0, dot);
  stem = stem.replaceFirst(RegExp(r' \(\d+\)$'), ''); // our duplicate suffix
  final original = stem;

  int? num(String s) => s.length > 9 ? null : int.tryParse(s);
  String head(String s) => s.trim().isEmpty ? original : s.trim();

  var m = RegExp(r'^(.*?)\s*[-_]\s*(\d+)$').firstMatch(stem);
  if (m != null) return ParsedPageName(head(m.group(1)!), num(m.group(2)!));
  m = RegExp(r'^(\d+)\s*[-_.\s]+\s*(.+)$').firstMatch(stem);
  if (m != null) return ParsedPageName(head(m.group(2)!), num(m.group(1)!));
  m = RegExp(r'^(.*?)\s*(\d+)$').firstMatch(stem);
  if (m != null) return ParsedPageName(head(m.group(1)!), num(m.group(2)!));
  return ParsedPageName(head(stem), null);
}

String buildPageFileName(String heading, int number, int width, {int dup = 1}) {
  final stem = sanitizeFileStem(heading, fallback: 'Page');
  final n = number.toString().padLeft(width, '0');
  return '$stem-$n${dup > 1 ? ' ($dup)' : ''}.txt';
}

/// Case-insensitive natural order: "p2" < "p10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final ca = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final cb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  bool digits(String s) => s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    final x = ca[i], y = cb[i];
    int c;
    if (digits(x) && digits(y)) {
      final nx = BigInt.parse(x), ny = BigInt.parse(y);
      c = nx.compareTo(ny);
      if (c == 0) c = x.length.compareTo(y.length);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return ca.length.compareTo(cb.length);
}

/// Order used when pages are discovered in a folder: numeric page number
/// first (so 2 < 10), files without a number last, then natural name order.
int comparePageFileNames(String a, String b) {
  const none = 1 << 62;
  final na = parsePageFileName(a).number ?? none;
  final nb = parsePageFileName(b).number ?? none;
  if (na != nb) return na.compareTo(nb);
  return naturalCompare(a, b);
}

/// "Physics", "Physics (2)", ... first one not in [takenLower].
String uniqueName(String base, Set<String> takenLower, {String ext = ''}) {
  var candidate = '$base$ext';
  for (var n = 2; takenLower.contains(candidate.toLowerCase()); n++) {
    candidate = '$base ($n)$ext';
  }
  return candidate;
}

/// Decodes TXT bytes: UTF-8 (with/without BOM), UTF-16 with BOM, else Latin-1.
String decodeText(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  if (b.length >= 2 &&
      ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
    final le = b[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(le ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]));
    }
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b); // legacy ANSI files
  }
}

/// Pages are always written as UTF-8 without BOM.
Uint8List encodeText(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _encodeJson(Object? o) => Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(o)),
    );

// ===========================================================================
// Public value types
// ===========================================================================

enum BookAccess { ok, permissionDenied, missing, error }

enum ImportMode {
  /// Copy the files into the app's internal library (always works, no
  /// permission can be revoked, but the original is not kept in sync).
  copy,

  /// Keep using the folder where it is (Windows path / Android SAF tree).
  /// Needs read+write access; can be revoked later.
  link,
}

class FontSettings {
  const FontSettings({
    this.family,
    this.size = 18,
    this.lineHeight = 1.5,
    this.weight = 400,
    this.paragraphSpacing = 8,
    this.align = 'left',
    this.colorValue,
  });

  final String? family;
  final double size;
  final double lineHeight;

  /// CSS-style weight: 100..900 in steps of 100 (T3).
  final int weight;

  /// Extra space between paragraphs, logical pixels (T3).
  final double paragraphSpacing;

  /// 'left' | 'center' | 'right' | 'justify' (T3).
  final String align;

  /// ARGB text colour, or null = follow the theme (T3).
  final int? colorValue;

  FontSettings copyWith({
    String? family,
    double? size,
    double? lineHeight,
    int? weight,
    double? paragraphSpacing,
    String? align,
    int? colorValue,
    bool clearColor = false,
  }) =>
      FontSettings(
        family: family ?? this.family,
        size: size ?? this.size,
        lineHeight: lineHeight ?? this.lineHeight,
        weight: weight ?? this.weight,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        align: align ?? this.align,
        colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      );

  Map<String, Object?> toJson() => {
        'family': family,
        'size': size,
        'lineHeight': lineHeight,
        'weight': weight,
        'paragraphSpacing': paragraphSpacing,
        'align': align,
        'colorValue': colorValue,
      };

  /// Old files (family/size/lineHeight only) still load; new fields default.
  factory FontSettings.fromJson(Object? raw) {
    if (raw is! Map) return const FontSettings();
    return FontSettings(
      family: raw['family'] is String ? raw['family'] as String : null,
      size: (raw['size'] is num) ? (raw['size'] as num).toDouble() : 18,
      lineHeight: (raw['lineHeight'] is num)
          ? (raw['lineHeight'] as num).toDouble()
          : 1.5,
      weight: (raw['weight'] is num) ? (raw['weight'] as num).toInt() : 400,
      paragraphSpacing: (raw['paragraphSpacing'] is num)
          ? (raw['paragraphSpacing'] as num).toDouble()
          : 8,
      align: raw['align'] is String ? raw['align'] as String : 'left',
      colorValue:
          raw['colorValue'] is num ? (raw['colorValue'] as num).toInt() : null,
    );
  }
}

/// Page metadata without content (the contract's BookPage has no heading).
class PageInfo {
  const PageInfo({
    required this.id,
    required this.number,
    required this.fileName,
    required this.heading,
  });
  final String id;
  final int number;
  final String fileName;
  final String heading;
}

class BookExportSnapshot {
  const BookExportSnapshot({
    required this.folderRef,
    required this.folderName,
    required this.fileNames,
  });
  final String folderRef;
  final String folderName;

  /// Files that make up the book: pages, booknotes.json, cover.
  final List<String> fileNames;
}

// ===========================================================================
// Internals
// ===========================================================================

class _Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() body) {
    final done = Completer<T>();
    final prev = _tail;
    _tail = done.future.then<void>((_) {}, onError: (Object _) {});
    prev.then<void>((_) async {
      try {
        done.complete(await body());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }
}

class _Page {
  _Page({required this.id, required this.fileName, required this.heading});
  final String id;
  String fileName;
  String heading;
}

class _Entry {
  _Entry({
    required this.book,
    required this.linked,
    this.internalName,
    this.coverName,
  });

  Book book; // book.folderRef is the resolved folder ref
  final bool linked;
  final String? internalName;
  String? coverName; // relative file name inside the folder
  bool metaLoaded = false;
  List<_Page> pages = [];
  Map<String, StorageEntry> stats = {};
  FontSettings fonts = const FontSettings();
  DateTime? createdAt;
  BookAccess access = BookAccess.ok;

  String get ref => book.folderRef;
}

bool _isTmpName(String n) => n.startsWith('.') && n.endsWith('.bntmp');
bool _isPageName(String n) => isSupportedPageFile(n) || _isTmpName(n);
String _tmpName(String pageId) => '.$pageId.bntmp';

// ===========================================================================
// BookStore
// ===========================================================================

class BookStore {
  BookStore({
    required this.backend,
    required this.libraryRoot,
    this.onFolderReleased,
    DateTime Function()? clock,
    Uuid? uuid,
  })  : _now = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid() {
    _ready = _lock.run(_init);
    _ready.ignore();
    _ready.then<void>((_) => _startBackgroundRefresh(), onError: (Object _) {});
  }

  final StorageBackend backend;
  final String libraryRoot;

  /// Called with a linked folder's ref once its book is removed (T2 wiring
  /// uses it to release the Android SAF grant).
  final Future<void> Function(String ref)? onFolderReleased;

  final DateTime Function() _now;
  final Uuid _uuid;
  final _lock = _Mutex();
  final _entries = <_Entry>[];
  final _known = <String, int?>{}; // pageId -> mtime (ms) we last read/wrote
  final _changes = StreamController<List<Book>>.broadcast();
  late final Future<void> _ready;

  String get booksRoot => p.join(libraryRoot, 'Books');
  String get trashRoot => p.join(libraryRoot, 'Trash');
  String get coverCacheRoot => p.join(libraryRoot, 'CoverCache');

  Future<void> get ready => _ready;

  /// Completes when every operation queued so far has finished (tests).
  Future<void> flush() => _lock.run(() async {});

  Future<void> dispose() async => _changes.close();

  // ------------------------------------------------------------ init / registry

  Future<void> _init() async {
    await _ensureDir(libraryRoot);
    await _ensureDir(booksRoot);
    await _ensureDir(trashRoot);
    await _ensureDir(coverCacheRoot);
    await _loadRegistry();
    await _scanInternal();
  }

  Future<void> _ensureDir(String path) async {
    try {
      await backend.checkAccess(path, write: false);
      return;
    } on StorageException catch (e) {
      if (e.kind != StorageErrorKind.notFound) rethrow;
    }
    final parent = p.dirname(path);
    if (parent == path) {
      throw StorageException(
        StorageErrorKind.notFound,
        'Cannot create $path',
        ref: path,
      );
    }
    await _ensureDir(parent);
    try {
      await backend.createFolder(parent, p.basename(path));
    } on StorageException catch (e) {
      if (e.kind != StorageErrorKind.alreadyExists) rethrow;
    }
  }

  Future<void> _backupCorrupt(
    String folder,
    String name,
    Uint8List bytes,
  ) async {
    try {
      final stamp = _now().millisecondsSinceEpoch;
      await backend.writeBytes(folder, '$name.corrupt-$stamp', bytes);
    } on StorageException {
      // best effort: the original is untouched anyway until we rewrite it
    }
  }

  Future<void> _loadRegistry() async {
    final Uint8List bytes;
    try {
      bytes = await backend.readBytes(libraryRoot, _registryFile);
    } on StorageException catch (e) {
      if (e.kind == StorageErrorKind.notFound) return;
      rethrow;
    }
    Map<String, Object?> j;
    try {
      j = Map<String, Object?>.from(jsonDecode(decodeText(bytes)) as Map);
    } catch (_) {
      await _backupCorrupt(libraryRoot, _registryFile, bytes);
      return; // _scanInternal re-adopts the internal books
    }
    final list = j['books'];
    if (list is! List) return;
    for (final raw in list) {
      try {
        final m = Map<String, Object?>.from(raw as Map);
        final linked = m['kind'] == 'linked';
        final snap = Map<String, Object?>.from(m['snapshot'] as Map);
        final internalName = linked ? null : m['name'] as String;
        final ref =
            linked ? m['ref'] as String : p.join(booksRoot, internalName!);
        final e = _Entry(
          book: Book.fromJson({...snap, 'folderRef': ref}),
          linked: linked,
          internalName: internalName,
          coverName: m['coverName'] as String?,
        );
        _applyCoverRef(e, e.book.cover.colorValue);
        _entries.add(e);
      } catch (_) {
        // skip malformed record
      }
    }
  }

  Future<void> _persistRegistry() async {
    final json = {
      'version': 1,
      'books': [
        for (final e in _entries)
          {
            'id': e.book.id,
            'kind': e.linked ? 'linked' : 'internal',
            if (e.linked) 'ref': e.ref else 'name': e.internalName,
            'coverName': e.coverName,
            'snapshot': e.book.toJson()..remove('folderRef'),
          },
      ],
    };
    await backend.writeBytes(
      libraryRoot,
      _registryFile,
      _encodeJson(json),
      overwrite: true,
    );
  }

  void _emit() {
    if (_changes.isClosed) return;
    _changes.add(List.unmodifiable(_entries.map((e) => e.book)));
  }

  /// Adopts folders found in Books/ that the registry does not know (e.g. a
  /// folder the user dropped in, or a lost registry).
  Future<void> _scanInternal() async {
    final known = {
      for (final e in _entries)
        if (!e.linked) e.internalName!.toLowerCase(),
    };
    final found = await backend.list(booksRoot);
    for (final d in found) {
      if (!d.isDirectory ||
          d.name.startsWith('.') ||
          known.contains(d.name.toLowerCase())) {
        continue;
      }
      try {
        final inner = await backend.list(d.ref);
        if (!_looksLikeBook(inner)) continue;
        await _registerFolder(d.ref, linked: false, internalName: d.name);
      } on StorageException {
        continue;
      }
    }
  }

  void _startBackgroundRefresh() {
    unawaited(() async {
      for (final e in List.of(_entries)) {
        try {
          await _lock.run(() => _refreshOne(e));
        } catch (_) {}
      }
      try {
        await _lock.run(_purgeTrash);
      } catch (_) {}
    }());
  }

  Future<void> _refreshOne(_Entry e) async {
    if (!_entries.contains(e)) return;
    final before = jsonEncode(e.book.toJson());
    try {
      await backend.checkAccess(e.ref, write: false);
      e.metaLoaded = false;
      await _sync(e);
      e.access = BookAccess.ok;
    } on StorageException catch (x) {
      e.access = _accessFor(x);
      return;
    }
    if (jsonEncode(e.book.toJson()) != before) {
      await _persistRegistry();
      _emit();
    }
  }

  BookAccess _accessFor(StorageException x) => switch (x.kind) {
        StorageErrorKind.permissionDenied => BookAccess.permissionDenied,
        StorageErrorKind.notFound => BookAccess.missing,
        _ => BookAccess.error,
      };

  Future<void> _purgeTrash() async {
    final items = await backend.list(trashRoot);
    for (final d in items) {
      if (!d.isDirectory) continue;
      final m = RegExp(r'-(\d{10,})$').firstMatch(d.name);
      if (m == null) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!));
      if (_now().difference(at) > _trashRetention) {
        try {
          await backend.deleteFolder(d.ref);
        } on StorageException {
          continue;
        }
      }
    }
  }

  // ------------------------------------------------------------ book list

  Stream<List<Book>> watchBooks() {
    late StreamController<List<Book>> c;
    StreamSubscription<List<Book>>? sub;
    c = StreamController<List<Book>>(
      onListen: () async {
        try {
          await _ready;
        } catch (e, s) {
          if (!c.isClosed) c.addError(e, s);
          return;
        }
        if (c.isClosed) return;
        sub = _changes.stream.listen(
          c.add,
        ); // subscribe first: no missed update
        c.add(List.unmodifiable(_entries.map((e) => e.book)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  Future<List<Book>> listBooks() async {
    await _ready;
    return List.unmodifiable(_entries.map((e) => e.book));
  }

  _Entry _entry(String bookId) => _entries.firstWhere(
        (e) => e.book.id == bookId,
        orElse: () => throw StorageException(
          StorageErrorKind.notFound,
          'Unknown book: $bookId',
        ),
      );

  Future<String> folderRefOf(String bookId) =>
      _lock.run(() async => _entry(bookId).ref);

  /// ok / permissionDenied / missing. Cheap; use before opening a linked book.
  Future<BookAccess> checkBook(String bookId) => _lock.run(() async {
        final e = _entry(bookId);
        try {
          await backend.checkAccess(e.ref, write: true);
          e.access = BookAccess.ok;
        } on StorageException catch (x) {
          e.access = _accessFor(x);
        }
        return e.access;
      });

  // ------------------------------------------------------------ metadata

  bool _looksLikeBook(List<StorageEntry> es) => es.any(
        (f) =>
            !f.isDirectory &&
            (f.name == metaFileName || isSupportedPageFile(f.name)),
      );

  String? _coverPathFor(_Entry e) {
    final n = e.coverName;
    if (n == null) return null;
    if (isSafRef(e.ref))
      return p.join(
        coverCacheRoot,
        '${e.book.id}${p.extension(n).toLowerCase()}',
      );
    return p.join(e.ref, n);
  }

  void _applyCoverRef(_Entry e, int colorValue) {
    e.book = e.book.copyWith(
      cover: BookCoverRef(
        imagePath: _coverPathFor(e),
        colorValue: colorValue,
        design: e.book.cover.design,
      ),
    );
  }

  Future<void> _refreshCoverCache(_Entry e) async {
    final n = e.coverName;
    if (n == null || !isSafRef(e.ref)) return;
    try {
      final bytes = await backend.readBytes(e.ref, n);
      await backend.writeBytes(
        coverCacheRoot,
        p.basename(_coverPathFor(e)!),
        bytes,
        overwrite: true,
      );
    } on StorageException {
      // cover is cosmetic
    }
  }

  /// Only a plain image file name inside the book folder is accepted from
  /// metadata (it may come from an untrusted ZIP).
  String? _safeCoverName(Object? v) {
    if (v is! String) return null;
    try {
      validateEntryName(v);
    } on StorageException {
      return null;
    }
    return _imageExts.contains(p.extension(v).toLowerCase()) ? v : null;
  }

  /// Reads booknotes.json into [e]. Returns true when the file should be
  /// (re)written (missing, corrupt, or repaired).
  Future<bool> _readMeta(_Entry e, Map<String, StorageEntry> files) async {
    e.metaLoaded = true;
    if (!files.containsKey(metaFileName)) {
      e.pages = [];
      return true;
    }
    final bytes = await backend.readBytes(e.ref, metaFileName);
    Map<String, Object?> j;
    try {
      j = Map<String, Object?>.from(jsonDecode(decodeText(bytes)) as Map);
    } catch (_) {
      await _backupCorrupt(e.ref, metaFileName, bytes);
      e.pages = [];
      return true;
    }
    var dirty = j['id'] != e.book.id;

    String? str(String k) =>
        j[k] is String && (j[k] as String).trim().isNotEmpty
            ? (j[k] as String).trim()
            : null;
    DateTime? opened;
    if (j['lastOpenedAt'] is String)
      opened = DateTime.tryParse(j['lastOpenedAt'] as String);
    final cover = j['cover'] is Map ? j['cover'] as Map : const {};
    e.coverName = _safeCoverName(cover['imagePath']);
    e.book = e.book.copyWith(
      cover: BookCoverRef.fromJson({
        ...Map<String, Object?>.from(cover),
        'imagePath': e.coverName,
        if (cover['colorValue'] is! num) 'colorValue': e.book.cover.colorValue,
      }),
      title: str('title'),
      subject: str('subject'),
      lastOpenedPage: j['lastOpenedPage'] is num
          ? (j['lastOpenedPage'] as num).toInt().clamp(1, 1 << 30).toInt()
          : null,
      lastOpenedAt: opened,
      preferredReadingMode: ReadingMode.values.firstWhere(
        (m) => m.name == j['preferredReadingMode'],
        orElse: () => e.book.preferredReadingMode,
      ),
    );
    _applyCoverRef(
      e,
      cover['colorValue'] is num
          ? (cover['colorValue'] as num).toInt()
          : e.book.cover.colorValue,
    );
    e.fonts = FontSettings.fromJson(j['fontSettings']);
    if (j['createdAt'] is String)
      e.createdAt = DateTime.tryParse(j['createdAt'] as String);

    final seenIds = <String>{};
    final seenFiles = <String>{};
    final pages = <_Page>[];
    final raw = j['pages'];
    if (raw is List) {
      for (final r in raw) {
        if (r is! Map) {
          dirty = true;
          continue;
        }
        final id = r['id'];
        final file = r['file'];
        if (id is! String || id.isEmpty || file is! String) {
          dirty = true;
          continue;
        }
        try {
          validateEntryName(file);
        } on StorageException {
          dirty = true;
          continue;
        }
        if (!_isPageName(file) ||
            !seenIds.add(id) ||
            !seenFiles.add(file.toLowerCase())) {
          dirty = true;
          continue;
        }
        final h = r['heading'];
        pages.add(
          _Page(
            id: id,
            fileName: file,
            heading: h is String && h.trim().isNotEmpty
                ? h.trim()
                : parsePageFileName(file).heading,
          ),
        );
      }
    } else {
      dirty = true;
    }
    e.pages = pages;
    await _refreshCoverCache(e);
    return dirty;
  }

  Future<void> _saveMeta(_Entry e) async {
    final b = e.book;
    final json = {
      'schemaVersion': 1,
      'id': b.id,
      'title': b.title,
      'subject': b.subject,
      'createdAt': (e.createdAt ?? _now()).toIso8601String(),
      'cover': {...b.cover.toJson(), 'imagePath': e.coverName},
      'lastOpenedPage': b.lastOpenedPage,
      'lastOpenedAt': b.lastOpenedAt?.toIso8601String(),
      'preferredReadingMode': b.preferredReadingMode.name,
      'fontSettings': e.fonts.toJson(),
      'pages': [
        for (final pg in e.pages)
          {'id': pg.id, 'file': pg.fileName, 'heading': pg.heading},
      ],
    };
    await backend.writeBytes(
      e.ref,
      metaFileName,
      _encodeJson(json),
      overwrite: true,
    );
    e.createdAt ??= _now();
  }

  /// Persists metadata + registry and notifies the shelf.
  Future<void> _commit(_Entry e, {bool bestEffortMeta = false}) async {
    try {
      await _saveMeta(e);
    } on StorageException {
      if (!bestEffortMeta) rethrow;
    }
    await _afterChange(e);
  }

  Future<void> _afterChange(_Entry e) async {
    e.book = e.book.copyWith(pageCount: e.pages.length);
    await _persistRegistry();
    _emit();
  }

  // ------------------------------------------------------------ folder <-> pages

  /// Reconciles booknotes.json with what is really in the folder:
  ///  * page files that vanished are dropped,
  ///  * new TXT files are appended in numeric order,
  ///  * a missing/corrupt booknotes.json is rebuilt (the corrupt one is kept
  ///    as booknotes.json.corrupt-<time>).
  Future<void> _sync(_Entry e, {bool strictSave = false}) async {
    final listing = await backend.list(e.ref);
    final files = {
      for (final f in listing)
        if (!f.isDirectory) f.name: f,
    };
    var dirty = false;
    if (!e.metaLoaded) dirty = await _readMeta(e, files);

    String? find(String wanted) {
      if (files.containsKey(wanted)) return wanted;
      final lower = wanted.toLowerCase();
      for (final n in files.keys) {
        if (n.toLowerCase() == lower) return n;
      }
      return null;
    }

    final kept = <_Page>[];
    final used = <String>{};
    for (final pg in e.pages) {
      // A re-numbering interrupted by a crash leaves the file under its
      // temporary name: find it there.
      final actual = find(pg.fileName) ?? find(_tmpName(pg.id));
      if (actual == null) {
        dirty = true;
        continue;
      }
      if (actual != pg.fileName) {
        pg.fileName = actual;
        dirty = true;
      }
      used.add(actual.toLowerCase());
      kept.add(pg);
    }
    final fresh = files.keys
        .where(
          (n) => isSupportedPageFile(n) && !used.contains(n.toLowerCase()),
        )
        .toList()
      ..sort(comparePageFileNames);
    for (final n in fresh) {
      kept.add(
        _Page(
          id: _uuid.v4(),
          fileName: n,
          heading: parsePageFileName(n).heading,
        ),
      );
      dirty = true;
    }
    e.pages = kept;
    e.stats = files;

    if (dirty) {
      try {
        await _saveMeta(e);
      } on StorageException {
        if (strictSave) rethrow; // read-only folder: still usable for reading
      }
    }
    e.book = e.book.copyWith(pageCount: e.pages.length);
    if (e.pages.any((x) => _isTmpName(x.fileName))) {
      try {
        await _normalize(e);
      } on StorageException {
        // will retry on the next structural change
      }
    }
  }

  int _width(_Entry e) => e.pages.length.toString().length.clamp(3, 9).toInt();

  /// Renames page files so every name is "<heading>-<NNN>.txt" with NNN equal
  /// to the page's position, then saves metadata/registry.
  ///
  /// Crash safety (two phases through temporary names):
  ///  1. every file that must change is renamed to ".<pageId>.bntmp"
  ///  2. booknotes.json is saved with the FINAL names
  ///  3. temp names are renamed to the final names
  /// _sync() finds a page under its listed name OR its temp name, so a crash
  /// between any two steps loses nothing.
  Future<void> _normalize(_Entry e) async {
    final width = _width(e);
    final moves = <({_Page page, String from, String tmp, String target})>[];
    for (var i = 0; i < e.pages.length; i++) {
      final pg = e.pages[i];
      final target = buildPageFileName(pg.heading, i + 1, width);
      if (pg.fileName != target) {
        moves.add((
          page: pg,
          from: pg.fileName,
          tmp: _tmpName(pg.id),
          target: target,
        ));
      }
    }
    if (moves.isEmpty) {
      await _saveMeta(e);
      await _afterChange(e);
      return;
    }
    for (final m in moves) {
      if (m.from != m.tmp) await backend.rename(e.ref, m.from, m.tmp);
    }
    for (final m in moves) {
      m.page.fileName = m.target;
    }
    await _saveMeta(e);
    for (final m in moves) {
      await backend.rename(e.ref, m.tmp, m.target);
    }
    final fresh = await backend.list(e.ref);
    e.stats = {
      for (final f in fresh)
        if (!f.isDirectory) f.name: f,
    };
    await _afterChange(e);
  }

  // ------------------------------------------------------------ book operations

  Future<Book> createBook(NewBookRequest request) => _lock.run(() async {
        final title = request.title.trim();
        if (title.isEmpty) {
          throw const StorageException(
            StorageErrorKind.invalidName,
            'A title is required',
          );
        }
        final taken = await _lowerNames(booksRoot);
        final folderName = uniqueName(
          sanitizeFileStem(title, fallback: 'Book'),
          taken,
        );
        final ref = await backend.createFolder(booksRoot, folderName);
        try {
          final e = _Entry(
            book: Book(
              id: _uuid.v4(),
              title: title,
              subject: request.subject.trim().isEmpty
                  ? 'General'
                  : request.subject.trim(),
              folderRef: ref,
              cover: BookCoverRef(colorValue: request.coverColorValue),
              pageCount: 1,
            ),
            linked: false,
            internalName: folderName,
          )..metaLoaded = true;
          e.createdAt = _now();
          e.coverName = await _importCover(ref, request.coverImagePath);
          _applyCoverRef(e, request.coverColorValue);
          final first = _Page(
            id: _uuid.v4(),
            fileName: buildPageFileName('Page', 1, 3),
            heading: 'Page',
          );
          await backend.writeBytes(ref, first.fileName, Uint8List(0));
          e.pages = [first];
          await _saveMeta(e);
          _entries.add(e);
          try {
            await _afterChange(e);
          } catch (_) {
            _entries.remove(e);
            rethrow;
          }
          return e.book;
        } catch (_) {
          try {
            await backend.deleteFolder(ref); // our own brand-new folder
          } catch (_) {}
          rethrow;
        }
      });

  Future<Set<String>> _lowerNames(String folderRef) async => {
        for (final f in await backend.list(folderRef)) f.name.toLowerCase(),
      };

  /// Copies a picked image into the book folder as cover[.N].<ext>. Returns
  /// the relative file name, or null if it could not be read.
  Future<String?> _importCover(String folderRef, String? source) async {
    if (source == null || source.isEmpty) return null;
    try {
      final bytes = await backend.readDocument(source);
      var ext = p.extension(source).toLowerCase();
      if (!_imageExts.contains(ext)) ext = '.png';
      final name = uniqueName('cover', await _lowerNames(folderRef), ext: ext);
      await backend.writeBytes(folderRef, name, bytes);
      return name;
    } on StorageException {
      return null;
    }
  }

  Future<void> updateBook(Book book) => _lock.run(() async {
        final e = _entry(book.id);
        if (!e.metaLoaded) await _sync(e);
        final incoming = book.cover.imagePath;
        if (incoming == null) {
          e.coverName = null;
        } else if (incoming != _coverPathFor(e)) {
          final name = await _importCover(e.ref, incoming);
          if (name == null) {
            throw const StorageException(
                StorageErrorKind.io, 'Could not import the cover artwork.');
          }
          e.coverName = name;
        }
        final title = book.title.trim();
        e.book = e.book.copyWith(
          title: title.isEmpty ? null : title,
          subject: book.subject.trim().isEmpty ? null : book.subject.trim(),
          lastOpenedPage: book.lastOpenedPage < 1 ? 1 : book.lastOpenedPage,
          lastOpenedAt: book.lastOpenedAt,
          preferredReadingMode: book.preferredReadingMode,
        );
        e.book = e.book.copyWith(cover: book.cover);
        _applyCoverRef(e, book.cover.colorValue);
        await _commit(e);
        await _refreshCoverCache(e);
      });

  Future<void> markOpened(String bookId, {int? page}) => _lock.run(() async {
        final idx = _entries.indexWhere((x) => x.book.id == bookId);
        if (idx < 0) return;
        final e = _entries[idx];
        e.book = e.book.copyWith(
          lastOpenedAt: _now(),
          lastOpenedPage: page == null ? null : (page < 1 ? 1 : page),
        );
        // Shelf info must work even if the folder permission was revoked.
        await _commit(e, bestEffortMeta: true);
      });

  Future<FontSettings> getFontSettings(String bookId) =>
      _lock.run(() async => _entry(bookId).fonts);

  Future<void> setFontSettings(String bookId, FontSettings fonts) =>
      _lock.run(() async {
        final e = _entry(bookId);
        if (!e.metaLoaded) await _sync(e);
        e.fonts = fonts;
        await _commit(e);
      });

  /// Internal copies are moved to Trash/ (purged after 30 days). Linked
  /// folders are only unlinked: the user's files are never deleted.
  Future<void> deleteBook(String bookId) => _lock.run(() async {
        final idx = _entries.indexWhere((x) => x.book.id == bookId);
        if (idx < 0) return;
        final e = _entries[idx];
        if (!e.linked) {
          try {
            final stamp = _now().millisecondsSinceEpoch;
            await backend.moveFolder(
                e.ref, trashRoot, '${e.internalName}-$stamp');
          } on StorageException catch (x) {
            if (x.kind != StorageErrorKind.notFound) rethrow; // already gone
          }
        }
        _entries.removeAt(idx);
        for (final pg in e.pages) {
          _known.remove(pg.id);
        }
        await _persistRegistry();
        _emit();
        if (e.linked) {
          final shared =
              _entries.any((o) => o.linked && o.ref.startsWith(e.ref));
          if (!shared) {
            try {
              await onFolderReleased?.call(e.ref);
            } catch (_) {}
          }
        }
      });

  // ------------------------------------------------------------ import

  /// Imports one folder (or, if it holds no pages itself, each sub-folder
  /// that does). See [ImportMode].
  Future<List<Book>> importFolder(
    String folderPath, {
    ImportMode mode = ImportMode.copy,
  }) =>
      _lock.run(() async {
        await backend.checkAccess(folderPath, write: mode == ImportMode.link);
        final top = await backend.list(folderPath);
        if (_looksLikeBook(top)) return [await _importOne(folderPath, mode)];

        final books = <Book>[];
        StorageException? firstError;
        for (final d in top.where(
          (d) => d.isDirectory && !d.name.startsWith('.'),
        )) {
          try {
            if (_looksLikeBook(await backend.list(d.ref))) {
              books.add(await _importOne(d.ref, mode));
            }
          } on StorageException catch (x) {
            firstError ??= x;
          }
        }
        if (books.isEmpty) {
          throw firstError ??
              StorageException(
                StorageErrorKind.invalidData,
                'No TXT pages found in this folder',
                ref: folderPath,
              );
        }
        return books;
      });

  Future<Book> _importOne(String srcRef, ImportMode mode) async {
    if (mode == ImportMode.link) {
      await backend.checkAccess(srcRef, write: true);
      final dup = _entries
          .where((e) => e.linked && _sameRef(e.ref, srcRef))
          .firstOrNull;
      if (dup != null) return dup.book; // already linked
      return _registerFolder(srcRef, linked: true);
    }
    await backend.checkAccess(srcRef, write: false);
    final taken = await _lowerNames(booksRoot);
    final srcName = await backend.displayName(srcRef);
    final name = uniqueName(sanitizeFileStem(srcName, fallback: 'Book'), taken);
    final dest = await backend.createFolder(booksRoot, name);
    try {
      for (final f in await backend.list(srcRef)) {
        final lower = f.name.toLowerCase();
        final copy = !f.isDirectory &&
            (f.name == metaFileName ||
                isSupportedPageFile(f.name) ||
                (!f.name.startsWith('.') &&
                    _imageExts.contains(p.extension(lower))));
        if (!copy) continue;
        await backend.writeBytes(
          dest,
          f.name,
          await backend.readBytes(srcRef, f.name),
        );
      }
      return await _registerFolder(
        dest,
        linked: false,
        internalName: name,
        titleHint: srcName,
      );
    } catch (_) {
      try {
        await backend.deleteFolder(dest); // our own half-finished copy
      } catch (_) {}
      rethrow;
    }
  }

  bool _sameRef(String a, String b) =>
      isSafRef(a) ? a == b : p.equals(p.normalize(a), p.normalize(b));

  /// Creates an empty, uniquely named folder in Books/ for a caller that
  /// fills it (ZIP import) and then calls [adoptInternalFolder].
  Future<({String name, String ref})> createInternalFolder(
    String desiredName,
  ) =>
      _lock.run(() async {
        final taken = await _lowerNames(booksRoot);
        final name = uniqueName(
          sanitizeFileStem(desiredName, fallback: 'Book'),
          taken,
        );
        return (name: name, ref: await backend.createFolder(booksRoot, name));
      });

  Future<Book> adoptInternalFolder(String name) => _lock.run(() async {
        final ref = p.join(booksRoot, name);
        if (!_looksLikeBook(await backend.list(ref))) {
          throw StorageException(
            StorageErrorKind.invalidData,
            'No TXT pages found',
            ref: ref,
          );
        }
        return _registerFolder(ref, linked: false, internalName: name);
      });

  /// Removes a folder created by [createInternalFolder] after a failed fill.
  Future<void> discardInternalFolder(String name) => _lock.run(() async {
        try {
          await backend.deleteFolder(p.join(booksRoot, name));
        } on StorageException {
          // nothing more we can do
        }
      });

  /// Registers an existing folder as a book. A book id already present in the
  /// library (re-import of an export, copied folder) gets a fresh id.
  Future<Book> _registerFolder(
    String ref, {
    required bool linked,
    String? internalName,
    String? titleHint,
  }) async {
    var id = await _peekMetaId(ref);
    if (id == null || _entries.any((e) => e.book.id == id)) id = _uuid.v4();
    final e = _Entry(
      book: Book(
        id: id,
        title: titleHint ?? await backend.displayName(ref),
        subject: 'General',
        folderRef: ref,
      ),
      linked: linked,
      internalName: internalName,
    );
    await _sync(e, strictSave: true);
    if (e.pages.isEmpty && !linked) {
      throw StorageException(
        StorageErrorKind.invalidData,
        'No TXT pages found',
        ref: ref,
      );
    }
    _entries.add(e);
    try {
      await _afterChange(e);
    } catch (_) {
      _entries.remove(e);
      rethrow;
    }
    return e.book;
  }

  Future<String?> _peekMetaId(String ref) async {
    try {
      final j = jsonDecode(
        decodeText(await backend.readBytes(ref, metaFileName)),
      );
      return j is Map && j['id'] is String && (j['id'] as String).isNotEmpty
          ? j['id'] as String
          : null;
    } on StorageException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Points a linked book at a (re-picked) folder after its permission was
  /// revoked or the folder moved. The folder must hold the same book.
  Future<Book> relinkBook(String bookId, String newFolderRef) =>
      _lock.run(() async {
        final e = _entry(bookId);
        if (!e.linked) {
          throw const StorageException(
            StorageErrorKind.invalidData,
            'Only linked books can be reconnected',
          );
        }
        await backend.checkAccess(newFolderRef, write: true);
        final listing = await backend.list(newFolderRef);
        if (!_looksLikeBook(listing)) {
          throw StorageException(
            StorageErrorKind.invalidData,
            'No TXT pages found in that folder',
            ref: newFolderRef,
          );
        }
        final other = await _peekMetaId(newFolderRef);
        if (other != null && other != bookId) {
          throw StorageException(
            StorageErrorKind.invalidData,
            'That folder belongs to a different book',
            ref: newFolderRef,
          );
        }
        final oldRef = e.ref;
        e.book = e.book.copyWith(folderRef: newFolderRef);
        e.metaLoaded = false;
        try {
          await _sync(e, strictSave: true);
        } catch (_) {
          e.book = e.book.copyWith(folderRef: oldRef);
          rethrow;
        }
        e.access = BookAccess.ok;
        await _afterChange(e);
        return e.book;
      });

  // ------------------------------------------------------------ pages

  Future<List<BookPage>> listPages(String bookId, {bool withContent = false}) =>
      _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        final out = <BookPage>[];
        for (var i = 0; i < e.pages.length; i++) {
          final pg = e.pages[i];
          out.add(
            BookPage(
              bookId: bookId,
              number: i + 1,
              fileName: pg.fileName,
              content: withContent
                  ? decodeText(await backend.readBytes(e.ref, pg.fileName))
                  : '',
              updatedAt: e.stats[pg.fileName]?.modified,
            ),
          );
        }
        return out;
      });

  Future<List<PageInfo>> pageInfos(String bookId) => _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        return [
          for (var i = 0; i < e.pages.length; i++)
            PageInfo(
              id: e.pages[i].id,
              number: i + 1,
              fileName: e.pages[i].fileName,
              heading: e.pages[i].heading,
            ),
        ];
      });

  /// Null when [pageNumber] is out of range.
  Future<BookPage?> readPage(String bookId, int pageNumber) =>
      _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        if (pageNumber < 1 || pageNumber > e.pages.length) return null;
        final pg = e.pages[pageNumber - 1];
        final st = await backend.stat(e.ref, pg.fileName); // stat BEFORE read
        final content = decodeText(await backend.readBytes(e.ref, pg.fileName));
        _known[pg.id] = st?.modified?.millisecondsSinceEpoch;
        return BookPage(
          bookId: bookId,
          number: pageNumber,
          fileName: pg.fileName,
          content: content,
          updatedAt: st?.modified,
        );
      });

  /// Creates an empty page at 1-based [atNumber] (default: end). Pages after
  /// it are renumbered (their file names change - reload the page list).
  Future<BookPage> createPage(
    String bookId, {
    int? atNumber,
    String? heading,
  }) =>
      _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        final n = e.pages.length;
        final pos = (atNumber ?? n + 1).clamp(1, n + 1).toInt();
        final h = (heading ?? '').trim();
        final pg = _Page(
          id: _uuid.v4(),
          fileName: '',
          heading: h.isEmpty ? 'Page' : h,
        );
        pg.fileName = _tmpName(pg.id);
        await backend.writeBytes(e.ref, pg.fileName, Uint8List(0)); // exclusive
        e.pages.insert(pos - 1, pg);
        try {
          await _normalize(e);
        } catch (_) {
          e.pages.remove(pg);
          rethrow;
        }
        return BookPage(bookId: bookId, number: pos, fileName: pg.fileName);
      });

  /// Saves [page].content to the file named [page.fileName].
  ///
  /// Throws [StorageErrorKind.conflict] when the file was changed outside the
  /// app since it was read here, or when the page was renumbered/removed
  /// meanwhile (reload and retry). [force] skips the external-change check.
  Future<void> writePage(
    BookPage page, {
    bool force = false,
  }) =>
      _lock.run(() async {
        final e = _entry(page.bookId);
        if (!e.metaLoaded) await _sync(e);
        final pg =
            e.pages.where((x) => x.fileName == page.fileName).firstOrNull;
        if (pg == null) {
          throw StorageException(
            StorageErrorKind.conflict,
            'Page "${page.fileName}" was renamed, renumbered or removed. Reload the book.',
            ref: e.ref,
          );
        }
        final st = await backend.stat(e.ref, pg.fileName);
        final known = _known[pg.id];
        final mtime = st?.modified?.millisecondsSinceEpoch;
        if (!force && known != null && mtime != null && mtime != known) {
          throw StorageException(
            StorageErrorKind.conflict,
            'Page "${pg.fileName}" was changed outside BookNotes since you opened it.',
            ref: e.ref,
          );
        }
        final written = await backend.writeBytes(
          e.ref,
          pg.fileName,
          encodeText(page.content),
          overwrite: true,
        );
        _known[pg.id] = written.modified?.millisecondsSinceEpoch;
      });

  Future<void> deletePage(String bookId, int pageNumber) => _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        if (pageNumber < 1 || pageNumber > e.pages.length) {
          throw const StorageException(
              StorageErrorKind.notFound, 'No such page');
        }
        final pg = e.pages[pageNumber - 1];
        try {
          await backend.delete(
            e.ref,
            pg.fileName,
          ); // file first: a crash only drops the entry
        } on StorageException catch (x) {
          if (x.kind != StorageErrorKind.notFound) rethrow;
        }
        e.pages.removeAt(pageNumber - 1);
        _known.remove(pg.id);
        await _normalize(e);
      });

  /// Moves a page to a new 1-based position and renumbers the files.
  Future<void> movePage(String bookId, int from, int to) => _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        final n = e.pages.length;
        if (from < 1 || from > n) {
          throw const StorageException(
              StorageErrorKind.notFound, 'No such page');
        }
        final pg = e.pages.removeAt(from - 1);
        e.pages.insert(to.clamp(1, n).toInt() - 1, pg);
        await _normalize(e);
      });

  /// Changes a page heading and its file name. Never overwrites: a clash is
  /// resolved with " (2)". Returns the page with its NEW fileName (no content).
  Future<BookPage> renamePage(
    String bookId,
    int pageNumber,
    String newHeading,
  ) =>
      _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        if (pageNumber < 1 || pageNumber > e.pages.length) {
          throw const StorageException(
              StorageErrorKind.notFound, 'No such page');
        }
        final heading = newHeading.trim();
        if (heading.isEmpty) {
          throw const StorageException(
            StorageErrorKind.invalidName,
            'A heading is required',
          );
        }
        final pg = e.pages[pageNumber - 1];
        final width = _width(e);
        final taken = {
          for (final n in e.stats.keys)
            if (n != pg.fileName) n.toLowerCase(),
        };
        var target = buildPageFileName(heading, pageNumber, width);
        for (var dup = 2; taken.contains(target.toLowerCase()); dup++) {
          target = buildPageFileName(heading, pageNumber, width, dup: dup);
        }
        if (target != pg.fileName) {
          await backend.rename(e.ref, pg.fileName, target);
          pg.fileName = target;
        }
        pg.heading = heading;
        await _commit(e);
        return BookPage(
            bookId: bookId, number: pageNumber, fileName: pg.fileName);
      });

  // ------------------------------------------------------------ export support

  /// Brings metadata up to date and lists the files that make up a book.
  Future<BookExportSnapshot> snapshotForExport(String bookId) =>
      _lock.run(() async {
        final e = _entry(bookId);
        await _sync(e);
        try {
          await _saveMeta(e);
        } on StorageException catch (x) {
          if (x.kind != StorageErrorKind.permissionDenied)
            rethrow; // read-only source is fine
        }
        final names = <String>[for (final pg in e.pages) pg.fileName];
        if (await backend.stat(e.ref, metaFileName) != null)
          names.add(metaFileName);
        final c = e.coverName;
        if (c != null && await backend.stat(e.ref, c) != null) names.add(c);
        return BookExportSnapshot(
          folderRef: e.ref,
          folderName: sanitizeFileStem(e.book.title, fallback: 'Book'),
          fileNames: names,
        );
      });
}
