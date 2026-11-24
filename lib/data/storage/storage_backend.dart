/// T2 - common storage interface.
///
/// Everything above this file (BookStore, BookTransfer, repositories) talks to
/// storage only through [StorageBackend]. Two implementations exist:
///  * IoBackend  (io_backend.dart)  - dart:io paths. Windows folders and the
///    Android app-private library.
///  * SafBackend (saf_backend.dart) - Android Storage Access Framework via a
///    Kotlin MethodChannel. Refs are `content://` URIs, NOT file paths.
///
/// A "folderRef" is an opaque string: an absolute path, or a `content://` tree
/// / document URI. Files inside a folder are addressed by plain file name.
library;

import 'dart:typed_data';

enum StorageErrorKind {
  /// Access denied or revoked (also: provider is read-only).
  permissionDenied,
  notFound,
  alreadyExists,
  invalidName,

  /// Content is not what we expected (not a folder, bad ZIP, wrong book...).
  invalidData,

  /// File changed on disk since it was read; saving would overwrite it.
  conflict,
  unsupported,
  io,
}

class StorageException implements Exception {
  const StorageException(this.kind, this.message, {this.ref, this.cause});

  final StorageErrorKind kind;
  final String message;
  final String? ref;
  final Object? cause;

  /// True when the fix is "ask the user to pick the folder again".
  bool get needsReconnect =>
      kind == StorageErrorKind.permissionDenied ||
      kind == StorageErrorKind.notFound;

  @override
  String toString() =>
      'StorageException(${kind.name}): $message${ref == null ? '' : ' [$ref]'}';
}

class StorageEntry {
  const StorageEntry({
    required this.name,
    required this.ref,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String name;

  /// Ref of this entry itself (usable as a folderRef when [isDirectory]).
  final String ref;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// True for Android SAF refs.
bool isSafRef(String ref) => ref.startsWith('content://');

/// Rejects names that could escape the folder. Backends call this on every
/// name they receive.
void validateEntryName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\\') ||
      name.contains('\u0000')) {
    throw StorageException(
      StorageErrorKind.invalidName,
      'Invalid file name: "$name"',
    );
  }
}

abstract interface class StorageBackend {
  /// Throws [StorageException] (permissionDenied / notFound / invalidData) if
  /// the folder cannot be read (and written, when [write] is true).
  Future<void> checkAccess(String folderRef, {bool write = true});

  /// Human-readable folder name (last path segment / SAF display name).
  Future<String> displayName(String folderRef);

  Future<List<StorageEntry>> list(String folderRef);

  /// Null when [name] does not exist in the folder.
  Future<StorageEntry?> stat(String folderRef, String name);

  Future<Uint8List> readBytes(String folderRef, String name);

  /// When [overwrite] is false the file is created exclusively and
  /// [StorageErrorKind.alreadyExists] is thrown if it exists. When true the
  /// file is replaced (atomically on IoBackend, in place on SAF).
  Future<StorageEntry> writeBytes(
    String folderRef,
    String name,
    Uint8List bytes, {
    bool overwrite = false,
  });

  Future<void> delete(String folderRef, String name);

  /// Never replaces an existing different file ([alreadyExists] instead).
  Future<void> rename(String folderRef, String name, String newName);

  /// Never reuses an existing folder. Returns the new folder's ref.
  Future<String> createFolder(String parentRef, String name);

  /// Renames/moves a folder (used for the internal Trash). SAF: unsupported.
  Future<void> moveFolder(
    String folderRef,
    String destParentRef,
    String destName,
  );

  /// Recursively deletes a folder. Only BookStore calls it, and only on its own
  /// Trash and on half-finished imports it created itself.
  Future<void> deleteFolder(String folderRef);

  /// Whole-file access by direct ref (a file path or a SAF document URI), for
  /// ZIP import/export and cover images chosen via pickers.
  Future<Uint8List> readDocument(String docRef);
  Future<void> writeDocument(
    String docRef,
    Uint8List bytes, {
    bool overwrite = false,
  });
}
