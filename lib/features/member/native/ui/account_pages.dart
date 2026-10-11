// The member's own account, kept on the gym's server: profile and photo, phone number, signed-in phones, privacy,
// notices, membership requests and closing the app account. Every change is a call the server authorises for THIS
// member (it never takes an id from here), so each screen simply says what happened or why it could not.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/data/countries.dart' show toE164;
import '../../../../data/models/user_gym.dart' show OtpChallenge;
import '../../../auth/phone_input.dart';
import '../../member_models.dart';
import 'async_section.dart';
import 'scope.dart';
import 'settings_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

/// What to tell the member when a call failed.
String failure(Object e, [String fallback = 'Could not save this. Try again.']) {
  if (e is ApiException) return e.isNetwork ? 'You need to be online to do this.' : e.message;
  return fallback;
}

const goalLabels = {
  'lose_fat': 'Lose fat', 'build_muscle': 'Build muscle', 'get_stronger': 'Get stronger', 'stay_fit': 'Stay fit',
  'endurance': 'Endurance', 'flexibility': 'Flexibility', 'recovery': 'Recovery',
};
const levelLabels = {'beginner': 'Beginner', 'intermediate': 'Intermediate', 'advanced': 'Advanced'};

void pushPage(BuildContext c, Widget page) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page));

