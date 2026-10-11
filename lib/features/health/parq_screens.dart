import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signature/signature.dart';

import '../../app/di.dart';
import '../../core/network/api_exception.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/widgets/auth_image.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/repositories/extras_repository.dart';

const _types = ['heading', 'text', 'question', 'signature'];

/// Owner-side PAR-Q form builder: edit widgets, generate by screening area, save as a major/minor version.
class ParqBuilderScreen extends StatefulWidget {
  const ParqBuilderScreen({super.key});
  @override
  State<ParqBuilderScreen> createState() => _ParqBuilderScreenState();
}

class _ParqBuilderScreenState extends State<ParqBuilderScreen> {
  final _repo = getIt<ExtrasRepository>();
  final _title = TextEditingController();
  List<Json> _widgets = [];
  String _version = '';
  String _consent = '';
  bool _loading = true, _dirty = false, _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _apply(Json f) {
    _title.text = f.s('title');
    _widgets = [
      for (final w in (f['widgets'] as List? ?? []))
        Map<String, dynamic>.from(w as Map),
    ];
    _consent = f.s('consent');
    _version = f.s('version');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _apply(await _repo.parqForm());
      _dirty = false;
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editWidget([int? index]) async {
    final w = index == null
        ? <String, dynamic>{
            'type': 'question',
            'answerType': 'yesno',
            'required': true,
          }
        : _widgets[index];
    final text = TextEditingController(text: w.str('text'));
    final opts = TextEditingController(
      text: ((w['options'] as List?) ?? []).join(', '),
    );
    var type = w.s('type', 'question');
    var answer = w.s('answerType', 'yesno');
    var required = w['required'] != false;
    var critical = w['critical'] == true;
    final key = GlobalKey<FormState>();
    final ok = await showAppSheet<bool>(
      context,
      title: index == null ? 'Add Question' : 'Edit',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            children: [
              DropdownField<String>(
                label: 'Type',
                value: type,
                items: _types,
                onChanged: (v) => set(() => type = v ?? type),
              ),
              if (type != 'signature') ...[
                const SizedBox(height: 12),
                AppTextField(
                  controller: text,
                  label: type == 'question' ? 'Question text *' : 'Text',
                  maxLines: 3,
                  maxLength: 600,
                  validator: (v) => V.required(
                    v,
                    type == 'question'
                        ? 'Question text *'
                        : 'Please enter the title',
                  ),
                ),
              ],
              if (type == 'question') ...[
                const SizedBox(height: 12),
                DropdownField<String>(
                  label: 'Answer type',
                  value: answer,
                  items: const ['yesno', 'text', 'choice'],
                  onChanged: (v) => set(() => answer = v ?? answer),
                ),
                if (answer == 'choice') ...[
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: opts,
                    label: 'Options (comma separated)',
                    validator: (v) =>
                        (v ?? '')
                                .split(',')
                                .where((e) => e.trim().isNotEmpty)
                                .length <
                            2
                        ? 'Add at least two options'
                        : null,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Required'),
                  value: required,
                  onChanged: (v) => set(() => required = v),
                ),
                if (answer == 'yesno')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('A "Yes" answer is a high-risk flag'),
                    value: critical,
                    onChanged: (v) => set(() => critical = v),
                  ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      final out = <String, dynamic>{
        if (w['id'] != null) 'id': w['id'],
        'type': type,
        if (type != 'signature')
          'text': text.text.trim()
        else
          'text': text.text.trim().isEmpty
              ? 'Member signature + I Agree'
              : text.text.trim(),
        if (type == 'question') ...{
          'answerType': answer,
          'required': required,
          'critical': answer == 'yesno' && critical,
          if (answer == 'choice')
            'options': opts.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
        },
      };
      setState(() {
        if (index == null) {
          // keep the signature widget last
          final sig = _widgets.lastIndexWhere((e) => e['type'] == 'signature');
          _widgets.insert(
            sig >= 0 && type != 'signature' ? sig : _widgets.length,
            out,
          );
        } else {
          _widgets[index] = out;
        }
        _dirty = true;
      });
    }
    text.dispose();
    opts.dispose();
  }

  Future<void> _generate() async {
    final areas = await runWithProgress<List<String>>(context, _repo.parqAreas);
    if (areas == null || !mounted) return;
    final chosen = <String>{};
    final go = await showAppSheet<bool>(
      context,
      title: 'Generate PAR-Q',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InfoBanner(
              'Builds a draft from the standard questions plus a question bank for each selected area. Rule-based, not an AI model. Review before saving.',
              icon: Icons.auto_awesome,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in areas)
                  PillChip(
                    label: a,
                    selected: chosen.contains(a),
                    onTap: () => set(
                      () =>
                          chosen.contains(a) ? chosen.remove(a) : chosen.add(a),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final f = await runWithProgress<Json>(
      context,
      () => _repo.parqGenerate(chosen.toList()),
    );
    if (f != null && mounted) {
      setState(() {
        _apply({...f, 'version': _version});
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      return showToast(context, 'Please enter the title', error: true);
    }
    final change = await chooseOne<String>(
      context,
      title: 'Save as',
      items: const ['minor', 'major'],
      labelOf: (v) => v == 'major'
          ? 'Major revision — members must re-sign'
          : 'Minor edit — existing signatures stay valid',
    );
    if (change == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final f = await _repo.parqSave({
        'title': _title.text.trim(),
        'widgets': _widgets,
        'consent': _consent,
        'changeType': change,
      });
      if (!mounted) return;
      setState(() {
        _apply(f);
        _dirty = false;
      });
      showToast(context, 'PAR-Q form saved (v${f.s('version')})');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(_version.isEmpty ? 'PAR-Q Form' : 'PAR-Q Form · v$_version'),
      actions: [
        if (!_loading && _error == null)
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Generate',
            onPressed: _generate,
          ),
      ],
    );
    if (_loading) return Scaffold(appBar: appBar, body: const LoadingBox());
    if (_error != null) {
      return Scaffold(
        appBar: appBar,
        body: ErrorState(error: toApiException(_error!), onRetry: _load),
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(
          context,
          title: 'Unsaved changes?',
          message: 'Your changes to the PAR-Q form have not been saved. Leave without saving?',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: appBar,
        body: Column(
          children: [
            Expanded(
              child: ReorderableListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                header: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppTextField(
                    controller: _title,
                    label: 'Form Title',
                    maxLength: 120,
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
                onReorderItem: (a, b) => setState(() {
                  _widgets.insert(b, _widgets.removeAt(a));
                  _dirty = true;
                }),
                children: [
                  for (final (i, w) in _widgets.indexed)
                    Card(
                      key: ValueKey(w['id'] ?? i),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(switch (w['type']) {
                          'heading' => Icons.title,
                          'text' => Icons.notes,
                          'signature' => Icons.draw_outlined,
                          _ => Icons.help_outline,
                        }),
                        title: Text(
                          w.str('text') ?? 'Signature',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: w['type'] == 'question'
                            ? Text(
                                '${w.s('answerType')}${w['critical'] == true ? ' · high-risk flag' : ''}${w['required'] == false ? ' · optional' : ''}',
                              )
                            : Text(w.s('type')),
                        onTap: () => _editWidget(i),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _widgets.removeAt(i);
                            _dirty = true;
                          }),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editWidget(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: LoadingButton(
                        label: 'Save Form',
                        loading: _saving,
                        onPressed: _dirty ? _save : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Member PAR-Q: shows the latest signed submission, or lets staff capture answers + signature.
class MemberParqScreen extends StatefulWidget {
  const MemberParqScreen({super.key, required this.memberId});
  final String memberId;
  @override
  State<MemberParqScreen> createState() => _MemberParqScreenState();
}

class _MemberParqScreenState extends State<MemberParqScreen> {
  final _repo = getIt<ExtrasRepository>();
  late final AsyncCubit<(Json, List<Json>)> _cubit = AsyncCubit(
    () async =>
        (await _repo.parqForm(), await _repo.parqSubmissions(widget.memberId)),
  );
  bool _signing = false;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PAR-Q')),
      body: AsyncBody<(Json, List<Json>)>(
        cubit: _cubit,
        builder: (context, d) {
          final form = d.$1;
          final subs = d.$2;
          final latest = subs.isEmpty ? null : subs.first;
          final current =
              latest != null && latest.i('formMajor') == form.i('major');
          if (_signing || latest == null || !current) {
            return _SignForm(
              form: form,
              memberId: widget.memberId,
              resign: latest != null,
              onDone: () {
                setState(() => _signing = false);
                _cubit.load();
              },
            );
          }
          final risk = latest.s('riskLevel');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'PAR-Q signed',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Tag(
                          '${risk[0].toUpperCase()}${risk.substring(1)} risk',
                          tone: risk == 'high'
                              ? Tone.danger
                              : risk == 'moderate'
                              ? Tone.warning
                              : Tone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Version ${latest.s('version')} · ${Fmt.dateTime(latest.str('signedAt'))}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if ((latest['flagged'] as List? ?? []).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Answered "Yes"',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final f in latest['flagged'] as List)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: (f as Map)['critical'] == true
                                    ? AppColors.danger
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${f['text']}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Signature',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: AuthImage(
                        url: latest.s('signatureUrl'),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() => _signing = true),
                child: const Text('Re-sign'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SignForm extends StatefulWidget {
  const _SignForm({
    required this.form,
    required this.memberId,
    required this.resign,
    required this.onDone,
  });
  final Json form;
  final String memberId;
  final bool resign;
  final VoidCallback onDone;
  @override
  State<_SignForm> createState() => _SignFormState();
}

class _SignFormState extends State<_SignForm> {
  final _repo = getIt<ExtrasRepository>();
  final _answers = <String, String>{};
  final _pad = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  bool _agreed = false, _busy = false;
  String? _missing;

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  List<Json> get _widgets => [
    for (final w in (widget.form['widgets'] as List? ?? []))
      Map<String, dynamic>.from(w as Map),
  ];

  Future<void> _submit() async {
    for (final w in _widgets.where(
      (w) => w['type'] == 'question' && w['required'] != false,
    )) {
      if ((_answers[w.s('id')] ?? '').trim().isEmpty) {
        setState(() => _missing = w.s('id'));
        return showToast(context, 'Please answer this question', error: true);
      }
    }
    if (_pad.isEmpty) {
      return showToast(context, 'Please draw your signature', error: true);
    }
    if (!_agreed) {
      return showToast(
        context,
        'Please confirm the declaration to continue',
        error: true,
      );
    }
    setState(() => _busy = true);
    try {
      final png = await _pad.toPngBytes();
      await _repo.parqSign(widget.memberId, {
        'answers': [
          for (final e in _answers.entries)
            {'widgetId': e.key, 'answer': e.value},
        ],
        'signature': 'data:image/png;base64,${base64Encode(png!)}',
        'agreed': true,
      });
      if (!mounted) return;
      showToast(context, 'PAR-Q signed successfully');
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.resign)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: InfoBanner(
                    'The PAR-Q form was revised. Please sign the new version.',
                    icon: Icons.info_outline,
                  ),
                ),
              for (final w in _widgets)
                switch (w['type']) {
                  'heading' => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      w.s('text'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  'text' => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      w.s('text'),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  'question' => _question(w),
                  _ => const SizedBox.shrink(),
                },
              const SizedBox(height: 8),
              const Text(
                'Signature',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Signature(
                    controller: _pad,
                    height: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _pad.clear,
                  child: const Text('Clear'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: Text(
                  widget.form.s('consent'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LoadingButton(
              label: 'I Agree & Sign',
              loading: _busy,
              onPressed: _submit,
            ),
          ),
        ),
      ],
    );
  }

  Widget _question(Json w) {
    final id = w.s('id');
    final answer = _answers[id];
    final invalid = _missing == id && (answer ?? '').isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${w.s('text')}${w['required'] == false ? '' : ' *'}',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: invalid ? AppColors.danger : null,
            ),
          ),
          const SizedBox(height: 6),
          switch (w.s('answerType')) {
            'text' => AppTextField(
              maxLines: 2,
              maxLength: 500,
              onChanged: (v) => _answers[id] = v,
            ),
            'choice' => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in (w['options'] as List? ?? []))
                  PillChip(
                    label: '$o',
                    selected: answer == o,
                    onTap: () => setState(() => _answers[id] = '$o'),
                  ),
              ],
            ),
            _ => Row(
              children: [
                for (final o in const ['yes', 'no'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: o == 'yes' ? 'Yes' : 'No',
                      selected: answer == o,
                      onTap: () => setState(() => _answers[id] = o),
                    ),
                  ),
              ],
            ),
          },
        ],
      ),
    );
  }
}
