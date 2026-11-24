/// Platform wiring: picks the right backend per ref, resolves the library
/// root, and wraps the native pickers (file_picker on Windows, SAF on Android).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'io_backend.dart';
import 'saf_backend.dart';
import 'storage_backend.dart';

/// Routes every call to [IoBackend] or [SafBackend] based on the ref.
class CompositeBackend implements StorageBackend {
  CompositeBackend(this.io, [this.saf]);

  final StorageBackend io;
  final StorageBackend? saf;

  StorageBackend _for(String ref) {
    if (isSafRef(ref)) {
      final s = saf;
      if (s == null) {
        throw StorageException(
          StorageErrorKind.unsupported,
          'content:// folders are only available on Android',
          ref: ref,
        );
      }
      return s;
    }
    return io;
  }

  @override
  Future<void> checkAccess(String r, {bool write = true}) =>
      _for(r).checkAccess(r, write: write);
  @override
  Future<String> displayName(String r) => _for(r).displayName(r);
  @override
  Future<List<StorageEntry>> list(String r) => _for(r).list(r);
  @override
  Future<StorageEntry?> stat(String r, String n) => _for(r).stat(r, n);
  @override
  Future<Uint8List> readBytes(String r, String n) => _for(r).readBytes(r, n);
  @override
  Future<StorageEntry> writeBytes(
    String r,
    String n,
    Uint8List b, {
    bool overwrite = false,
  }) =>
      _for(r).writeBytes(r, n, b, overwrite: overwrite);
  @override
  Future<void> delete(String r, String n) => _for(r).delete(r, n);
  @override
  Future<void> rename(String r, String n, String nn) =>
      _for(r).rename(r, n, nn);
  @override
  Future<String> createFolder(String r, String n) => _for(r).createFolder(r, n);
  @override
  Future<void> moveFolder(String r, String dp, String dn) =>
      _for(r).moveFolder(r, dp, dn);
  @override
  Future<void> deleteFolder(String r) => _for(r).deleteFolder(r);
  @override
  Future<Uint8List> readDocument(String r) => _for(r).readDocument(r);
  @override
  Future<void> writeDocument(String r, Uint8List b, {bool overwrite = false}) =>
      _for(r).writeDocument(r, b, overwrite: overwrite);
}

class StoragePlatform {
  StoragePlatform._(this.backend, this.libraryRoot, this._saf);

  /// `<libraryRoot>/Books/<Book>/...`, `<libraryRoot>/library.json`.
  ///  * Windows: `%USERPROFILE%\Documents\BookNotes` (visible to the user).
  ///  * Android: app-private documents dir (internal library).
  final String libraryRoot;
  final StorageBackend backend;
  final SafBackend? _saf;

  static Future<StoragePlatform> create({String? libraryRoot}) async {
    var root = libraryRoot;
    if (root == null) {
      final docs = await getApplicationDocumentsDirectory();
      root = p.join(docs.path, 'BookNotes');
    }
    final saf = Platform.isAndroid ? SafBackend() : null;
    return StoragePlatform._(
      CompositeBackend(const IoBackend(), saf),
      root,
      saf,
    );
  }

  /// SAF persistent-permission handling is available (Android only).
  bool get hasSaf => _saf != null;

  /// Folder picker. Returns a path (Windows) or a persisted tree URI
  /// (Android); null when cancelled.
  Future<String?> pickFolder() async {
    final saf = _saf;
    if (saf != null) return saf.pickTree();
    return FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a folder');
  }

  /// Picker for a ZIP to import. Returns a doc ref for readDocument().
  Future<String?> pickZipToImport() async {
    final saf = _saf;
    if (saf != null) {
      return saf.pickOpenDocument([
        'application/zip',
        'application/x-zip-compressed',
        'application/octet-stream',
      ]);
    }
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a BookNotes ZIP',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    return r?.files.single.path;
  }

  /// "Save as" for a ZIP export. The OS dialog is what confirms an overwrite
  /// (Windows asks; Android picks a fresh name), so callers may pass the
  /// result to writeDocument(overwrite: true).
  Future<String?> pickZipSaveTarget(String suggestedName) async {
    final saf = _saf;
    if (saf != null)
      return saf.pickCreateDocument(suggestedName, 'application/zip');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export book as ZIP',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (path == null) return null;
    return path.toLowerCase().endsWith('.zip') ? path : '$path.zip';
  }

  /// Release the persisted SAF grant for [ref] (no-op elsewhere).
  Future<void> releaseFolder(String ref) async {
    final saf = _saf;
    if (saf != null && isSafRef(ref)) await saf.releasePermission(ref);
  }
}