// ---- edit profile ---------------------------------------------------------------------------------------------------

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: AsyncSection<MemberAccount>(load: sc.gymApi.account, builder: (context, a) => _ProfileForm(initial: a)),
      ),
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({required this.initial});
  final MemberAccount initial;
  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final _key = GlobalKey<FormState>();
  late MemberAccount _a = widget.initial;
  late final _name = TextEditingController(text: _a.name);
  late final _email = TextEditingController(text: _a.email ?? '');
  late final _address = TextEditingController(text: _a.address ?? '');
  late final _ecName = TextEditingController(text: _a.emergencyName ?? '');
  late final _ecPhone = TextEditingController(text: _a.emergencyPhone ?? '');
  late final _height = TextEditingController(text: _a.heightCm == null ? '' : fmtNum(_a.heightCm!));
  late final _weight = TextEditingController(text: _a.weightKg == null ? '' : fmtNum(_a.weightKg!));
  late final _notes = TextEditingController(text: _a.fitnessNotes ?? '');
  String? _gender, _blood, _birth, _goal, _level;
  int? _days;
  Uint8List? _photo;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gender = _a.gender;
    _blood = _a.bloodGroup;
    _birth = _a.birthDate;
    _goal = _a.goal;
    _level = _a.level;
    _days = _a.daysPerWeek;
    if (_a.hasPhoto) _loadPhoto();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _address, _ecName, _ecPhone, _height, _weight, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    final p = await NativeScope.of(context).gymApi.photo().catchError((_) => null);
    if (mounted) setState(() => _photo = p);
  }

  Future<void> _pickPhoto() async {
    final api = NativeScope.of(context).gymApi;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await x.readAsBytes();
      final mime = x.mimeType ?? (x.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      _a = await api.setPhoto(bytes, mime);
      if (mounted) setState(() => _photo = bytes);
    } catch (e) {
      if (mounted) toast(context, failure(e, 'Could not upload the photo.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _busy = true);
    try {
      _a = await NativeScope.of(context).gymApi.removePhoto();
      if (mounted) setState(() => _photo = null);
    } catch (e) {
      if (mounted) toast(context, failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _textOrNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final ecName = _textOrNull(_ecName), ecPhone = _textOrNull(_ecPhone);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'email': _textOrNull(_email),
      'gender': _gender,
      'birthDate': _birth,
      'bloodGroup': _blood,
      'address': _textOrNull(_address),
      'emergencyContact': ecName != null && ecPhone != null ? {'name': ecName, 'phone': ecPhone} : null,
      'heightCm': double.tryParse(_height.text.trim()),
      'weightKg': double.tryParse(_weight.text.trim()),
      'fitness': {'goal': _goal, 'level': _level, 'daysPerWeek': _days, 'notes': _textOrNull(_notes)},
    };
    setState(() { _busy = true; _error = null; });
    try {
      await NativeScope.of(context).gymApi.updateAccount(body);
      if (!mounted) return;
      toast(context, 'Profile saved');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(_birth ?? '') ?? DateTime(now.year - 25);
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(now.year - 110), lastDate: now);
    if (d != null) setState(() => _birth = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint, filled: true, fillColor: OG.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none));

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  Widget _drop<T>(String label, T? value, Map<T, String> options, ValueChanged<T?> onChanged) => _gap(DropdownButtonFormField<T>(
    initialValue: value, decoration: _dec(label), dropdownColor: OG.card2,
    items: [DropdownMenuItem<T>(value: null, child: Text('Not set', style: TextStyle(color: OG.dim))), for (final e in options.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
    onChanged: _busy ? null : onChanged,
  ));

  String? _numIn(String? v, double lo, double hi) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    return n == null || n < lo || n > hi ? 'Between ${fmtNum(lo)} and ${fmtNum(hi)}' : null;
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _key,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Column(children: [
        CircleAvatar(
          radius: 44, backgroundColor: OG.acc.withValues(alpha: 0.2), backgroundImage: _photo == null ? null : MemoryImage(_photo!),
          child: _photo == null ? Icon(Icons.person, size: 44, color: OG.acc) : null,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: _busy ? null : _pickPhoto, icon: const Icon(Icons.photo_camera_outlined, size: 18), label: Text(_photo == null ? 'Add photo' : 'Change photo')),
          if (_photo != null) TextButton(onPressed: _busy ? null : _removePhoto, child: Text('Remove', style: TextStyle(color: OG.red))),
        ]),
      ])),
      const SectionLabel('About you'),
      _gap(TextFormField(
        controller: _name, decoration: _dec('Name'), textCapitalization: TextCapitalization.words, maxLength: 80, enabled: !_busy,
        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
      )),
      _gap(TextFormField(
        controller: _email, decoration: _dec('Email'), keyboardType: TextInputType.emailAddress, enabled: !_busy,
        validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : 'Enter a valid email',
      )),
      _drop<String>('Gender', _gender, const {'male': 'Male', 'female': 'Female', 'other': 'Other'}, (v) => setState(() => _gender = v)),
      _gap(InkWell(
        onTap: _busy ? null : _pickBirth,
        child: InputDecorator(
          decoration: _dec('Date of birth').copyWith(suffixIcon: _birth == null ? const Icon(Icons.calendar_today_outlined, size: 18) : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _birth = null))),
          child: Text(_birth ?? 'Not set', style: TextStyle(color: _birth == null ? OG.dim : OG.text)),
        ),
      )),
      _drop<String>('Blood group', _blood, {for (final b in const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']) b: b}, (v) => setState(() => _blood = v)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _gap(TextFormField(controller: _height, decoration: _dec('Height (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !_busy, validator: (v) => _numIn(v, 50, 260)))),
        const SizedBox(width: 12),
        Expanded(child: _gap(TextFormField(controller: _weight, decoration: _dec('Weight (kg)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !_busy, validator: (v) => _numIn(v, 10, 500)))),
      ]),
      _gap(TextFormField(controller: _address, decoration: _dec('Address'), maxLines: 2, maxLength: 250, enabled: !_busy)),
      const SectionLabel('Emergency contact'),
      _gap(TextFormField(controller: _ecName, decoration: _dec('Name'), maxLength: 80, enabled: !_busy)),
      _gap(TextFormField(
        controller: _ecPhone, decoration: _dec('Phone', hint: '+91 98765 43210'), keyboardType: TextInputType.phone, enabled: !_busy,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
        validator: (v) => (v ?? '').trim().isEmpty && _ecName.text.trim().isEmpty ? null : (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch((v ?? '').replaceAll(' ', '')) ? null : 'Use the international form, e.g. +919876543210'),
      )),
      const SectionLabel('Fitness profile'),
      _drop<String>('Goal', _goal, goalLabels, (v) => setState(() => _goal = v)),
      _drop<String>('Level', _level, levelLabels, (v) => setState(() => _level = v)),
      _drop<int>('Days per week', _days, {for (var i = 1; i <= 7; i++) i: '$i'}, (v) => setState(() => _days = v)),
      _gap(TextFormField(controller: _notes, decoration: _dec('Anything your trainer should know'), maxLines: 3, maxLength: 200, enabled: !_busy)),
      Text('Your membership, plan, dates and payments are set by your gym and cannot be changed here.', style: TextStyle(color: OG.dim, fontSize: 12)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: OG.red))),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: OG.acc, foregroundColor: OG.onAcc, minimumSize: const Size.fromHeight(50)),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
      ),
    ]),
  );
}

