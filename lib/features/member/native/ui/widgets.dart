import 'package:flutter/material.dart';

import '../domain/catalogue.dart';
import 'theme.dart';

int _weightDecimals = 1;

/// Settings → Units → Weight decimals: 1 reads fine for plate-loadable numbers, 2 for quarter plates and
/// microplates. Display only; nothing stored is rounded.
void setWeightDecimals(int n) => _weightDecimals = n == 2 ? 2 : 1;
int get weightDecimals => _weightDecimals;

String fmtNum(num v) {
  final p = _weightDecimals == 2 ? 100 : 10;
  final r = (v * p).round() / p;
  return r == r.truncateToDouble() ? r.toInt().toString() : r.toString();
}

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
}

class OgCard extends StatelessWidget {
  const OgCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.margin = const EdgeInsets.only(bottom: 12)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: OG.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(text.toUpperCase(), style: TextStyle(color: OG.dim, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
  );
}

/// An exercise's picture (served by the training-log host), or a plain icon when there is none.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb(this.ex, {super.key, this.mediaBase, this.size = 52});
  final Exercise? ex;
  final String? mediaBase;
  final double size;

  @override
  Widget build(BuildContext context) {
    final e = ex;
    final icon = Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: OG.card2, borderRadius: BorderRadius.circular(12)),
      child: Icon(e?.cardio == true ? Icons.directions_run : Icons.fitness_center, color: OG.dim, size: size * 0.45),
    );
    if (e == null || e.img.isEmpty || mediaBase == null || mediaBase!.isEmpty) return icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        '$mediaBase/exercise-media/still/${e.img}',
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, _, _) => icon,
        loadingBuilder: (_, child, p) => p == null ? child : icon,
      ),
    );
  }
}

class StepperField extends StatelessWidget {
  const StepperField({super.key, required this.value, required this.step, required this.onChanged, this.min = 0, this.max = 9999, this.width = 96, this.buttons = true});
  final num value;
  final num step;
  final num min;
  final num max;
  final double width;
  final ValueChanged<num> onChanged;

  /// The plus and minus buttons (Settings → Fine-tuning → "Weight and reps buttons"). Off, the number is
  /// tapped and typed.
  final bool buttons;

  Future<void> _type(BuildContext context) async {
    final c = TextEditingController(text: fmtNum(value));
    final v = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), onSubmitted: (s) => Navigator.pop(ctx, num.tryParse(s.replaceAll(',', '.')))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, num.tryParse(c.text.replaceAll(',', '.'))), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.isFinite) onChanged(v.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final number = InkWell(
      onTap: () => _type(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40, alignment: Alignment.center,
        decoration: buttons ? null : BoxDecoration(color: OG.card2, borderRadius: BorderRadius.circular(10)),
        child: Text(fmtNum(value), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    );
    if (!buttons) return SizedBox(width: width + 24, child: number);
    return SizedBox(
      width: width + 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _btn(Icons.remove, () => onChanged((value - step).clamp(min, max))),
          SizedBox(width: width - 32, child: number),
          _btn(Icons.add, () => onChanged((value + step).clamp(min, max))),
        ],
      ),
    );
  }

  Widget _btn(IconData i, VoidCallback f) => SizedBox(
    width: 32, height: 40,
    child: IconButton(padding: EdgeInsets.zero, iconSize: 18, color: OG.dim, onPressed: f, icon: Icon(i)),
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(BuildContext context, String title, {String? message, String ok = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok, style: TextStyle(color: danger ? OG.red : OG.acc)),
        ),
      ],
    ),
  );
  return r ?? false;
}
