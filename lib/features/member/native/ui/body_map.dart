import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_drawing/path_drawing.dart';

import '../domain/rows.dart';
import 'theme.dart';

class _View {
  _View(this.box, this.muscles, this.inert);
  final Rect box;
  final Map<String, List<Path>> muscles;
  final List<Path> inert;
}

/// openGym's body outlines (assets/member/body.json), parsed once.
class BodyGeometry {
  BodyGeometry._(this._views);
  final Map<String, _View> _views;
  static final Map<String, BodyGeometry> _cache = {};

  /// The male or female outline ("Body diagram" in Settings → Look & Home), parsed once each.
  static Future<BodyGeometry> load([String body = 'male']) async {
    final key = body == 'female' ? 'female' : 'male';
    final hit = _cache[key];
    if (hit != null) return hit;
    return _cache[key] = parse(await rootBundle.loadString('assets/member/body.json'), key);
  }

  static BodyGeometry parse(String raw, [String body = 'male']) {
    final j = asMap(jsonDecode(raw));
    final inert = {for (final s in (j['inert'] as List? ?? const [])) '$s'};
    final g = asMap(j[body] ?? j['male']);
    final views = <String, _View>{};
    for (final side in ['front', 'back']) {
      final v = asMap(g[side]);
      final vb = '${v['vb']}'.split(RegExp(r'[ ,]+')).map(double.parse).toList();
      final muscles = <String, List<Path>>{};
      final sil = <Path>[];
      asMap(v['p']).forEach((slug, ds) {
        final paths = [for (final d in (ds as List)) parseSvgPathData('$d')];
        (inert.contains(slug) ? sil : (muscles[slug] = <Path>[])).addAll(paths);
      });
      views[side] = _View(Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]), muscles, sil);
    }
    return BodyGeometry._(views);
  }

  /// A point inside [slug] on [side], for tests and accessibility actions.
  Offset? pointInside(String side, String slug) {
    for (final path in _views[side]!.muscles[slug] ?? const <Path>[]) {
      final b = path.getBounds();
      for (var y = b.top; y < b.bottom; y += b.height / 40) {
        for (var x = b.left; x < b.right; x += b.width / 40) {
          if (path.contains(Offset(x, y)) && hit(side, Offset(x, y)) == slug) return Offset(x, y);
        }
      }
    }
    return null;
  }

  Rect boxOf(String side) => _views[side]!.box;

  /// The muscle under [p] (in the view's own coordinates), or null.
  String? hit(String side, Offset p) {
    final v = _views[side]!;
    for (final e in v.muscles.entries) {
      for (final path in e.value) {
        if (path.contains(p)) return e.key;
      }
    }
    return null;
  }
}

/// Front and back views; tap a muscle to toggle it.
class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.geometry, required this.selected, required this.onToggle});
  final BodyGeometry geometry;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Row(children: [
    for (final side in ['front', 'back'])
      Expanded(child: _Side(geometry: geometry, side: side, selected: selected, onToggle: onToggle)),
  ]);
}

class _Side extends StatelessWidget {
  const _Side({required this.geometry, required this.side, required this.selected, required this.onToggle});
  final BodyGeometry geometry;
  final String side;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final box = geometry._views[side]!.box;
    return AspectRatio(
      aspectRatio: box.width / box.height,
      child: LayoutBuilder(builder: (context, c) {
        final scale = c.maxWidth / box.width;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final slug = geometry.hit(side, Offset(d.localPosition.dx / scale + box.left, d.localPosition.dy / scale + box.top));
            if (slug != null) onToggle(slug);
          },
          child: CustomPaint(painter: _Painter(geometry._views[side]!, selected, scale)),
        );
      }),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.view, this.selected, this.scale) : look = OG.palette.signature;
  final String look;
  final _View view;
  final Set<String> selected;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-view.box.left, -view.box.top);
    final sil = Paint()..color = OG.line;
    for (final p in view.inert) {
      canvas.drawPath(p, sil);
    }
    for (final e in view.muscles.entries) {
      final on = selected.contains(e.key);
      final fill = Paint()..color = on ? OG.acc : const Color(0xFF5B616C);
      final edge = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5 / scale..color = OG.bg;
      for (final p in e.value) {
        canvas.drawPath(p, fill);
        canvas.drawPath(p, edge);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Painter old) => old.look != look || old.view != view || old.selected.length != selected.length || !old.selected.containsAll(selected) || old.scale != scale;
}