// ---- a one-time code step, shared by "change phone" and "delete account" -----------------------------------------------

class _CodeStep extends StatefulWidget {
  const _CodeStep({required this.challenge, required this.actionLabel, required this.onSubmit, this.danger = false, this.extra});
  final OtpChallenge challenge;
  final String actionLabel;
  final bool danger;
  final Widget? extra;
  final Future<void> Function(String code) onSubmit;
  @override
  State<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<_CodeStep> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final c = _code.text.trim();
    if (c.length < 4) {
      setState(() => _error = 'Enter the code you received.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.onSubmit(c);
    } catch (e) {
      if (mounted) setState(() => _error = failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('We sent a code to ${widget.challenge.maskedTarget ?? 'your phone'}.', style: TextStyle(color: OG.dim)),
    if (widget.challenge.devOtp != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Development server: code ${widget.challenge.devOtp}', style: TextStyle(color: OG.orange, fontSize: 12))),
    const SizedBox(height: 12),
    TextField(
      controller: _code, keyboardType: TextInputType.number, maxLength: 8, enabled: !_busy, autofocus: true,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly], textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, letterSpacing: 6),
      decoration: InputDecoration(counterText: '', hintText: 'Code', filled: true, fillColor: OG.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
      onSubmitted: (_) => _go(),
    ),
    if (widget.extra != null) widget.extra!,
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: OG.red))),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _go,
      style: FilledButton.styleFrom(backgroundColor: widget.danger ? OG.red : OG.acc, foregroundColor: widget.danger ? Colors.white : OG.onAcc, minimumSize: const Size.fromHeight(50)),
      child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.actionLabel),
    ),
  ]);
}

// ---- change phone ------------------------------------------------------------------------------------------------------

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});
  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  String _dial = '+91';
  OtpChallenge? _challenge;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final c = await NativeScope.of(context).gymApi.requestPhoneChange(toE164(_phone.text, dial: _dial));
      if (mounted) setState(() => _challenge = c);
    } catch (e) {
      if (mounted) setState(() => _error = failure(e, 'Could not send the code.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Change phone number')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Text('Your phone number is how you sign in. A code goes to the new number to prove it is yours. Your gym’s records follow you; other phones you are signed in on will be signed out.', style: TextStyle(color: OG.dim, height: 1.4)),
        const SizedBox(height: 16),
        if (_challenge == null)
          Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PhoneInput(controller: _phone, dial: _dial, label: 'New phone number', onDialChanged: (d) => setState(() => _dial = d), onSubmitted: (_) => _send()),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: OG.red))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _send,
              style: FilledButton.styleFrom(backgroundColor: OG.acc, foregroundColor: OG.onAcc, minimumSize: const Size.fromHeight(50)),
              child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send code'),
            ),
          ]))
        else
          _CodeStep(
            challenge: _challenge!, actionLabel: 'Change number',
            onSubmit: (code) async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final phone = await sc.gymApi.verifyPhoneChange(_challenge!.requestId, code);
              messenger.showSnackBar(SnackBar(content: Text('Your number is now $phone')));
              nav.pop();
            },
          ),
      ]),
    );
  }
}

