/// T4 - page turn animators for the T3 reader.
///
///  * [CurlPageTurnAnimator]  realistic curl (default)
///  * [FlipPageTurnAnimator]  simpler flip about the binding
///  * SlidePageTurnAnimator   T3's original slide + fade, kept as the fallback
///
/// All implement T3's [PageTurnAnimator] seam. They never change pages
/// themselves: a finished drag calls [PageTurnScope.goForward] /
/// [PageTurnScope.goBack] and the animation reacts to the new
/// [PageTurnScope.anchor]. Pages are built only with [PageTurnScope.buildSpread].
///
/// One state machine ([PageTurnEngine]) runs at most one transition at a time:
///   idle -> dragging -> committing -> running -> idle   (drag to turn)
///   idle -> running -> idle                             (button / key / jump)
/// A new anchor while running either reverses the turn (back to where it came
/// from) or snaps the running turn to its end and starts the next one.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../reader_models.dart' show ReaderLayout, SpreadMath;
import '../reader_widgets.dart';
import 'page_curl_geometry.dart';
import 'page_curl_painter.dart';
import 'page_flip_animator.dart';
import 'page_turn_gesture.dart';

enum PageTurnStyle { curl, flip, slide }

extension PageTurnStyleX on PageTurnStyle {
  String get label => switch (this) {
    PageTurnStyle.curl => 'Page curl',
    PageTurnStyle.flip => 'Page flip',
    PageTurnStyle.slide => 'Slide',
  };
}

/// The style the reader uses unless told otherwise.
const kDefaultPageTurnStyle = PageTurnStyle.curl;

PageTurnAnimator animatorForStyle(PageTurnStyle style) => switch (style) {
  PageTurnStyle.curl => const CurlPageTurnAnimator(),
  PageTurnStyle.flip => const FlipPageTurnAnimator(),
  PageTurnStyle.slide => const SlidePageTurnAnimator(),
};

/// Key of the frame that exists only while a turn is in progress (test hook).
const pageTurnFrameKey = ValueKey<String>('page-turn-frame');

class CurlPageTurnAnimator extends PageTurnAnimator {
  const CurlPageTurnAnimator({this.tilt = 0.10});

  /// Mid-turn slant of the fold, as a fraction of page height.
  final double tilt;

  @override
  bool get handlesGestures => true;

  @override
  Widget build(BuildContext context, PageTurnScope scope) =>
      PageTurnEngine(scope: scope, kind: PageTurnKind.curl, tilt: tilt);
}

class FlipPageTurnAnimator extends PageTurnAnimator {
  const FlipPageTurnAnimator();

  @override
  bool get handlesGestures => true;

  @override
  Widget build(BuildContext context, PageTurnScope scope) =>
      PageTurnEngine(scope: scope, kind: PageTurnKind.flip);
}

enum PageTurnKind { curl, flip }

enum _Phase { idle, dragging, committing, running }

enum _Mode { curl, flip, fade }

class PageTurnEngine extends StatefulWidget {
  const PageTurnEngine({
    super.key,
    required this.scope,
    required this.kind,
    this.tilt = 0.10,
  });

  final PageTurnScope scope;
  final PageTurnKind kind;
  final double tilt;

  @override
  State<PageTurnEngine> createState() => _PageTurnEngineState();
}

