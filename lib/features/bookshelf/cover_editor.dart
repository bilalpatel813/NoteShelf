import 'package:flutter/material.dart';

import '../../core/models/book.dart';
import '../../core/models/book_design.dart';
import 'book_card.dart';

/// Returns a draft only on Save; the caller owns persistence and error handling.
class CoverEditor extends StatefulWidget {
  const CoverEditor({super.key, required this.book, this.pickImage});
  final Book book;
  final Future<String?> Function()? pickImage;

  @override
  State<CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends State<CoverEditor> {
  late final TextEditingController title, subtitle, author;
  late BookDesign design;
  late int color;
  String? image;
  String? error;

  static const colors = <int, String>{
    0xFF7A2E2E: 'Burgundy',
    0xFF344A38: 'Forest green',
    0xFF344D70: 'Blue',
    0xFF684B70: 'Purple',
    0xFFB66B76: 'Rose',
    0xFF8A633E: 'Brown',
    0xFF313C44: 'Slate',
    0xFFE6D4AF: 'Cream',
  };

  @override
  void initState() {
    super.initState();
    design = widget.book.cover.design ?? BookDesign.preset(BookTheme.basic);
    title = TextEditingController(text: widget.book.title);
    subtitle = TextEditingController(
      text: widget.book.cover.design?.subtitle ?? widget.book.subject,
    );
    author = TextEditingController(text: design.author);
    color = widget.book.cover.colorValue;
    image = widget.book.cover.imagePath;
  }

  @override
  void dispose() {
    title.dispose();
    subtitle.dispose();
    author.dispose();
    super.dispose();
  }

  Book get draft => widget.book.copyWith(
        title:
            title.text.trim().isEmpty ? widget.book.title : title.text.trim(),
        cover: BookCoverRef(
          imagePath: image,
          colorValue: color,
          design: design.copyWith(
            subtitle: subtitle.text.trim(),
            author: author.text.trim(),
          ),
        ),
      );

  Future<void> chooseImage() async {
    try {
      final picked = await widget.pickImage!();
      if (mounted && picked != null) setState(() => image = picked);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not choose artwork: $e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Customize cover'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: SizedBox(
                    width: 120,
                    height: 180,
                    child: BookCoverView(book: draft, width: 120),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  decoration:
                      InputDecoration(labelText: 'Title', errorText: error),
                  onChanged: (_) => setState(() => error = null),
                ),
                TextField(
                  controller: subtitle,
                  decoration: const InputDecoration(labelText: 'Subtitle'),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: author,
                  decoration: const InputDecoration(labelText: 'Author'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BookTheme>(
                  value: design.theme,
                  decoration: const InputDecoration(labelText: 'Theme'),
                  items: [
                    for (final item in BookTheme.values)
                      DropdownMenuItem(
                          value: item, child: Text(_label(item.name))),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      design = BookDesign.preset(value).copyWith(
                          subtitle: subtitle.text, author: author.text);
                      color = switch (value) {
                        BookTheme.basic => 0xFF7A2E2E,
                        BookTheme.medieval => 0xFF68432F,
                        BookTheme.minecraft => 0xFF795237,
                        BookTheme.diary => 0xFFB66B76,
                        BookTheme.pixelated => 0xFF344D70,
                      };
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text('Cover color',
                    style: Theme.of(context).textTheme.labelLarge),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final value in colors.keys)
                      IconButton(
                        tooltip:
                            '${colors[value]}${color == value ? ', selected' : ''}',
                        onPressed: () => setState(() => color = value),
                        icon: Icon(
                          color == value ? Icons.check_circle : Icons.circle,
                          color: Color(value),
                        ),
                      ),
                  ],
                ),
                DropdownButtonFormField<CoverIcon>(
                  value: design.icon,
                  decoration: const InputDecoration(labelText: 'Icon'),
                  items: [
                    for (final item in CoverIcon.values)
                      DropdownMenuItem(
                          value: item, child: Text(_label(item.name))),
                  ],
                  onChanged: (v) {
                    if (v != null)
                      setState(() => design = design.copyWith(icon: v));
                  },
                ),
                DropdownButtonFormField<CoverDecoration>(
                  value: design.decoration,
                  decoration: const InputDecoration(
                    labelText: 'Border / decoration',
                  ),
                  items: [
                    for (final item in CoverDecoration.values)
                      DropdownMenuItem(
                          value: item, child: Text(_label(item.name))),
                  ],
                  onChanged: (v) {
                    if (v != null)
                      setState(() => design = design.copyWith(decoration: v));
                  },
                ),
                DropdownButtonFormField<BookTexture>(
                  value: design.texture,
                  decoration: const InputDecoration(labelText: 'Texture'),
                  items: [
                    for (final item in BookTexture.values)
                      DropdownMenuItem(
                          value: item, child: Text(_label(item.name))),
                  ],
                  onChanged: (v) {
                    if (v != null)
                      setState(() => design = design.copyWith(texture: v));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Decorative bookmark'),
                  value: design.bookmark,
                  onChanged: (v) =>
                      setState(() => design = design.copyWith(bookmark: v)),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (widget.pickImage != null)
                      OutlinedButton.icon(
                        onPressed: chooseImage,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Choose artwork'),
                      ),
                    if (image != null)
                      TextButton(
                        onPressed: () => setState(() => image = null),
                        child: const Text('Use generated cover'),
                      ),
                  ],
                ),
                if (image != null)
                  const Text(
                    'Artwork replaces the generated cover. Other choices still apply to pages.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                setState(() => error = 'A title is required');
                return;
              }
              Navigator.pop(context, draft);
            },
            child: const Text('Save'),
          ),
        ],
      );
}

String _label(String name) => '${name[0].toUpperCase()}${name.substring(1)}';
