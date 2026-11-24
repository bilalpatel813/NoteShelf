/// T2 - export a book as a normal folder or a ZIP, and import a ZIP.
///
/// Exported shape (folder and ZIP alike):
///   <Title>/booknotes.json
///   <Title>/Motion-001.txt
///   <Title>/Force-002.txt
///   <Title>/cover.png            (if the book has a cover)
///
/// Nothing is ever overwritten: folder exports pick a free folder name, ZIP
/// exports write through the OS "save as" target (or fail with alreadyExists
/// when overwrite is false), and ZIP imports always create a NEW book folder.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/models/book.dart';
import 'book_store.dart';
import 'storage_backend.dart';

const _maxZipEntries = 5000;
const _maxZipBytes = 256 * 1024 * 1024; // total uncompressed, zip-bomb guard
const _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};

class BookTransfer {
  BookTransfer(this.store);

  final BookStore store;
  StorageBackend get _backend => store.backend;

  // ------------------------------------------------------------ export

  /// Copies the book into a new folder inside [destParentRef] (a Windows
  /// directory or an Android SAF tree). Returns the new folder's ref.
  Future<String> exportFolder(String bookId, String destParentRef) async {
    final snap = await store.snapshotForExport(bookId);
    await _backend.checkAccess(destParentRef, write: true);
    final taken = {
      for (final f in await _backend.list(destParentRef)) f.name.toLowerCase(),
    };
    final name = uniqueName(snap.folderName, taken);
    final dest = await _backend.createFolder(destParentRef, name);
    try {
      for (final n in snap.fileNames) {
        await _backend.writeBytes(
          dest,
          n,
          await _backend.readBytes(snap.folderRef, n),
        );
      }
    } catch (_) {
      try {
        await _backend.deleteFolder(dest); // our own half-written export
      } catch (_) {}
      rethrow;
    }
    return dest;
  }

  /// ZIP bytes for the book (built in memory - fine for text notebooks).
  Future<Uint8List> exportZipBytes(String bookId) async {
    final snap = await store.snapshotForExport(bookId);
    final archive = Archive();
    for (final n in snap.fileNames) {
      final bytes = await _backend.readBytes(snap.folderRef, n);
      archive.addFile(
        ArchiveFile('${snap.folderName}/$n', bytes.length, bytes),
      );
    }
    final out = ZipEncoder().encode(archive);
    if (out == null) {
      throw const StorageException(
        StorageErrorKind.io,
        'Could not create the ZIP',
      );
    }
    return Uint8List.fromList(out);
  }

  /// Writes the ZIP to [destDocRef] (a file path, or a SAF document URI from
  /// the system "save as" dialog). With [overwrite] false an existing
  /// non-empty target raises alreadyExists.
  Future<String> exportZipTo(
    String bookId,
    String destDocRef, {
    bool overwrite = false,
  }) async {
    final bytes = await exportZipBytes(bookId);
    await _backend.writeDocument(destDocRef, bytes, overwrite: overwrite);
    return destDocRef;
  }

  // ------------------------------------------------------------ import

  /// Reads a ZIP from [docRef] and imports it as a new book.
  Future<Book> importZipFrom(String docRef) async {
    final bytes = await _backend.readDocument(docRef);
    final base = isSafRef(docRef) ? null : p.basenameWithoutExtension(docRef);
    return importZipBytes(bytes, fallbackName: base);
  }

  /// Imports a ZIP produced by [exportZipBytes] (or any ZIP of TXT files).
  ///  * The book root is the folder holding booknotes.json, else the folder
  ///    holding the TXT files; only files directly in that folder are used.
  ///  * Unsafe entries (absolute paths, "..", drive letters) reject the ZIP.
  ///  * A book id that already exists in the library gets a new id, so
  ///    re-importing an export never touches the original.
  Future<Book> importZipBytes(Uint8List bytes, {String? fallbackName}) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw StorageException(
        StorageErrorKind.invalidData,
        'Not a valid ZIP file',
        cause: e,
      );
    }
    if (archive.files.length > _maxZipEntries) {
      throw const StorageException(
        StorageErrorKind.invalidData,
        'ZIP has too many files',
      );
    }

    final entries = <({List<String> dir, String name, ArchiveFile file})>[];
    var total = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final raw = f.name.replaceAll('\\', '/');
      final segs = raw.split('/').where((s) => s.isNotEmpty).toList();
      if (raw.startsWith('/') ||
          segs.isEmpty ||
          segs.any((s) => s == '..') ||
          RegExp(r'^[A-Za-z]:').hasMatch(segs.first)) {
        throw StorageException(
          StorageErrorKind.invalidData,
          'Unsafe path in ZIP: ${f.name}',
        );
      }
      if (segs.any((s) => s.startsWith('.') || s == '__MACOSX'))
        continue; // hidden/metadata
      total += f.size;
      if (total > _maxZipBytes) {
        throw const StorageException(
          StorageErrorKind.invalidData,
          'ZIP is too large',
        );
      }
      entries.add((
        dir: segs.sublist(0, segs.length - 1),
        name: segs.last,
        file: f,
      ));
    }

    bool isBookFile(String n) =>
        n == metaFileName ||
        isSupportedPageFile(n) ||
        _imageExts.contains(p.extension(n).toLowerCase());

    // Root folder: shallowest booknotes.json, else shallowest folder with TXT.
    entries.sort((a, b) => a.dir.length.compareTo(b.dir.length));
    var root = entries.where((e) => e.name == metaFileName).firstOrNull?.dir;
    root ??= entries.where((e) => isSupportedPageFile(e.name)).firstOrNull?.dir;
    if (root == null) {
      throw const StorageException(
        StorageErrorKind.invalidData,
        'No TXT pages found in this ZIP',
      );
    }
    final rootDir = root;
    final selected = entries
        .where((e) => _sameDir(e.dir, rootDir) && isBookFile(e.name))
        .toList();

    final desired = rootDir.isNotEmpty
        ? rootDir.last
        : (fallbackName ?? 'Imported book');
    final made = await store.createInternalFolder(desired);
    try {
      for (final e in selected) {
        final data = Uint8List.fromList(e.file.content as List<int>);
        await _backend.writeBytes(
          made.ref,
          e.name,
          data,
        ); // exclusive: duplicates fail
      }
      return await store.adoptInternalFolder(made.name);
    } catch (_) {
      await store.discardInternalFolder(made.name);
      rethrow;
    }
  }

  bool _sameDir(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