// ---- devices & security ------------------------------------------------------------------------------------------------

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<DeviceSession>> _f = NativeScope.of(context).gymApi.sessions();
  bool _busy = false;

  void _reload() => setState(() {
    _f = NativeScope.of(context).gymApi.sessions();
  });

  Future<void> _end(DeviceSession s) async {
    final sc = NativeScope.of(context);
    if (!await confirm(context, 'Sign out ${s.device}?', message: 'That phone will need your phone number and a code to sign in again.', ok: 'Sign out', danger: true)) return;
    setState(() => _busy = true);
    try {
      await sc.gymApi.endSession(s.id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) toast(context, failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endOthers() async {
    final sc = NativeScope.of(context);
    if (!await confirm(context, 'Sign out all other phones?', message: 'This phone stays signed in.', ok: 'Sign out others', danger: true)) return;
    setState(() => _busy = true);
    try {
      await sc.gymApi.endOtherSessions();
      if (mounted) _reload();
    } catch (e) {
      if (mounted) toast(context, failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _when(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 2) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices & security')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('You sign in with a code sent to your phone, so there is no password to remember or leak. These are the phones signed in to your account.', style: TextStyle(color: OG.dim, height: 1.4)),
        const SizedBox(height: 16),
        FutureBuilder<List<DeviceSession>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
            if (snap.hasError) {
              return Row(children: [
                Icon(Icons.cloud_off, color: OG.orange), const SizedBox(width: 10),
                Expanded(child: Text(failure(snap.error!, 'Could not load your devices.'), style: TextStyle(color: OG.dim))),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ]);
            }
            final list = snap.data!;
            if (list.isEmpty) return OgCard(child: Text('No other sessions.', style: TextStyle(color: OG.dim)));
            return SettingsSection(
              title: 'Signed in',
              children: [
                for (final s in list) SettingsRow(
                  icon: s.current ? Icons.smartphone_rounded : Icons.devices_other_rounded, tint: s.current ? OG.acc : OG.blue,
                  title: s.device, subtitle: s.current ? 'This phone · active now' : 'Last active ${_when(s.lastActiveAt)}',
                  trailing: s.current ? null : IconButton(tooltip: 'Sign out this phone', icon: Icon(Icons.logout_rounded, color: OG.red), onPressed: _busy ? null : () => _end(s)),
                ),
              ],
            );
          },
        ),
        SettingsSection(children: [
          SettingsRow(icon: Icons.phonelink_erase_rounded, tint: OG.orange, title: 'Sign out all other phones', enabled: !_busy, onTap: _endOthers),
          SettingsRow(icon: Icons.sim_card_outlined, tint: OG.blue, title: 'Change phone number', chevron: true, onTap: () => pushPage(context, const ChangePhoneScreen())),
          SettingsRow(
            icon: Icons.shield_outlined, tint: OG.red, danger: true, title: 'Sign out everywhere', subtitle: 'Ends every session, including this one.',
            onTap: () async {
              if (!await confirm(context, 'Sign out everywhere?', message: 'You will be signed out on every phone, including this one.', ok: 'Sign out everywhere', danger: true)) return;
              try {
                await sc.signOutEverywhere();
              } catch (e) {
                if (context.mounted) toast(context, failure(e, 'Could not sign you out everywhere. Try again.'));
              }
            },
          ),
        ]),
      ]),
    );
  }
}

// ---- privacy ------------------------------------------------------------------------------------------------------------

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: AsyncSection<PrivacySettings>(load: sc.gymApi.privacy, builder: (context, p) => _PrivacyBody(initial: p)),
      ),
    );
  }
}

