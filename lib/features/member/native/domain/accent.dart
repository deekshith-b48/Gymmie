// The accent colour, ported from openGym's lib/accent.js and lib/format.js (ACCENTS).
//
// Stored as two settings: `accent` names the choice ('lime', 'sky', ... or 'custom') and
// `accentCustom` keeps the member's own colour as '#rrggbb'. Nothing here trusts a stored value: it
// comes from other devices, backups and the server, and only a plain six-digit hex gets to be a colour.
// A custom colour is checked against the theme's backgrounds and, when it would vanish into them,
// made lighter or darker just far enough to be read (same maths as openGym, golden-tested).
import 'dart:math' as math;

const defaultAccent = 'lime';
const customAccent = 'custom';

/// Preset names in the order openGym lists them.
const accentNames = <String, String>{
  'lime': 'Green', 'sky': 'Blue', 'orange': 'Orange', 'violet': 'Purple',
  'pink': 'Pink', 'red': 'Red', 'teal': 'Teal', 'gold': 'Yellow',
};

/// The dark theme's shade of each preset (openGym ACCENTS).
const accentDark = <String, String>{
  'lime': '#30d158', 'sky': '#0a84ff', 'orange': '#ff9f0a', 'violet': '#bf5af2',
  'pink': '#ff375f', 'red': '#ff453a', 'teal': '#40c8e0', 'gold': '#ffd60a',
};

/// The light theme's shade (index.css, :root[data-theme=light] system colours).
const accentLight = <String, String>{
  'lime': '#34c759', 'sky': '#007aff', 'orange': '#ff9500', 'violet': '#af52de',
  'pink': '#ff2d55', 'red': '#ff3b30', 'teal': '#30b0c7', 'gold': '#ffcc00',
};

/// Text drawn on top of a preset (ACCENT_INK).
const accentInk = <String, String>{
  'lime': '#000000', 'sky': '#ffffff', 'orange': '#000000', 'violet': '#ffffff',
  'pink': '#ffffff', 'red': '#ffffff', 'teal': '#000000', 'gold': '#000000',
};

final _hex = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);

/// '#rrggbb' in lowercase, or null for anything else.
String? cleanHex(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return _hex.hasMatch(t) ? t.toLowerCase() : null;
}

/// The choice to draw: a known preset, 'custom' with a usable colour, or the default.
String accentKeyOf(Map<String, dynamic> s) {
  final k = s['accent'];
  if (k is String && accentDark.containsKey(k)) return k;
  if (k == customAccent && cleanHex(s['accentCustom']) != null) return customAccent;
  return defaultAccent;
}

// ---- colour maths (sRGB, WCAG 2 relative luminance) ---------------------------------------------------------------------

List<int> _rgb(String hex) {
  final n = int.parse(hex.substring(1), radix: 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

String _toHex(List<double> c) {
  String h(double v) => v.clamp(0, 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c[0])}${h(c[1])}${h(c[2])}';
}

double _lin(int v8) {
  final v = v8 / 255;
  return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(String hex) {
  final c = _rgb(hex);
  return 0.2126 * _lin(c[0]) + 0.7152 * _lin(c[1]) + 0.0722 * _lin(c[2]);
}

/// WCAG contrast ratio of two '#rrggbb' colours, 1 to 21.
double contrast(String a, String b) {
  final x = luminance(a), y = luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// [hex] moved [t] (0..1) of the way to [to].
String mix(String hex, String to, double t) {
  final a = _rgb(hex), b = _rgb(to);
  return _toHex([for (var i = 0; i < 3; i++) a[i] + (b[i] - a[i]) * t]);
}

/// Black or white, whichever reads better on [hex] (black on a tie).
String inkOn(String hex) => contrast(hex, '#000000') >= contrast(hex, '#ffffff') ? '#000000' : '#ffffff';

class _Theme {
  const _Theme(this.bgs, this.min, this.toward, this.label2);
  final List<String> bgs;
  final double min;
  final String toward;
  final List<String> label2;
}

const _themes = <String, _Theme>{
  'dark': _Theme(['#000000', '#1c1c1e'], 3, '#ffffff', ['#8d8d93', '#98989f']),
  'light': _Theme(['#f2f2f7', '#ffffff'], 3, '#000000', ['#85858b', '#8a8a8e']),
};
const _greySat = 0.25;
const _greyText = 4.5;
const _greyGap = 2;

double _worst(String hex, List<String> bgs) => bgs.map((b) => contrast(hex, b)).reduce(math.min);

List<double> _toHsl(String hex) {
  final c = _rgb(hex).map((v) => v / 255).toList();
  final r = c[0], g = c[1], b = c[2];
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2, d = mx - mn;
  if (d == 0) return [0, 0, l];
  final s = d / (1 - (2 * l - 1).abs());
  final h = mx == r ? ((g - b) / d) % 6 : mx == g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
}

String _fromHsl(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - (((h / 60) % 2) - 1).abs());
  final m = l - c / 2;
  final List<double> rgb = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return _toHex([for (final v in rgb) (v + m) * 255]);
}

/// Whether [hex] counts as a grey (white, black, #808080, near-whites).
bool isGrey(String hex) => _toHsl(hex)[1] < _greySat;

/// [hex] as drawn in [theme] ('dark' or 'light'): unchanged when it already stands out enough, otherwise
/// made lighter (dark theme) or darker (light theme) in small steps of HSL lightness, hue and saturation kept.
String readableIn(String hex, String theme) {
  final th = _themes[theme] ?? _themes['dark']!;
  final grey = isGrey(hex);
  bool ok(String c) => grey ? _worst(c, th.bgs) >= _greyText && _worst(c, th.label2) >= _greyGap : _worst(c, th.bgs) >= th.min;
  if (ok(hex)) return hex;
  final hsl = _toHsl(hex);
  final s = hsl[1], l = hsl[2];
  final up = th.toward == '#ffffff';
  final hue = hsl[0] < 0 ? hsl[0] + 360 : hsl[0];
  final yellow = !up && hue >= 48 && hue <= 72;
  for (var i = 1; i <= 50; i++) {
    final c = _fromHsl(yellow ? math.max(42, hue - i * 1.5) : hue, s, up ? math.min(1, l + i * 0.02) : math.max(0, l - i * 0.02));
    if (ok(c)) return c;
  }
  return th.toward;
}

/// The text colour for a button that is [acc] at rest and [acc2] while pressed.
String inkOnBoth(String acc, String acc2) {
  final ink = inkOn(acc);
  if (contrast(acc2, ink) >= 3) return ink;
  final other = ink == '#000000' ? '#ffffff' : '#000000';
  double score(String k) => math.min(contrast(acc, k), contrast(acc2, k));
  return score(other) > score(ink) ? other : ink;
}

/// The colour drawn for the accent in [theme], and the text colour on top of it.
({String acc, String ink}) resolveAccent(Map<String, dynamic> s, String theme) {
  final key = accentKeyOf(s);
  if (key == customAccent) {
    final acc = readableIn(cleanHex(s['accentCustom'])!, theme);
    return (acc: acc, ink: inkOnBoth(acc, mix(acc, '#000000', 0.25)));
  }
  return (acc: (theme == 'light' ? accentLight : accentDark)[key]!, ink: accentInk[key]!);
}
