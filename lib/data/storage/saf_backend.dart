/// Android Storage Access Framework backend. Talks to SafPlugin.kt over the
/// `com.booknotes/saf` MethodChannel. Refs are `content://` URIs:
///  * a tree URI returned by [pickTree] (permission is persisted natively), or
///  * a child document URI built with the tree (what list()/createFolder()
///    return). These are never file paths.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'storage_backend.dart';

class SafBackend implements StorageBackend {
  SafBackend([MethodChannel? channel])
    : _ch = channel ?? const MethodChannel('com.booknotes/saf');

  final MethodChannel _ch;

  StorageException _map(PlatformException e, String ref) {
    final msg = e.message ?? e.code;
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return StorageException(
          StorageErrorKind.permissionDenied,
          msg,
          ref: ref,
          cause: e,
        );
      case 'NOT_FOUND':
        return StorageException(
          StorageErrorKind.notFound,
          msg,
          ref: ref,
          cause: e,
        );
      case 'ALREADY_EXISTS':
        return StorageException(
          StorageErrorKind.alreadyExists,
          msg,
          ref: ref,
          cause: e,
        );
      case 'INVALID_NAME':
        return StorageException(
          StorageErrorKind.invalidName,
          msg,
          ref: ref,
          cause: e,
        );
      case 'INVALID_DATA':
        return StorageException(
          StorageErrorKind.invalidData,
          msg,
          ref: ref,
          cause: e,
        );
      case 'UNSUPPORTED':
        return StorageException(
          StorageErrorKind.unsupported,
          msg,
          ref: ref,
          cause: e,
        );
      default:
        return StorageException(StorageErrorKind.io, msg, ref: ref, cause: e);
    }
  }

  Future<Object?> _call(
    String method,
    Map<String, Object?> args,
    String ref,
  ) async {
    try {
      return await _ch.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      throw _map(e, ref);
    } on MissingPluginException {
      throw StorageException(
        StorageErrorKind.unsupported,
        'SAF plugin is not registered (see android_native/README_ANDROID.md)',
        ref: ref,
      );
    }
  }

  StorageEntry _entry(Object? raw) {
    final m = Map<Object?, Object?>.from(raw as Map);
    final ms = (m['modified'] as num?)?.toInt() ?? 0;
    return StorageEntry(
      name: m['name'] as String,
      ref: m['ref'] as String,
      isDirectory: m['isDir'] as bool? ?? false,
      size: (m['size'] as num?)?.toInt() ?? 0,
      modified: ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  // ------------------------------------------------------------ pickers
  /// System folder picker. Persistable read+write permission is taken natively.
  /// Returns null if the user cancels.
  Future<String?> pickTree() async =>
      await _call('pickTree', const {}, 'picker') as String?;

  /// System "save as" dialog; the system never overwrites silently (it picks a
  /// new name on conflict). Returns a document URI or null.
  Future<String?> pickCreateDocument(
    String suggestedName,
    String mimeType,
  ) async => await _call('pickCreateDocument', {
    'name': suggestedName,
    'mime': mimeType,
  }, 'picker') as String?;

  Future<String?> pickOpenDocument(List<String> mimeTypes) async =>
      await _call('pickOpenDocument', {'mimes': mimeTypes}, 'picker')
          as String?;

  /// Drops a persisted grant (call when the last book using it is removed).
  Future<void> releasePermission(String ref) async {
    await _call('releasePermission', {'ref': ref}, ref);
  }

  // ------------------------------------------------------------ backend
  @override
  Future<void> checkAccess(String folderRef, {bool write = true}) async {
    await _call('checkAccess', {'ref': folderRef, 'write': write}, folderRef);
  }

  @override
  Future<String> displayName(String folderRef) async =>
      await _call('displayName', {'ref': folderRef}, folderRef) as String;

  @override
  Future<List<StorageEntry>> list(String folderRef) async {
    final raw =
        await _call('list', {'ref': folderRef}, folderRef) as List<Object?>;
    return raw.map(_entry).toList();
  }

  @override
  Future<StorageEntry?> stat(String folderRef, String name) async {
    validateEntryName(name);
    final raw = await _call('stat', {
      'ref': folderRef,
      'name': name,
    }, folderRef);
    return raw == null ? null : _entry(raw);
  }

  @override
  Future<Uint8List> readBytes(String folderRef, String name) async {
    validateEntryName(name);
    return await _call('readBytes', {'ref': folderRef, 'name': name}, folderRef)
        as Uint8List;
  }

  @override
  Future<StorageEntry> writeBytes(
    String folderRef,
    String name,
    Uint8List bytes, {
    bool overwrite = false,
  }) async {
    validateEntryName(name);
    final raw = await _call('writeBytes', {
      'ref': folderRef,
      'name': name,
      'bytes': bytes,
      'overwrite': overwrite,
    }, folderRef);
    return _entry(raw);
  }

  @override
  Future<void> delete(String folderRef, String name) async {
    validateEntryName(name);
    await _call('delete', {'ref': folderRef, 'name': name}, folderRef);
  }

  @override
  Future<void> rename(String folderRef, String name, String newName) async {
    validateEntryName(name);
    validateEntryName(newName);
    await _call('rename', {
      'ref': folderRef,
      'name': name,
      'newName': newName,
    }, folderRef);
  }

  @override
  Future<String> createFolder(String parentRef, String name) async {
    validateEntryName(name);
    return await _call('createFolder', {
      'ref': parentRef,
      'name': name,
    }, parentRef) as String;
  }

  @override
  Future<void> moveFolder(
    String folderRef,
    String destParentRef,
    String destName,
  ) => throw const StorageException(
    StorageErrorKind.unsupported,
    'Moving folders is not supported over SAF',
  );

  @override
  Future<void> deleteFolder(String folderRef) async {
    await _call('deleteFolder', {'ref': folderRef}, folderRef);
  }

  @override
  Future<Uint8List> readDocument(String docRef) async =>
      await _call('readDocument', {'ref': docRef}, docRef) as Uint8List;

  @override
  Future<void> writeDocument(
    String docRef,
    Uint8List bytes, {
    bool overwrite = false,
  }) async {
    await _call('writeDocument', {
      'ref': docRef,
      'bytes': bytes,
      'overwrite': overwrite,
    }, docRef);
  }
}