const _fieldInfo = <(String, String, IconData)>[
  ('email', 'Email', Icons.mail_outline),
  ('birthDate', 'Date of birth and age', Icons.cake_outlined),
  ('address', 'Address', Icons.home_outlined),
  ('emergencyContact', 'Emergency contact', Icons.contact_phone_outlined),
  ('health', 'Health information', Icons.health_and_safety_outlined),
];

class _PrivacyBody extends StatefulWidget {
  const _PrivacyBody({required this.initial});
  final PrivacySettings initial;
  @override
  State<_PrivacyBody> createState() => _PrivacyBodyState();
}

class _PrivacyBodyState extends State<_PrivacyBody> {
  late PrivacySettings _p = widget.initial;
  bool _busy = false;

  Future<void> _save({Map<String, bool>? fields, String? share}) async {
    if (_busy) return;
    final before = _p;
    setState(() { _busy = true; });
    try {
      final next = await NativeScope.of(context).gymApi.setPrivacy(trainerCanSee: fields, shareTraining: share);
      if (mounted) setState(() => _p = next);
    } catch (e) {
      if (mounted) {
        setState(() => _p = before);
        toast(context, failure(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SettingsSection(
      title: 'What your trainer can see',
      footer: 'Your gym’s owner and managers always see what they need to run your membership. Your name, phone and attendance are always visible to your trainer.',
      children: [
        for (final f in _fieldInfo) SwitchRow(
          icon: f.$3, title: f.$2, value: _p.trainerCanSee[f.$1] ?? true, enabled: !_busy,
          onChanged: (v) => _save(fields: {f.$1: v}),
        ),
      ],
    ),
    SettingsSection(
      title: 'Share my training',
      footer: 'Your training log is private by default. Sharing only gives a summary (sessions, volume, streak), never your notes or photos.',
      children: [
        SelectRow<String>(
          icon: Icons.insights_rounded, title: 'Who sees my training summary', value: _p.shareTraining, tint: OG.purple, sheetTitle: 'Share training summary with',
          options: const [
            SelectOption('off', 'Nobody', subtitle: 'Only you.'),
            SelectOption('trainer', 'My trainer', subtitle: 'The trainer assigned to you.'),
            SelectOption('gym', 'My gym’s staff', subtitle: 'Your trainer, managers and the owner.'),
          ],
          onChanged: (v) => _save(share: v),
        ),
      ],
    ),
  ]);
}

// ---- notifications ------------------------------------------------------------------------------------------------------

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: AsyncSection<NotificationSettings>(load: sc.gymApi.notifications, builder: (context, n) => _NotificationsBody(initial: n, gym: sc.overview.gym.name)),
      ),
    );
  }
}

class _NotificationsBody extends StatefulWidget {
  const _NotificationsBody({required this.initial, required this.gym});
  final NotificationSettings initial;
  final String gym;
  @override
  State<_NotificationsBody> createState() => _NotificationsBodyState();
}

class _NotificationsBodyState extends State<_NotificationsBody> {
  late NotificationSettings _n = widget.initial;
  bool _busy = false;

