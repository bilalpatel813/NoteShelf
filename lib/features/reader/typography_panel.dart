/// T3 - font / typography picker. Changes are presentation only and are saved
/// per book via ReaderController.setTypography -> BookStore.setFontSettings.
library;

import 'package:flutter/material.dart';

import 'reader_controller.dart';
import 'reader_models.dart';

Future<void> showTypographySheet(
  BuildContext context,
  ReaderController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    child: SingleChildScrollView(
      child: TypographyPanel(controller: controller),
    ),
  ),
);

class TypographyPanel extends StatelessWidget {
  const TypographyPanel({super.key, required this.controller});
  final ReaderController controller;

  static const _swatches = <Color>[
    Color(0xFF000000),
    Color(0xFF3E2C1C),
    Color(0xFF1F3A5F),
    Color(0xFF2F4A2A),
    Color(0xFFE9D9B8),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.typography;
        void set(TypographySettings n) => controller.setTypography(n);

        Widget row(String label, Widget child) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 120, child: Text(label)),
              Expanded(child: child),
            ],
          ),
        );

        Widget slider(
          double v,
          double min,
          double max,
          int? div,
          String shown,
          ValueChanged<double> on,
        ) => Row(
          children: [
            Expanded(
              child: Slider(
                value: v.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: div,
                onChanged: on,
              ),
            ),
            SizedBox(width: 44, child: Text(shown, textAlign: TextAlign.end)),
          ],
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(
                'Font',
                DropdownButton<String>(
                  isExpanded: true,
                  value: readerFontFamilies.contains(t.family)
                      ? t.family
                      : null,
                  items: [
                    for (final f in readerFontFamilies)
                      DropdownMenuItem(
                        value: f,
                        child: Text(f, style: TextStyle(fontFamily: f)),
                      ),
                  ],
                  onChanged: (v) =>
                      v == null ? null : set(t.copyWith(family: v)),
                ),
              ),
              row(
                'Size',
                slider(
                  t.size,
                  TypographySettings.minSize,
                  TypographySettings.maxSize,
                  30,
                  t.size.toStringAsFixed(0),
                  (v) => set(t.copyWith(size: v)),
                ),
              ),
              row(
                'Weight',
                slider(
                  t.weight.toDouble(),
                  100,
                  900,
                  8,
                  '${t.weight}',
                  (v) => set(t.copyWith(weight: (v / 100).round() * 100)),
                ),
              ),
              row(
                'Line height',
                slider(
                  t.lineHeight,
                  TypographySettings.minLineHeight,
                  TypographySettings.maxLineHeight,
                  15,
                  t.lineHeight.toStringAsFixed(1),
                  (v) => set(t.copyWith(lineHeight: (v * 10).round() / 10)),
                ),
              ),
              row(
                'Paragraph gap',
                slider(
                  t.paragraphSpacing,
                  0,
                  TypographySettings.maxParagraphSpacing,
                  16,
                  t.paragraphSpacing.toStringAsFixed(0),
                  (v) => set(t.copyWith(paragraphSpacing: v)),
                ),
              ),
              row(
                'Align',
                SegmentedButton<TextAlign>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: TextAlign.left,
                      icon: Icon(Icons.format_align_left),
                      tooltip: 'Left',
                    ),
                    ButtonSegment(
                      value: TextAlign.center,
                      icon: Icon(Icons.format_align_center),
                      tooltip: 'Center',
                    ),
                    ButtonSegment(
                      value: TextAlign.right,
                      icon: Icon(Icons.format_align_right),
                      tooltip: 'Right',
                    ),
                    ButtonSegment(
                      value: TextAlign.justify,
                      icon: Icon(Icons.format_align_justify),
                      tooltip: 'Justify',
                    ),
                  ],
                  selected: {t.align},
                  onSelectionChanged: (s) => set(t.copyWith(align: s.first)),
                ),
              ),
              row(
                'Text colour',
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Auto'),
                      selected: t.color == null,
                      onSelected: (_) => set(t.copyWith(clearColor: true)),
                    ),
                    for (final c in _swatches)
                      GestureDetector(
                        onTap: () => set(t.copyWith(color: c)),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: c,
                          child: t.color == c
                              ? Icon(
                                  Icons.check,
                                  size: 16,
                                  color: c.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Applies to this book only. Your text is never changed by these settings. '
                'In Edit mode paragraph gap is not shown (it appears in View mode).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
