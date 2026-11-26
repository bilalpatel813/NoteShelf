/// T3 - reusable reader widgets.
///
///  * [PageSheet]        one page: heading, text (editor or read-only), number
///  * [SpreadView]       one page (folded) or two pages (unfolded)
///  * [PageTurnAnimator] the seam T4 replaces to animate page turns
///  * [SlidePageTurnAnimator] simple default (slide + fade)
///  * [PageNavBar]       previous / next / page indicator / jump
///  * [SaveStatusChip]   Saved / Unsaved / Saving / Save failed
///
/// None of these touch storage. They read state from [ReaderController].
// ignore_for_file: deprecated_member_use
library;

import 'package:flutter/material.dart';

import '../../core/models/book_design.dart';
import '../../core/theme/book_visuals.dart';
import 'reader_controller.dart';
import 'reader_models.dart';

// =============================================================================
// Animation seam (T4)
// =============================================================================

/// Renders the spread whose first page is [anchor]. [interactive] is false for
/// an outgoing / incoming snapshot that must not take focus or key input.
typedef SpreadBuilder = Widget Function(
  BuildContext context,
  int anchor, {
  required bool interactive,
});

/// Everything an animator needs to show a page turn.
class PageTurnScope {
  const PageTurnScope({
    required this.anchor,
    required this.previousAnchor,
    required this.layout,
    required this.buildSpread,
    required this.canGoBack,
    required this.canGoForward,
    required this.goBack,
    required this.goForward,
    this.duration = const Duration(milliseconds: 280),
    this.gesturesEnabled = true,
    this.textSelectable = true,
  });

  /// First page of the spread that should be on screen now (1-based).
  final int anchor;

  /// Anchor shown before the last change (== [anchor] on first build).
  final int previousAnchor;
  final ReaderLayout layout;

  /// Builds any spread. Call it for outgoing and incoming spreads. All of them
  /// edit the SAME controller-owned text, so animating never copies or loses text.
  final SpreadBuilder buildSpread;
  final bool canGoBack, canGoForward;

  /// Ask the reader to move (e.g. at the end of a drag gesture). The animator
  /// should NOT change pages itself; it reacts to the new [anchor].
  final VoidCallback goBack, goForward;
  final Duration duration;

  /// False in Edit mode: animators that handle touch / mouse drags themselves
  /// must not start one (it would fight caret placement and text selection).
  final bool gesturesEnabled;

  /// Whether view-mode page text may be text-selected. [SelectionArea]'s own
  /// pan/horizontal recognizers would otherwise claim every swipe that starts
  /// on a word, so the reader turns this off while drag-to-turn is active.
  final bool textSelectable;

  /// +1 forward, -1 backward, 0 none.
  int get direction => anchor.compareTo(previousAnchor);
}

/// Replace this to change how pages turn. Implementations must be pure widgets:
/// no storage access, no text copies, no controller mutation except
/// [PageTurnScope.goBack] / [PageTurnScope.goForward].
abstract class PageTurnAnimator {
  const PageTurnAnimator();

  /// True when the animator wires up its own drag-to-turn (so the reader must
  /// not add its own swipe detector on top).
  bool get handlesGestures => false;
  Widget build(BuildContext context, PageTurnScope scope);
}

/// Default: slide + fade, keyed by anchor.
class SlidePageTurnAnimator extends PageTurnAnimator {
  const SlidePageTurnAnimator();

  @override
  Widget build(BuildContext context, PageTurnScope scope) {
    final dir = scope.direction == 0 ? 1 : scope.direction;
    return AnimatedSwitcher(
      duration: scope.duration,
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey<int>(scope.anchor);
        final from = Offset(incoming ? 0.08 * dir : -0.08 * dir, 0);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(anim),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(scope.anchor),
        child: scope.buildSpread(context, scope.anchor, interactive: true),
      ),
    );
  }
}

// =============================================================================
// Spread + page
// =============================================================================

/// Builds the visible pages for one anchor. Rebuilds when the controller changes.
class SpreadView extends StatelessWidget {
  const SpreadView({
    super.key,
    required this.controller,
    required this.anchor,
    this.interactive = true,
    this.textSelectable = true,
  });

  final ReaderController controller;
  final int anchor;
  final bool interactive;
  final bool textSelectable;

  @override
  Widget build(BuildContext context) {
    final s = SpreadMath.spreadFor(
      anchor,
      controller.pageCount,
      controller.layout,
    );
    Widget sheet(int n, {required bool left}) => Expanded(
          child: PageSheet(
            controller: controller,
            number: n,
            interactive: interactive,
            leftSide: left,
            textSelectable: textSelectable,
          ),
        );

    if (controller.layout == ReaderLayout.folded) {
      return Row(children: [sheet(s.left, left: false)]);
    }
    return Row(
      children: [
        sheet(s.left, left: true),
        Container(width: 2, color: Colors.black.withOpacity(0.18)), // gutter
        // Odd final page: the right side is an empty sheet.
        s.right == null
            ? Expanded(child: _BlankSheet(design: controller.book.cover.design))
            : sheet(s.right!, left: false),
      ],
    );
  }
}

class _BlankSheet extends StatelessWidget {
  const _BlankSheet({this.design});
  final BookDesign? design;
  @override
  Widget build(BuildContext context) => BookPageSurface(
        design: design,
        blank: true,
        child: const SizedBox.expand(),
      );
}

/// One page. Edit mode: multi-line TextField bound to the controller-owned
/// TextEditingController. View mode: selectable, read-only text with paragraph
/// spacing.
class PageSheet extends StatelessWidget {
  const PageSheet({
    super.key,
    required this.controller,
    required this.number,
    this.interactive = true,
    this.leftSide = false,
    this.textSelectable = true,
  });

