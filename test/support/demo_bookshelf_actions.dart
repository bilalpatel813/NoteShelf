// Test-only stand-in for the real bookshelf actions (never used in production).
import 'package:booknotes/core/contracts/contracts.dart';
import 'package:booknotes/core/models/book.dart';
import 'package:booknotes/features/bookshelf/bookshelf_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DemoBookshelfActions implements BookshelfActions {
  DemoBookshelfActions(this._ref);
  final Ref _ref;

  @override
  Future<void> newBook(BuildContext context) async {
    final req = await showDialog<NewBookRequest>(
      context: context,
      builder: (_) => const _NewBookDialog(),
    );
    if (req != null) await _ref.read(bookRepositoryProvider).createBook(req);
  }

  @override
  Future<void> importFolder(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Folder'),
        content: const Text(
          'Integration point for T2: pick a folder, then call '
          'BookRepository.importFolder(path).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> openBook(BuildContext context, Book book) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reader integration point (T3): would open "${book.title}" '
          'at page ${book.lastOpenedPage}.',
        ),
      ),
    );
    await _ref.read(bookRepositoryProvider).markOpened(book.id);
  }
}

class _NewBookDialog extends StatefulWidget {
  const _NewBookDialog();
  @override
  State<_NewBookDialog> createState() => _NewBookDialogState();
}

class _NewBookDialogState extends State<_NewBookDialog> {
  static const _colors = [
    0xFF7A2E2E,
    0xFF1F3A5F,
    0xFF2F4A2A,
    0xFF5B2A63,
    0xFF5A4630,
    0xFF0F5D5A,
  ];
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
      NewBookRequest(
        title: t,
        subject: s.isEmpty ? 'General' : s,
        coverColorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Book'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Wrap(
              spacing: 10,
              children: [
                for (final c in _colors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(c),
                      child: _color == c
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create book')),
      ],
    );
  }
}