  Future<void> _save({bool? announcements, bool? expiryOn, int? days}) async {
    if (_busy) return;
    final before = _n;
    setState(() => _busy = true);
    try {
      final next = await NativeScope.of(context).gymApi.setNotifications(announcements: announcements, expiryOn: expiryOn, expiryDaysBefore: days);
      if (mounted) setState(() => _n = next);
    } catch (e) {
      if (mounted) {
        setState(() => _n = before);
        toast(context, failure(e, 'Could not save this. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SettingsSection(title: 'From ${widget.gym}', children: [
      SwitchRow(
        icon: Icons.campaign_outlined, tint: OG.orange, title: 'Messages from my gym', enabled: !_busy,
        subtitle: 'Offers and announcements from ${widget.gym}.', value: _n.announcements, onChanged: (v) => _save(announcements: v),
      ),
      SwitchRow(
        icon: Icons.event_busy_outlined, tint: OG.red, title: 'Membership expiry reminder', enabled: !_busy,
        subtitle: 'A message before your membership ends.', value: _n.expiryOn, onChanged: (v) => _save(expiryOn: v),
      ),
      SelectRow<int>(
        icon: Icons.schedule_rounded, title: 'Remind me', tint: OG.blue, sheetTitle: 'Days before expiry', value: _n.expiryDaysBefore,
        options: [for (final d in const [1, 3, 7, 14, 30]) SelectOption(d, d == 1 ? '1 day before' : '$d days before')],
        onChanged: _n.expiryOn ? (v) => _save(days: v) : (_) {},
      ),
    ]),
    if (_n.mandatory.isNotEmpty) SettingsSection(
      title: 'Always on',
      footer: 'These keep your account and money safe, so they cannot be switched off.',
      children: [for (final m in _n.mandatory) SettingsRow(icon: Icons.lock_outline_rounded, tint: OG.grey, title: m)],
    ),
    Text('Workout reminders are set on this phone, under Settings → Timer alerts.', style: TextStyle(color: OG.dim, fontSize: 12)),
  ]);
}

// ---- membership requests -----------------------------------------------------------------------------------------------

String requestLabel(String type) => switch (type) { 'renew' => 'Renew', 'change_plan' => 'Change plan', 'cancel' => 'Cancel membership', _ => type };

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  late Future<List<MembershipRequest>> _f = NativeScope.of(context).gymApi.requests();
  void _reload() => setState(() {
    _f = NativeScope.of(context).gymApi.requests();
  });

  Future<void> _new() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewRequestScreen()));
    if (done == true) _reload();
  }

  Future<void> _withdraw(MembershipRequest q) async {
    final api = NativeScope.of(context).gymApi;
    if (!await confirm(context, 'Withdraw this request?', ok: 'Withdraw', danger: true)) return;
    try {
      await api.withdrawRequest(q.id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) toast(context, failure(e));
    }
  }

  Color _tint(String s) => switch (s) { 'approved' => OG.green, 'rejected' => OG.red, 'pending' => OG.orange, _ => OG.grey };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Membership requests')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _new, backgroundColor: OG.acc, foregroundColor: OG.onAcc, icon: const Icon(Icons.add), label: const Text('New request')),
    body: FutureBuilder<List<MembershipRequest>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        if (snap.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(failure(snap.error!, 'Could not load your requests.'), style: TextStyle(color: OG.dim), textAlign: TextAlign.center),
            TextButton(onPressed: _reload, child: const Text('Retry')),
          ])));
        }
        final list = snap.data!;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          Text('Ask your gym to renew, change or cancel your membership. The gym decides, then plans, dates and payments are updated by them.', style: TextStyle(color: OG.dim, height: 1.4)),
          const SizedBox(height: 16),
          if (list.isEmpty) OgCard(child: Text('You have not made any requests.', style: TextStyle(color: OG.dim))),
          for (final q in list) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(requestLabel(q.type), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: _tint(q.status).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text(q.status[0].toUpperCase() + q.status.substring(1), style: TextStyle(color: _tint(q.status), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            if (q.planName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.planName!, style: TextStyle(color: OG.dim))),
            if ((q.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('You: ${q.note}')),
            if ((q.decisionNote ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Gym: ${q.decisionNote}', style: TextStyle(color: OG.acc))),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.createdAt.length >= 10 ? q.createdAt.substring(0, 10) : q.createdAt, style: TextStyle(color: OG.dim, fontSize: 12))),
            if (q.pending) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _withdraw(q), child: Text('Withdraw', style: TextStyle(color: OG.red)))),
          ])),
        ]);
      },
    ),
  );
}

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key, this.initialType});
  final String? initialType;
  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  late String _type = widget.initialType ?? 'renew';
  String? _planId;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(MemberProfile p) async {
    setState(() { _busy = true; _error = null; });
    try {
      await NativeScope.of(context).gymApi.createRequest(
        type: _type, planId: _type == 'cancel' ? null : _planId, note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      toast(context, 'Request sent to ${p.gymName}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = failure(e, 'Could not send the request.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: AsyncSection<MemberProfile>(load: sc.gymApi.profile, builder: (context, p) {
          final plans = p.gymPlans;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'renew', label: Text('Renew')), ButtonSegment(value: 'change_plan', label: Text('Change')), ButtonSegment(value: 'cancel', label: Text('Cancel'))],
              selected: {_type}, onSelectionChanged: _busy ? null : (v) => setState(() { _type = v.first; _planId = null; }),
            ),
            const SizedBox(height: 16),
            if (_type != 'cancel') ...[
              const SectionLabel('Plan'),
              if (plans.isEmpty) Text('Your gym has no plans listed yet.', style: TextStyle(color: OG.dim)),
              for (final pl in plans) ListTile(
                onTap: _busy ? null : () => setState(() => _planId = pl.id), contentPadding: EdgeInsets.zero,
                leading: Icon((_planId ?? (_type == 'renew' ? p.current?.planId : null)) == pl.id ? Icons.radio_button_checked : Icons.radio_button_off, color: OG.acc),
                title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${p.currencySymbol}${fmtNum(pl.price)}', style: TextStyle(color: OG.dim)),
              ),
            ] else
              OgCard(child: Text('Your membership keeps running until your gym confirms the cancellation. Refunds and dates are up to the gym.', style: TextStyle(color: OG.dim, height: 1.4))),
            const SectionLabel('Note (optional)'),
            TextField(
              controller: _note, maxLength: 300, maxLines: 3, enabled: !_busy,
              decoration: InputDecoration(filled: true, fillColor: OG.card, hintText: 'Anything the front desk should know', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: OG.red))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _send(p),
              style: FilledButton.styleFrom(backgroundColor: _type == 'cancel' ? OG.red : OG.acc, foregroundColor: _type == 'cancel' ? Colors.white : OG.onAcc, minimumSize: const Size.fromHeight(50)),
              child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send request'),
            ),
          ]);
        }),
      ),
    );
  }
}