class _PageTurnEngineState extends State<PageTurnEngine>
    with SingleTickerProviderStateMixin {
  // Progress of the turn, 0..1. While dragging it follows the finger.
  late final AnimationController _c = AnimationController(vsync: this);
  final CurlPaints _paints = CurlPaints();

  _Phase _phase = _Phase.idle;
  _Mode _mode = _Mode.curl;
  int _from = 0, _to = 0, _dir = 1;
  bool _reversing = false; // running back toward _from
  int _logicalAnchor = 0; // last anchor seen from the scope
  Widget? _out, _in; // retained outgoing / incoming spreads
  int _token = 0; // invalidates completions of cancelled runs
  Timer? _commitTimer;
  Size _size = Size.zero;
  bool _reduce = false;

  // Drag
  bool _dragLive = false, _dragIgnored = true;
  int _dragDir = 0;
  double _dragTotal = 0;

  @override
  void initState() {
    super.initState();
    _logicalAnchor = widget.scope.anchor;
  }

  @override
  void dispose() {
    _token++;
    _commitTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- scope changes

  @override
  void didUpdateWidget(PageTurnEngine old) {
    super.didUpdateWidget(old);
    final s = widget.scope;
    if (s.layout != old.scope.layout) {
      // Fold / unfold re-lays the whole book out: no animation.
      _settle();
      _logicalAnchor = s.anchor;
      return;
    }
    if (!s.gesturesEnabled && _phase == _Phase.dragging) _cancelDrag();
    if (s.anchor != _logicalAnchor) {
      final prev = _logicalAnchor;
      _logicalAnchor = s.anchor;
      _onAnchorChanged(prev, s.anchor);
    }
  }

  void _onAnchorChanged(int prev, int next) {
    if (_phase == _Phase.committing && next == _to) {
      _commitTimer?.cancel();
      _runTo(1, _scaled(1 - _c.value), Curves.easeOut);
      return;
    }
    var shown = prev;
    if (_phase == _Phase.running) {
      if (!_reversing && next == _from) {
        _reversing = true; // direction change: turn back where it came from
        _runTo(0, _scaled(_c.value), Curves.easeOut);
        return;
      }
      if (_reversing && next == _to) {
        _reversing = false;
        _runTo(1, _scaled(1 - _c.value), Curves.easeOut);
        return;
      }
      shown = _reversing ? _from : _to; // what the snapped turn ends on
    }
    if (_phase != _Phase.idle) _settle(); // snap: never two turns at once
    if (shown == next) return;
    _start(shown, next);
  }

  // ------------------------------------------------------------------ transitions

  Duration get _fullDuration {
    if (_mode == _Mode.fade) return const Duration(milliseconds: 120);
    final f = widget.kind == PageTurnKind.curl ? 1.6 : 1.4;
    return widget.scope.duration * f;
  }

  Duration _scaled(double fraction) =>
      _fullDuration * fraction.clamp(0.0, 1.0).toDouble();

  Widget _retain(int anchor) => RepaintBoundary(
    child: widget.scope.buildSpread(context, anchor, interactive: false),
  );

  void _setMode() => _mode = _reduce
      ? _Mode.fade
      : (widget.kind == PageTurnKind.curl ? _Mode.curl : _Mode.flip);

  void _start(int from, int to) {
    if (widget.scope.duration == Duration.zero ||
        !_size.isFinite ||
        _size.isEmpty)
      return;
    _setMode();
    _from = from;
    _to = to;
    _dir = to > from ? 1 : -1;
    _reversing = false;
    _out = _retain(from);
    _in = _retain(to);
    _c.value = 0;
    _runTo(
      1,
      _fullDuration,
      _mode == _Mode.fade ? Curves.linear : Curves.easeInOutCubic,
    );
  }

  void _runTo(double target, Duration d, Curve curve) {
    final token = ++_token;
    _phase = _Phase.running;
    unawaited(
      _c.animateTo(target, duration: d, curve: curve).whenComplete(() {
        if (!mounted || token != _token) return;
        _settle(rebuild: true);
      }),
    );
  }

  void _settle({bool rebuild = false}) {
    _token++;
    _commitTimer?.cancel();
    _commitTimer = null;
    _c.stop();
    _phase = _Phase.idle;
    _reversing = false;
    _dragLive = false;
    _out = _in = null;
    if (rebuild && mounted) setState(() {});
  }

  // ---------------------------------------------------------------------- drag

  double _regionWidth(int dir) => PageCurlGeometry.regionFor(
    _size,
    unfolded: widget.scope.layout == ReaderLayout.unfolded,
    direction: dir,
  ).width;

  void _onDragStart(DragStartDetails d) {
    _dragLive = false;
    _dragDir = 0;
    _dragTotal = 0;
    _dragIgnored =
        !widget.scope.gesturesEnabled ||
        _phase != _Phase.idle || // never start a second turn
        !PageTurnDrag.mayStart(
          local: d.localPosition,
          size: _size,
          kind: d.kind,
        );
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dragIgnored) return;
    final dx = d.primaryDelta ?? d.delta.dx;
    _dragTotal += dx;
    if (_reduce) return; // reduced motion: swipe only, decided on release
    if (!_dragLive) {
      if (dx == 0) return;
      final dir = PageTurnDrag.directionFor(dx);
      final s = widget.scope;
      if (dir > 0 ? !s.canGoForward : !s.canGoBack) {
        _dragIgnored = true;
        return;
      }
      _beginDrag(dir);
    }
    final p = PageTurnDrag.progressDelta(dx, _dragDir, _regionWidth(_dragDir));
    _c.value = (_c.value + p).clamp(0.0, 1.0).toDouble();
  }

  void _beginDrag(int dir) {
    final s = widget.scope;
    _setMode();
    _from = s.anchor;
    _to = s.anchor + dir * SpreadMath.step(s.layout);
    _dir = dir;
    _dragDir = dir;
    _reversing = false;
    _out = _retain(_from);
    _in = _retain(_to);
    _c.stop();
    _c.value = 0;
    _phase = _Phase.dragging;
    _dragLive = true;
    setState(() {});
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragIgnored) return;
    final v = d.primaryVelocity ?? 0;
    final s = widget.scope;
    if (_reduce || !_dragLive) {
      if (_dragTotal == 0) return;
      // Plain swipe (reduced motion): the reader moves, the fade follows.
      final dir = PageTurnDrag.directionFor(_dragTotal);
      final enough =
          _dragTotal.abs() > 40 || v.abs() >= PageTurnDrag.flingVelocity;
      if (enough && _phase == _Phase.idle && s.gesturesEnabled) {
        if (dir > 0 && s.canGoForward) s.goForward();
        if (dir < 0 && s.canGoBack) s.goBack();
      }
      return;
    }
    _dragLive = false;
    if (PageTurnDrag.shouldCommit(
      progress: _c.value,
      velocityX: v,
      direction: _dragDir,
    )) {
      _commit();
    } else {
      _cancelDrag();
    }
  }

  void _onDragCancel() {
    if (_dragLive && _phase == _Phase.dragging) _cancelDrag();
  }

  /// Ask the reader to move, then finish the curl once the new anchor arrives.
  void _commit() {
    _phase = _Phase.committing;
    // If the reader never answers (e.g. a load stalls), fall back to un-turning.
    _commitTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _phase == _Phase.committing) _cancelDrag();
    });
    final s = widget.scope;
    if (_dragDir > 0) {
      s.goForward();
    } else {
      s.goBack();
    }
  }

  void _cancelDrag() {
    _commitTimer?.cancel();
    _dragLive = false;
    _reversing = true;
    _runTo(0, _scaled(_c.value), Curves.easeOut);
  }

  // --------------------------------------------------------------------- build

  Color _paperBack(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF241F1B)
      : const Color(0xFFF1E8D0);

  @override
  Widget build(BuildContext context) {
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final s = widget.scope;
    Widget body = LayoutBuilder(
      builder: (ctx, constraints) {
        final size = constraints.biggest;
        _size = size;
        if (_phase == _Phase.idle ||
            !size.isFinite ||
            _out == null ||
            _in == null) {
          return s.buildSpread(ctx, s.anchor, interactive: true);
        }
        return IgnorePointer(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: AnimatedBuilder(
              animation: _c,
              builder: (ctx2, _) => KeyedSubtree(
                key: pageTurnFrameKey,
                child: _frame(ctx2, size, _c.value),
              ),
            ),
          ),
        );
      },
    );
    if (s.gesturesEnabled) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: body,
      );
    }
    return body;
  }

  Widget _frame(BuildContext context, Size size, double t) {
    final unfolded = widget.scope.layout == ReaderLayout.unfolded;
    switch (_mode) {
      case _Mode.fade:
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _out!),
            Positioned.fill(
              child: Opacity(
                opacity: t.clamp(0.0, 1.0).toDouble(),
                child: _in!,
              ),
            ),
          ],
        );
      case _Mode.flip:
        return buildFlipFrame(
          size: size,
          unfolded: unfolded,
          direction: _dir,
          progress: t,
          outgoing: _out!,
          incoming: _in!,
        );
      case _Mode.curl:
        final f = PageCurlGeometry.compute(
          size: size,
          unfolded: unfolded,
          direction: _dir,
          progress: t,
          tilt: widget.tilt,
        );
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // Under everything: the incoming spread (revealed beyond the fold).
            Positioned.fill(child: _in!),
            // Outgoing spread, only where it has not been turned over yet. In
            // two-page mode that includes the stationary page.
            Positioned.fill(
              child: ClipPath(
                clipper: PathClipper(f.hingeSidePath),
                child: _out!,
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: CurlShadowPainter(frame: f, paints: _paints),
              ),
            ),
            // Flap. Two-page: its back is the incoming spread's page beside the
            // binding, moved into place by [CurlFrame.back]. Folded: paper only.
            if (unfolded)
              Positioned.fill(
                child: ClipPath(
                  clipper: PathClipper(f.flapPath),
                  child: Transform(
                    transform: Matrix4.fromList(f.back.toColumnMajor4()),
                    child: _in!,
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            Positioned.fill(
              child: CustomPaint(
                painter: CurlFlapPainter(
                  frame: f,
                  paints: _paints,
                  paperBack: unfolded ? null : _paperBack(context),
                ),
              ),
            ),
          ],
        );
    }
  }
}
