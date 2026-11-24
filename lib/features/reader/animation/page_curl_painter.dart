/// T4 - painting for the page curl: cast shadow, fold shading, paper back.
///
/// Two painters bracket the flap in the stack:
///   [CurlShadowPainter]  below the flap: shadow it casts, spine + fold shadow
///   [CurlFlapPainter]    above the flap: paper back (folded layout), crease
///                        and highlight that suggest the paper bending
/// Paints and static shaders live in [CurlPaints], owned by the animator's
/// State, so a frame allocates little beyond its own paths.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'page_curl_geometry.dart';

/// Clips to a precomputed path. Reclips when the path changes.
class PathClipper extends CustomClipper<Path> {
  const PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(PathClipper old) => !identical(old.path, path);
}

/// Reusable paints + shaders, rebuilt only when the page width changes.
class CurlPaints {
  double _width = -1;
  late Paint shadowBlur;
  late Paint foldShadow; // gradient, local x = away from hinge (revealed side)
  late Paint flapBand; // gradient, local x = into the flap
  late double band;
  final Paint paper = Paint();
  final Paint edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8
    ..color = const Color(0x1F000000);

  void ensure(double pageWidth) {
    if (pageWidth == _width) return;
    _width = pageWidth;
    band = math.max(24.0, math.min(pageWidth * 0.22, 170.0));
    shadowBlur = Paint()
      ..color = const Color(0x59000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    foldShadow = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(band * 0.7, 0), const [
        Color(0x40000000),
        Color(0x00000000),
      ]);
    flapBand = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(band, 0),
        const [Color(0x4D000000), Color(0x59FFFFFF), Color(0x00FFFFFF)],
        const [0.0, 0.28, 1.0],
      );
  }
}

class CurlShadowPainter extends CustomPainter {
  CurlShadowPainter({required this.frame, required this.paints});

  final CurlFrame frame;
  final CurlPaints paints;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isStart || frame.isEnd) return;
    paints.ensure(frame.region.width);
    canvas.save();
    canvas.clipRect(frame.bounds);

    // 1. Shadow of the flap on the page it lies over (hinge side only).
    canvas.save();
    canvas.clipPath(frame.hingeSidePath);
    canvas.drawPath(
      frame.flapPath.shift(const Offset(3, 5)),
      paints.shadowBlur,
    );
    canvas.restore();

    // 2. Soft shadow where the revealed page meets the lifted fold.
    canvas.save();
    canvas.clipPath(frame.revealedPath);
    final mid = frame.foldMid;
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(math.atan2(frame.normal.dy, frame.normal.dx));
    final h = frame.size.height * 2;
    canvas.drawRect(
      Rect.fromLTRB(0, -h, paints.band * 0.7, h),
      paints.foldShadow,
    );
    canvas.restore();

    // 3. Two-page mode: the binding darkens while the page passes over it.
    if (frame.unfolded) {
      final a = (0.16 * math.sin(math.pi * frame.progress)).clamp(0.0, 1.0);
      final w = frame.region.width * 0.05;
      final spine = Paint()
        ..shader = ui.Gradient.linear(
          Offset(frame.hingeX - w, 0),
          Offset(frame.hingeX + w, 0),
          [
            const Color(0x00000000),
            Color.fromRGBO(0, 0, 0, a),
            const Color(0x00000000),
          ],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawRect(
        Rect.fromLTRB(frame.hingeX - w, 0, frame.hingeX + w, frame.size.height),
        spine,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CurlShadowPainter old) =>
      old.frame.progress != frame.progress ||
      old.frame.direction != frame.direction ||
      old.frame.size != frame.size;
}

class CurlFlapPainter extends CustomPainter {
  CurlFlapPainter({
    required this.frame,
    required this.paints,
    required this.paperBack,
  });

  final CurlFrame frame;
  final CurlPaints paints;

  /// Colour of the paper's back. Folded layout paints it; two-page layout draws
  /// the incoming page under this painter instead, so it is only an overlay.
  final Color? paperBack;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isStart || frame.isEnd) return;
    paints.ensure(frame.region.width);
    canvas.save();
    canvas.clipRect(frame.bounds);
    canvas.clipPath(frame.flapPath);

    if (paperBack != null) {
      canvas.drawPath(frame.flapPath, paints.paper..color = paperBack!);
    }

    // Crease at the fold, then a highlight, fading across the flap: reads as
    // paper bending around the fold line.
    canvas.save();
    final mid = frame.foldMid;
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(math.atan2(-frame.normal.dy, -frame.normal.dx));
    final h = frame.size.height * 2;
    canvas.drawRect(Rect.fromLTRB(0, -h, paints.band, h), paints.flapBand);
    canvas.restore();

    canvas.drawPath(frame.flapPath, paints.edge);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CurlFlapPainter old) =>
      old.frame.progress != frame.progress ||
      old.frame.direction != frame.direction ||
      old.frame.size != frame.size ||
      old.paperBack != paperBack;
}
