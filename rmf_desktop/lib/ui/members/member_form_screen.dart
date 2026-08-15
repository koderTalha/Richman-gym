import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/member_form_bloc.dart';
import '../../data/database.dart';
import '../../data/member_repository.dart';
import '../../domain/money.dart';
import '../../domain/phone.dart';
import '../../theme/app_theme.dart';

class MemberFormScreen extends StatelessWidget {
  const MemberFormScreen({super.key, this.memberId});

  /// Null creates a new member; otherwise edits the existing one.
  final int? memberId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MemberFormBloc(
        repository: context.read<MemberRepository>(),
        memberId: memberId,
      )..add(const MemberFormLoaded()),
      child: _MemberFormView(isEditing: memberId != null),
    );
  }
}

class _MemberFormView extends StatefulWidget {
  const _MemberFormView({required this.isEditing});

  final bool isEditing;

  @override
  State<_MemberFormView> createState() => _MemberFormViewState();
}

class _MemberFormViewState extends State<_MemberFormView> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _emergency = TextEditingController();
  final _fee = TextEditingController();

  int? _planId;
  String? _gender;
  DateTime _joiningDate = DateTime.now();
  bool _prefilled = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _emergency, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Copies the loaded member into the controllers exactly once, so typing is
  /// not clobbered by later state emissions.
  void _prefill(MemberFormState state) {
    if (_prefilled || state.status == MemberFormStatus.loading) return;
    _prefilled = true;

    final existing = state.existing;
    _planId = existing?.membership?.planId ??
        (state.plans.isEmpty ? null : state.plans.first.id);

    if (existing == null) return;

    _name.text = existing.member.fullName;
    _phone.text = existing.member.phoneRaw ?? existing.member.phone;
    _email.text = existing.member.email ?? '';
    _address.text = existing.member.address ?? '';
    _emergency.text = existing.member.emergencyContact ?? '';
    _gender = existing.member.gender;
    _joiningDate = existing.member.joiningDate;

    final override = existing.membership?.feeOverrideMinor;
    if (override != null) {
      _fee.text = fromMinorUnits(override).toStringAsFixed(0);
    }
  }

  Future<void> _pickJoiningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joiningDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _joiningDate = picked);
  }

  void _submit({bool confirmSharedPhone = false}) {
    if (!_formKey.currentState!.validate() || _planId == null) return;

    final feeText = _fee.text.trim();

    context.read<MemberFormBloc>().add(
          MemberFormSubmitted(
            fullName: _name.text.trim(),
            rawPhone: _phone.text.trim(),
            planId: _planId!,
            joiningDate: _joiningDate,
            email: _blankToNull(_email.text),
            gender: _gender,
            address: _blankToNull(_address.text),
            emergencyContact: _blankToNull(_emergency.text),
            feeOverrideMinor:
                feeText.isEmpty ? null : toMinorUnits(double.parse(feeText)),
            confirmSharedPhone: confirmSharedPhone,
          ),
        );
  }

  /// Names whoever already has this number before a second member is put on
  /// it, because the usual reason for a match is a mistyped digit.
  Future<void> _confirmSharedPhone(List<Member> sharing) async {
    final names = sharing
        .map((m) => '${m.fullName} (#${m.memberCode})')
        .join('\n');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.palette.surfaceRaised,
        title: const Text('This number is already in use'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_phone.text.trim()} is registered to:',
              style: mutedStyleOf(context),
            ),
            const SizedBox(height: 8),
            Text(names,
                style: TextStyle(
                    fontSize: 14, color: context.palette.textPrimary)),
            const SizedBox(height: 14),
            Text(
              'Relatives do share a number, and that is fine — everyone on it '
              'gets their own receipts. But check the digits first: a wrong '
              'number sends this member’s receipts to somebody else.',
              style: mutedStyleOf(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Let me check'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Number is correct'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) _submit(confirmSharedPhone: true);
  }

  String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MemberFormBloc, MemberFormState>(
      listener: (context, state) {
        if (state.status == MemberFormStatus.saved) {
          Navigator.of(context).pop(true);
        } else if (state.status == MemberFormStatus.confirmSharedPhone) {
          _confirmSharedPhone(state.sharingPhone);
        }
      },
      builder: (context, state) {
        _prefill(state);

        // The confirmation is a modal dialog, so the form underneath is
        // unreachable while it is up. Leaving the button enabled means
        // dismissing the dialog puts the operator back on a working form
        // rather than a permanently greyed-out one.
        final submitting = state.status == MemberFormStatus.submitting;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: context.palette.surfaceRaised,
            title: Text(widget.isEditing ? 'Edit Member' : 'Add Member'),
          ),
          body: state.status == MemberFormStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!widget.isEditing)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'The member ID is assigned automatically, '
                                  'continuing from the highest existing number.',
                                  style: mutedStyleOf(context),
                                ),
                              ),
                            _FieldRow(children: [
                              TextFormField(
                                controller: _name,
                                decoration: const InputDecoration(
                                    labelText: 'Full name *'),
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    (v == null || v.trim().length < 2)
                                        ? 'Enter the full name'
                                        : null,
                              ),
                              TextFormField(
                                controller: _phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone *',
                                  hintText: '0300-0000001',
                                ),
                                validator: (v) => isValidPhone(v)
                                    ? null
                                    : 'Enter a valid phone number',
                              ),
                            ]),
                            _FieldRow(children: [
                              DropdownButtonFormField<int>(
                                initialValue: _planId,
                                decoration: const InputDecoration(
                                    labelText: 'Membership plan *'),
                                items: state.plans
                                    .map((p) => DropdownMenuItem(
                                          value: p.id,
                                          child: Text(
                                              '${p.name} — ${formatMinorUnits(p.priceMinor)}'),
                                        ))
                                    .toList(),
                                onChanged: (v) => setState(() => _planId = v),
                                validator: (v) =>
                                    v == null ? 'Choose a plan' : null,
                              ),
                              TextFormField(
                                controller: _fee,
                                decoration: const InputDecoration(
                                  labelText: 'Custom fee (optional)',
                                  hintText: 'Leave blank to use the plan price',
                                ),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  final parsed = double.tryParse(v.trim());
                                  if (parsed == null || parsed <= 0) {
                                    return 'Enter a positive amount';
                                  }
                                  return null;
                                },
                              ),
                            ]),
                            _FieldRow(children: [
                              DropdownButtonFormField<String?>(
                                initialValue: _gender,
                                decoration:
                                    const InputDecoration(labelText: 'Gender'),
                                items: [
                                  const DropdownMenuItem(
                                      value: null,
                                      child: Text('Not specified')),
                                  const DropdownMenuItem(
                                      value: 'Male', child: Text('Male')),
                                  const DropdownMenuItem(
                                      value: 'Female', child: Text('Female')),
                                ],
                                onChanged: (v) => setState(() => _gender = v),
                              ),
                              InkWell(
                                onTap: _pickJoiningDate,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                      labelText: 'Joining date *'),
                                  child: Text(
                                    '${_joiningDate.day.toString().padLeft(2, '0')}/'
                                    '${_joiningDate.month.toString().padLeft(2, '0')}/'
                                    '${_joiningDate.year}',
                                    style: TextStyle(
                                        fontSize: 14, color: context.palette.textPrimary),
                                  ),
                                ),
                              ),
                            ]),
                            _FieldRow(children: [
                              TextFormField(
                                controller: _email,
                                decoration:
                                    const InputDecoration(labelText: 'Email'),
                              ),
                              TextFormField(
                                controller: _emergency,
                                decoration: const InputDecoration(
                                    labelText: 'Emergency contact'),
                              ),
                            ]),
                            TextFormField(
                              controller: _address,
                              decoration:
                                  const InputDecoration(labelText: 'Address'),
                            ),
                            const SizedBox(height: 16),
                            if (state.error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.palette.expiredBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(state.error!,
                                    style: TextStyle(
                                        color: context.palette.expired,
                                        fontSize: 13)),
                              ),
                            ],
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                FilledButton(
                                  onPressed: submitting ? null : _submit,
                                  child: Text(submitting
                                      ? 'Saving…'
                                      : widget.isEditing
                                          ? 'Save Changes'
                                          : 'Add Member'),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Two fields side by side with consistent spacing.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i != children.length - 1) const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}
