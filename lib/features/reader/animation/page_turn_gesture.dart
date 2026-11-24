/// T4 - drag-to-turn rules. Pure functions so they can be unit-tested; the
/// animator owns the GestureDetector and the state.
library;

import 'dart:ui' show Offset, PointerDeviceKind, Size;

class PageTurnDrag {
  const PageTurnDrag._();

  /// Fraction of the width, measured from each side, where a MOUSE drag may
  /// begin. Elsewhere a mouse drag selects text. Touch may begin anywhere.
  static const mouseEdgeZone = 0.22;

  /// Minimum fling speed (logical px/s) that decides a turn on its own.
  static const flingVelocity = 700.0;

  static bool mayStart({
    required Offset local,
    required Size size,
    required PointerDeviceKind? kind,
  }) {
    if (kind != PointerDeviceKind.mouse) return true;
    final zone = size.width * mouseEdgeZone;
    return local.dx <= zone || local.dx >= size.width - zone;
  }

  /// Dragging left turns forward (+1), dragging right turns back (-1).
  static int directionFor(double dx) => dx < 0 ? 1 : -1;

  /// Change in turn progress for a horizontal movement [dx] in [direction].
  static double progressDelta(double dx, int direction, double pageWidth) =>
      pageWidth <= 0 ? 0 : (-direction * dx) / pageWidth;

  /// Decide on release. [velocityX] is the raw horizontal velocity.
  static bool shouldCommit({
    required double progress,
    required double velocityX,
    required int direction,
  }) {
    final along = -direction * velocityX; // > 0: moving the way the page turns
    if (along >= flingVelocity) return progress > 0.02;
    if (along <= -flingVelocity) return false; // flicked back: cancel
    return progress >= 0.5;
  }
}
