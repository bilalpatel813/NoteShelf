/// dart:io implementation: Windows folders and Android app-private storage.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'storage_backend.dart';

class IoBackend implements StorageBackend {
  const IoBackend();

  /// Maps dart:io failures to [StorageException]. Public so tests can use it.
  static StorageException mapError(Object e, String ref) {
    if (e is StorageException) return e;
    if (e is PathNotFoundException) {
      return StorageException(
        StorageErrorKind.notFound,
        'Not found',
        ref: ref,
        cause: e,
      );
    }
    if (e is PathAccessException) {
      return StorageException(
        StorageErrorKind.permissionDenied,
        'Access denied',
        ref: ref,
        cause: e,
      );
    }
    if (e is PathExistsException) {
      return StorageException(
        StorageErrorKind.alreadyExists,
        'Already exists',
        ref: ref,
        cause: e,
      );
    }
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      if (code != null) {
        if (Platform.isWindows) {
          // 2/3 file or path not found, 5 access denied, 19 write protected,
          // 80/183 exists, 32/33 sharing/lock violation.
          if (code == 2 || code == 3) {
            return StorageException(
              StorageErrorKind.notFound,
              'Not found',
              ref: ref,
              cause: e,
            );
          }
          if (code == 5 || code == 19) {
            return StorageException(
              StorageErrorKind.permissionDenied,
              'Access denied',
              ref: ref,
              cause: e,
            );
          }
          if (code == 80 || code == 183) {
            return StorageException(
              StorageErrorKind.alreadyExists,
              'Already exists',
              ref: ref,
              cause: e,
            );
          }
          if (code == 32 || code == 33) {
            return StorageException(
              StorageErrorKind.io,
              'The file is in use by another program',
              ref: ref,
              cause: e,
            );
          }
        } else {
          // 1 EPERM, 2 ENOENT, 13 EACCES, 17 EEXIST, 30 EROFS.
          if (code == 2) {
            return StorageException(
              StorageErrorKind.notFound,
              'Not found',
              ref: ref,
              cause: e,
            );
          }
          if (code == 1 || code == 13 || code == 30) {
            return StorageException(
              StorageErrorKind.permissionDenied,
              'Access denied',
              ref: ref,
              cause: e,
            );
          }
          if (code == 17) {
            return StorageException(
              StorageErrorKind.alreadyExists,
              'Already exists',
              ref: ref,
              cause: e,
            );
          }
        }
      }
      return StorageException(
        StorageErrorKind.io,
        e.message,
        ref: ref,
        cause: e,
      );
    }
    return StorageException(StorageErrorKind.io, '$e', ref: ref, cause: e);
  }

  Future<T> _guard<T>(String ref, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapError(e, ref);
    }
  }

  @override
  Future<void> checkAccess(String folderRef, {bool write = true}) =>
      _guard(folderRef, () async {
        final type = await FileSystemEntity.type(folderRef);
        if (type == FileSystemEntityType.notFound) {
          throw StorageException(
            StorageErrorKind.notFound,
            'Folder not found',
            ref: folderRef,
          );
        }
        if (type != FileSystemEntityType.directory) {
          throw StorageException(
            StorageErrorKind.invalidData,
            'Not a folder',
            ref: folderRef,
          );
        }
        await Directory(folderRef).list().take(1).toList(); // read probe
        if (write) {
          final probe = File(
            p.join(folderRef, '.bn-probe-${Random().nextInt(1 << 31)}'),
          );
          await probe.create(exclusive: true);
          await probe.delete();
        }
      });

  @override
  Future<String> displayName(String folderRef) async => p.basename(folderRef);

  @override
  Future<List<StorageEntry>> list(String folderRef) =>
      _guard(folderRef, () async {
        final out = <StorageEntry>[];
        await for (final ent in Directory(folderRef).list(followLinks: false)) {
          final FileStat st;
          try {
            st = await ent.stat();
          } on FileSystemException {
            continue; // vanished or unreadable entry: skip it
          }
          out.add(
            StorageEntry(
              name: p.basename(ent.path),
              ref: ent.path,
              isDirectory: st.type == FileSystemEntityType.directory,
              size: st.size,
              modified: st.modified,
            ),
          );
        }
        return out;
      });

  @override
  Future<StorageEntry?> stat(String folderRef, String name) => _guard(
        folderRef,
        () async {
          validateEntryName(name);
          final path = p.join(folderRef, name);
          if (await FileSystemEntity.type(path) ==
              FileSystemEntityType.notFound) {
            return null;
          }
          final st = await FileStat.stat(path);
          return StorageEntry(
            name: name,
            ref: path,
            isDirectory: st.type == FileSystemEntityType.directory,
            size: st.size,
            modified: st.modified,
          );
        },
      );

  @override
  Future<Uint8List> readBytes(String folderRef, String name) =>
      _guard(folderRef, () async {
        validateEntryName(name);
        return await File(p.join(folderRef, name)).readAsBytes();
      });

  @override
  Future<StorageEntry> writeBytes(
    String folderRef,
    String name,
    Uint8List bytes, {
    bool overwrite = false,
  }) =>
      _guard(folderRef, () async {
        validateEntryName(name);
        final path = p.join(folderRef, name);
        if (!overwrite) {
          final f = File(path);
          await f.create(exclusive: true); // PathExistsException if present
          try {
            await f.writeAsBytes(bytes, flush: true);
          } catch (_) {
            try {
              await f.delete();
            } catch (_) {}
            rethrow;
          }
        } else {
          // Write beside the target, then replace it: a crash never leaves a
          // half-written page.
          final tmp = File('$path.bntmp');
          await tmp.writeAsBytes(bytes, flush: true);
          try {
            await _replace(tmp, path);
          } catch (_) {
            try {
              await tmp.delete();
            } catch (_) {}
            rethrow;
          }
        }
        final st = await FileStat.stat(path);
        return StorageEntry(
          name: name,
          ref: path,
          isDirectory: false,
          size: st.size,
          modified: st.modified,
        );
      });

  /// File.rename replaces an existing file. On Windows antivirus/indexers can
  /// hold the target briefly, so retry a few times.
  Future<void> _replace(File tmp, String path) async {
    for (var attempt = 0;; attempt++) {
      try {
        await tmp.rename(path);
        return;
      } on FileSystemException catch (e) {
        final code = e.osError?.errorCode;
        final retryable =
            Platform.isWindows && (code == 5 || code == 32 || code == 33);
        if (!retryable || attempt >= 4) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 60 * (attempt + 1)));
      }
    }
  }

  @override
  Future<void> delete(String folderRef, String name) =>
      _guard(folderRef, () async {
        validateEntryName(name);
        await File(p.join(folderRef, name)).delete();
      });

  @override
  Future<void> rename(String folderRef, String name, String newName) =>
      _guard(folderRef, () async {
        validateEntryName(name);
        validateEntryName(newName);
        final src = p.join(folderRef, name);
        final dst = p.join(folderRef, newName);
        if (await FileSystemEntity.type(dst) != FileSystemEntityType.notFound) {
          // Only allowed when dst IS src (case-only rename on a
          // case-insensitive file system). File.rename would silently replace
          // a different file on POSIX.
          if (!await FileSystemEntity.identical(src, dst)) {
            throw StorageException(
              StorageErrorKind.alreadyExists,
              '"$newName" already exists',
              ref: dst,
            );
          }
        }
        await File(src).rename(dst);
      });

  @override
  Future<String> createFolder(String parentRef, String name) => _guard(
        parentRef,
        () async {
          validateEntryName(name);
          final path = p.join(parentRef, name);
          if (await FileSystemEntity.type(path) !=
              FileSystemEntityType.notFound) {
            throw StorageException(
              StorageErrorKind.alreadyExists,
              '"$name" already exists',
              ref: path,
            );
          }
          await Directory(path).create();
          return path;
        },
      );

  @override
  Future<void> moveFolder(
    String folderRef,
    String destParentRef,
    String destName,
  ) =>
      _guard(folderRef, () async {
        validateEntryName(destName);
        final dst = p.join(destParentRef, destName);
        if (await FileSystemEntity.type(dst) != FileSystemEntityType.notFound) {
          throw StorageException(
            StorageErrorKind.alreadyExists,
            '"$destName" already exists',
            ref: dst,
          );
        }
        await Directory(folderRef).rename(dst);
      });

  @override
  Future<void> deleteFolder(String folderRef) => _guard(folderRef, () async {
        await Directory(folderRef).delete(recursive: true);
      });

  @override
  Future<Uint8List> readDocument(String docRef) =>
      _guard(docRef, () async => await File(docRef).readAsBytes());

  @override
  Future<void> writeDocument(
    String docRef,
    Uint8List bytes, {
    bool overwrite = false,
  }) async {
    await writeBytes(
      p.dirname(docRef),
      p.basename(docRef),
      bytes,
      overwrite: overwrite,
    );
  }
}
