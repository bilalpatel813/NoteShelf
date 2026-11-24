/// T2 - New Book / Import Folder flows (+ export/import/reconnect helpers).
///
/// openBook is NOT implemented here: it is forwarded to [openBook] when given
/// (T3 passes its navigation) and otherwise to DemoBookshelfActions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/contracts.dart';
import '../../core/models/book.dart';
import '../../features/bookshelf/bookshelf_providers.dart';
import 'book_store.dart';
import 'storage_backend.dart';
import 'txt_repositories.dart';

/// Typed access to the T2 repositories from any provider/widget.
final txtBookRepositoryProvider = Provider<TxtBookRepository>((ref) {
  final r = ref.watch(bookRepositoryProvider);
  if (r is TxtBookRepository) return r;
  throw StateError('bookRepositoryProvider must be overridden with TxtBookRepository');
});

/// Extra storage API (rename heading, move page, fonts, relink, export...).
final bookStoreProvider = Provider<BookStore>((ref) => ref.watch(txtBookRepositoryProvider).store);

/// User-facing text for a storage failure.
String describeStorageError(Object e) {
  if (e is! StorageException) return 'Something went wrong: $e';
  switch (e.kind) {
    case StorageErrorKind.permissionDenied:
      return 'BookNotes no longer has permission to use this folder. '
          'Reconnect it by choosing the folder again, or import it as a copy.';
    case StorageErrorKind.notFound:
      return 'The folder or file could not be found. It may have been moved or deleted.';
    case StorageErrorKind.alreadyExists:
      return 'A file with that name already exists, so nothing was overwritten.';
    case StorageErrorKind.conflict:
      return 'This page was changed outside BookNotes. Reload it before saving, '
          'or save anyway to replace the other version.';
    case StorageErrorKind.invalidData:
    case StorageErrorKind.invalidName:
    case StorageErrorKind.unsupported:
    case StorageErrorKind.io:
      return e.message;
  }
}

class T2Actions implements BookshelfActions {
  T2Actions(this._ref, {Future<void> Function(BuildContext, Book)? openBook})
      : _openBook = openBook;

  final Ref _ref;
  final Future<void> Function(BuildContext, Book)? _openBook;

  TxtBookRepository get _repo => _ref.read(txtBookRepositoryProvider);

  // ---------------------------------------------------------------- shelf hooks

  @override
  Future<void> newBook(BuildContext context) async {
    final req = await showDialog<NewBookRequest>(
      context: context,
      builder: (_) => const _NewBookDialog(),
    );
    if (req == null || !context.mounted) return;
    await _guarded(context, () async {
      await _repo.createBook(req);
    });
  }

  @override
  Future<void> importFolder(BuildContext context) async {
    final platform = _repo.platform;
    if (platform == null) throw StateError('TxtBookRepository has no StoragePlatform');
    final ref = await platform.pickFolder();
    if (ref == null || !context.mounted) return;
    final mode = await showDialog<ImportMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Import folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImportMode.copy),
            child: const ListTile(
              title: Text('Copy into BookNotes'),
              subtitle: Text('Safe and always available. The original folder is left alone.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImportMode.link),
            child: const ListTile(
              title: Text('Use the folder where it is'),
              subtitle: Text('Edits are saved straight into that folder. '
                  'Needs permission to read and write it.'),
            ),
          ),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    await _guarded(context, () async {
      final books = await _repo.importFolder(ref, mode: mode);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(books.length == 1
              ? 'Imported "${books.first.title}"'
              : 'Imported ${books.length} books'),
        ));
      }
    });
  }

  @override
  Future<void> openBook(BuildContext context, Book book) {
    final open = _openBook;
    if (open != null) return open(context, book);
    return DemoBookshelfActions(_ref).openBook(context, book);
  }

  // ---------------------------------------------------------------- extra flows

  /// Export as a ZIP chosen via the system "save as" dialog.
  Future<void> exportBookAsZip(BuildContext context, Book book) async {
    final platform = _repo.platform!;
    final target = await platform.pickZipSaveTarget('${sanitizeFileStem(book.title)}.zip');
    if (target == null || !context.mounted) return;
    await _guarded(context, () async {
      await _repo.transfer.exportZipTo(book.id, target, overwrite: true); // OS confirmed
      if (context.mounted) _snack(context, 'Exported "${book.title}" as ZIP');
    });
  }

  /// Export as a plain folder (a new sub-folder is created; nothing is overwritten).
  Future<void> exportBookAsFolder(BuildContext context, Book book) async {
    final platform = _repo.platform!;
    final parent = await platform.pickFolder();
    if (parent == null || !context.mounted) return;
    await _guarded(context, () async {
      await _repo.transfer.exportFolder(book.id, parent);
      if (context.mounted) _snack(context, 'Exported "${book.title}" to a folder');
    });
  }

  Future<void> importZip(BuildContext context) async {
    final platform = _repo.platform!;
    final doc = await platform.pickZipToImport();
    if (doc == null || !context.mounted) return;
    await _guarded(context, () async {
      final book = await _repo.transfer.importZipFrom(doc);
      if (context.mounted) _snack(context, 'Imported "${book.title}"');
    });
  }

  /// For a linked book whose folder permission was revoked / moved: lets the
  /// user pick the folder again. Returns true when the book is reachable again.
  Future<bool> reconnectBook(BuildContext context, Book book) async {
    final platform = _repo.platform!;
    final ref = await platform.pickFolder();
    if (ref == null || !context.mounted) return false;
    var ok = false;
    await _guarded(context, () async {
      await _repo.store.relinkBook(book.id, ref);
      ok = true;
      if (context.mounted) _snack(context, 'Reconnected "${book.title}"');
    });
    return ok;
  }

  // ---------------------------------------------------------------- helpers

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guarded(BuildContext context, Future<void> Function() body) async {
    try {
      await body();
    } on StorageException catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Could not complete that'),
          content: Text(describeStorageError(e)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }
}

/// Minimal New Book form (title, subject, cover colour).
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