// ---- delete account -----------------------------------------------------------------------------------------------------

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  OtpChallenge? _challenge;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() { _busy = true; _error = null; });
    try {
      final c = await NativeScope.of(context).gymApi.requestDeleteCode();
      if (mounted) setState(() => _challenge = c);
    } catch (e) {
      if (mounted) setState(() => _error = failure(e, 'Could not send the code.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final typed = _confirm.text.trim() == 'DELETE';
    return Scaffold(
      appBar: AppBar(title: const Text('Delete my account')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('What happens', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Text('• Your training log, settings, photo, contact and fitness details are erased from your account.\n'
              '• You are signed out everywhere and can no longer use the app.\n'
              '• Your gym keeps what it must to run its business: your name, phone number, memberships, payments and invoices, attendance and any health forms its staff recorded. Ask the gym if you want those removed.\n'
              '• Your gym can switch the app back on for you later.', style: TextStyle(color: OG.dim, height: 1.5)),
        ])),
        const SizedBox(height: 8),
        if (_challenge == null) ...[
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: OG.red))),
          FilledButton(
            onPressed: _busy ? null : _send,
            style: FilledButton.styleFrom(backgroundColor: OG.red, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send me a code to confirm'),
          ),
        ] else
          _CodeStep(
            challenge: _challenge!, actionLabel: 'Delete my account', danger: true,
            extra: Padding(padding: const EdgeInsets.only(top: 12), child: TextField(
              controller: _confirm, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'Type DELETE to confirm', filled: true, fillColor: OG.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            )),
            onSubmit: (code) async {
              if (!typed) throw ApiException(status: 422, code: 'VALIDATION', message: 'Type DELETE to confirm.');
              await sc.gymApi.deleteAccount(requestId: _challenge!.requestId, otp: code);
              await sc.signOut();
            },
          ),
      ]),
    );
  }
}