  final ReaderController controller;
  final int number;
  final bool interactive;
  final bool leftSide;
  final bool textSelectable;

  @override
  Widget build(BuildContext context) {
    final b = controller.bufferFor(number);
    final scheme = Theme.of(context).colorScheme;
    if (b == null) return _BlankSheet(design: controller.book.cover.design);
    final style = controller.typography.toTextStyle(context);
    final edit = controller.isEdit && interactive;

    return BookPageSurface(
      design: controller.book.cover.design,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(
              controller: controller,
              buffer: b,
              editable: controller.isEdit && interactive,
            ),
            const Divider(height: 12),
            Expanded(child: _body(context, b, style, edit, scheme)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (controller.isEdit && interactive)
                  IconButton(
                    tooltip: 'Delete this page',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _confirmDelete(context),
                  ),
                const Spacer(),
                Text(
                  '${b.number}', // page number display
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                if (controller.isEdit && interactive) const SizedBox(width: 40),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PageBuffer b,
    TextStyle style,
    bool edit,
    ColorScheme scheme,
  ) {
    if (!b.loaded) {
      if (b.error != null) {
        return _LoadFailed(
          error: b.error!,
          onRetry: () => controller.reloadPage(number),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (edit) {
      return TextField(
        controller: b.text,
        // Stable key per page id: the field keeps focus/caret across rebuilds.
        key: ValueKey('editor-${b.id}'),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textAlign: controller.typography.align,
        style: style,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: 'Start writing…',
        ),
      );
    }
    return _ReadOnlyText(
      text: b.text.text,
      style: style,
      align: controller.typography.align,
      paragraphSpacing: controller.typography.paragraphSpacing,
      selectable: textSelectable,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete page $number?'),
        content: const Text(
          'The page and its text file will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.deletePage(number);
  }
}

/// Read-only rendering. Each line of the TXT is one paragraph; the extra
/// spacing is drawn between them and never written into the text.
class _ReadOnlyText extends StatelessWidget {
  const _ReadOnlyText({
    required this.text,
    required this.style,
    required this.align,
    required this.paragraphSpacing,
    this.selectable = true,
  });

  final String text;
  final TextStyle style;
  final TextAlign align;
  final double paragraphSpacing;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'This page is empty.',
          style: style.copyWith(
            fontStyle: FontStyle.italic,
            color: style.color?.withOpacity(0.5),
          ),
        ),
      );
    }
    final paragraphs = text.replaceAll('\r\n', '\n').split('\n');
    final list = ListView.builder(
      itemCount: paragraphs.length,
      itemBuilder: (_, i) => Padding(
        padding: EdgeInsets.only(bottom: paragraphSpacing),
        // An empty line still takes one line of height, like in the editor.
        child: Text(
          paragraphs[i].isEmpty ? ' ' : paragraphs[i],
          style: style,
          textAlign: align,
        ),
      ),
    );
    // SelectionArea's pan / horizontal recognizers claim swipes that start on
    // a word, which would stop the page from turning; skip it while the
    // animator owns drags (see PageTurnScope.textSelectable).
    return selectable ? SelectionArea(child: list) : list;
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.controller,
    required this.buffer,
    required this.editable,
  });
  final ReaderController controller;
  final PageBuffer buffer;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleMedium;
    final label = Text(
      buffer.heading,
      style: t,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!editable) return Align(alignment: Alignment.centerLeft, child: label);
    return InkWell(
      onTap: () => _rename(context),
      child: Row(
        children: [
          Expanded(child: label),
          const Icon(Icons.edit_outlined, size: 16),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final c = TextEditingController(text: buffer.heading);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Page heading'),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: const InputDecoration(labelText: 'Heading'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    c.dispose();
    if (value != null) await controller.renameHeading(buffer.number, value);
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(height: 8),
            const Text('This page could not be loaded.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
}

// =============================================================================
// Navigation + status
// =============================================================================

class PageNavBar extends StatelessWidget {
  const PageNavBar({super.key, required this.controller});
  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final label = SpreadMath.label(controller.spread, controller.pageCount);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous (Alt+Left)',
          icon: const Icon(Icons.chevron_left),
          onPressed: controller.canGoBack ? controller.previous : null,
        ),
        TextButton(onPressed: () => _jump(context), child: Text(label)),
        IconButton(
          tooltip: 'Next (Alt+Right)',
          icon: const Icon(Icons.chevron_right),
          onPressed: controller.canGoForward ? controller.next : null,
        ),
        if (controller.isEdit)
          IconButton(
            tooltip: 'Add page',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: controller.addPage,
          ),
      ],
    );
  }

  Future<void> _jump(BuildContext context) async {
    final c = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s)),
          decoration: InputDecoration(hintText: '1 – ${controller.pageCount}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v != null) await controller.goTo(v);
  }
}

class SaveStatusChip extends StatelessWidget {
  const SaveStatusChip({super.key, required this.controller});
  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (controller.overallStatus) {
      SaveStatus.saved => (Icons.check_circle_outline, 'Saved'),
      SaveStatus.dirty => (Icons.circle_outlined, 'Unsaved changes'),
      SaveStatus.saving => (Icons.sync, 'Saving…'),
      SaveStatus.error => (Icons.error_outline, 'Save failed'),
    };
    final isError = controller.overallStatus == SaveStatus.error;
    final color = isError ? Theme.of(context).colorScheme.error : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style:
              Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
