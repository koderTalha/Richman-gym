import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/settings_bloc.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';
import 'backup_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SettingsBloc(context.read<SettingsRepository>())
        ..add(const SettingsRequested()),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (a, b) => b.message != null && a.message != b.message,
      listener: (context, state) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.message!))),
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (state.settings == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Settings',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ink50)),
                const SizedBox(height: 20),
                _GymInfoCard(settings: state.settings!),
                const SizedBox(height: 16),
                const _AccountCard(),
                const SizedBox(height: 16),
                _WhatsAppCard(settings: state.settings!, state: state),
                const SizedBox(height: 16),
                _PlansCard(plans: state.plans),
                const SizedBox(height: 16),
                BackupCard(
                  card: ({required title, subtitle, required child}) =>
                      _Card(title: title, subtitle: subtitle, child: child),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink50)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: kMutedStyle),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _GymInfoCard extends StatefulWidget {
  const _GymInfoCard({required this.settings});
  final GymSetting settings;

  @override
  State<_GymInfoCard> createState() => _GymInfoCardState();
}

class _GymInfoCardState extends State<_GymInfoCard> {
  late final _name = TextEditingController(text: widget.settings.gymName);
  late final _phone = TextEditingController(text: widget.settings.phone ?? '');
  late final _address =
      TextEditingController(text: widget.settings.address ?? '');
  late final _prefix =
      TextEditingController(text: widget.settings.receiptPrefix);
  late final _footer =
      TextEditingController(text: widget.settings.receiptFooterMessage);

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _prefix, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Gym details',
      subtitle: 'These appear on every receipt.',
      child: Column(
        children: [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'Gym name', isDense: true))),
            const SizedBox(width: 14),
            Expanded(
                child: TextField(
                    controller: _phone,
                    decoration: const InputDecoration(
                        labelText: 'Phone', isDense: true))),
          ]),
          const SizedBox(height: 14),
          TextField(
              controller: _address,
              decoration:
                  const InputDecoration(labelText: 'Address', isDense: true)),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _prefix,
                decoration: const InputDecoration(
                    labelText: 'Receipt prefix',
                    helperText: 'e.g. RMF-2026-000184',
                    isDense: true),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: TextField(
                    controller: _footer,
                    decoration: const InputDecoration(
                        labelText: 'Receipt footer message', isDense: true))),
          ]),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => context.read<SettingsBloc>().add(
                    GymInfoSaved(
                      gymName: _name.text.trim(),
                      phone: _blank(_phone.text),
                      address: _blank(_address.text),
                      receiptPrefix: _prefix.text.trim(),
                      receiptFooter: _footer.text.trim(),
                    ),
                  ),
              child: const Text('Save gym details'),
            ),
          ),
        ],
      ),
    );
  }

  String? _blank(String v) => v.trim().isEmpty ? null : v.trim();
}

class _WhatsAppCard extends StatefulWidget {
  const _WhatsAppCard({required this.settings, required this.state});
  final GymSetting settings;
  final SettingsState state;

  @override
  State<_WhatsAppCard> createState() => _WhatsAppCardState();
}

class _WhatsAppCardState extends State<_WhatsAppCard> {
  late WhatsAppProviderKind _provider = widget.settings.whatsappProvider;
  late bool _mockFails = widget.settings.whatsappMockFails;
  late final _phoneNumberId =
      TextEditingController(text: widget.settings.whatsappPhoneNumberId ?? '');
  late final _token =
      TextEditingController(text: widget.settings.whatsappAccessToken ?? '');
  late final _businessAccountId = TextEditingController(
      text: widget.settings.whatsappBusinessAccountId ?? '');
  late final _businessNumber = TextEditingController(
      text: widget.settings.whatsappBusinessNumber ?? '');

  bool _showToken = false;

  @override
  void dispose() {
    for (final c in [
      _phoneNumberId,
      _token,
      _businessAccountId,
      _businessNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _blank(String v) => v.trim().isEmpty ? null : v.trim();

  void _save() => context.read<SettingsBloc>().add(
        WhatsAppSettingsSaved(
          provider: _provider,
          mockFails: _mockFails,
          phoneNumberId: _blank(_phoneNumberId.text),
          accessToken: _blank(_token.text),
          businessAccountId: _blank(_businessAccountId.text),
          businessNumber: _blank(_businessNumber.text),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isMeta = _provider == WhatsAppProviderKind.meta;
    final state = widget.state;

    return _Card(
      title: 'WhatsApp',
      subtitle: 'How receipts are delivered to members.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<WhatsAppProviderKind>(
            segments: const [
              ButtonSegment(
                  value: WhatsAppProviderKind.mock,
                  label: Text('Mock (development)')),
              ButtonSegment(
                  value: WhatsAppProviderKind.meta,
                  label: Text('Meta Cloud API')),
            ],
            selected: {
              _provider == WhatsAppProviderKind.manual
                  ? WhatsAppProviderKind.mock
                  : _provider
            },
            onSelectionChanged: (s) => setState(() => _provider = s.first),
          ),
          const SizedBox(height: 16),
          if (isMeta) ...[
            const Text(
              'Paste the values from Meta Business Suite. Ask whoever owns the '
              'WhatsApp Business account for these.',
              style: kMutedStyle,
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _phoneNumberId,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number ID *',
                    helperText: 'A long number from WhatsApp Manager — '
                        'not the phone number itself',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _businessAccountId,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Business Account ID',
                    helperText: 'Optional — for your reference',
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _token,
              obscureText: !_showToken,
              decoration: InputDecoration(
                labelText: 'Permanent Access Token *',
                helperText: 'Create a System User in Meta Business Settings. '
                    'Tokens from the Graph API Explorer expire in 24 hours.',
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _businessNumber,
              decoration: const InputDecoration(
                labelText: 'Business phone number',
                helperText: 'Optional — the number members see messages from',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: state.testing
                      ? null
                      : () => context.read<SettingsBloc>().add(
                            WhatsAppCredentialsTested(
                              phoneNumberId: _blank(_phoneNumberId.text),
                              accessToken: _blank(_token.text),
                            ),
                          ),
                  icon: state.testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(state.testing ? 'Checking…' : 'Test connection'),
                ),
                const SizedBox(width: 12),
                if (state.testResult != null)
                  Expanded(
                    child: Text(
                      state.testResult!.ok
                          ? 'Connected — ${state.testResult!.summary}'
                          : 'Failed — ${state.testResult!.summary}',
                      style: TextStyle(
                        fontSize: 12,
                        color: state.testResult!.ok
                            ? AppColors.paid
                            : AppColors.expired,
                      ),
                    ),
                  ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ink950,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.ink800),
              ),
              child: const Text(
                'Mock mode records realistic send results, but nothing leaves '
                'this machine. Use it until Meta credentials are available.',
                style: kMutedStyle,
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _mockFails,
              onChanged: (v) => setState(() => _mockFails = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.crimson500,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Always fail (for testing the retry flow)',
                  style: TextStyle(fontSize: 13, color: AppColors.ink50)),
            ),
          ],
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save WhatsApp settings'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the owner replace the seeded password, which otherwise stays as the
/// value baked into the source.
class _AccountCard extends StatefulWidget {
  const _AccountCard();

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final userId = context.read<AuthBloc>().state.user!.id;

    context.read<SettingsBloc>().add(PasswordChangeRequested(
          userId: userId,
          currentPassword: _current.text,
          newPassword: _next.text,
          confirmPassword: _confirm.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listenWhen: (a, b) => b.passwordChanged && !a.passwordChanged,
      listener: (context, state) {
        _current.clear();
        _next.clear();
        _confirm.clear();
      },
      builder: (context, state) {
        final email = context.watch<AuthBloc>().state.user?.email ?? '';

        return _Card(
          title: 'Account',
          subtitle: 'Signed in as $email',
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _current,
                  obscureText: !_show,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_show ? Icons.visibility_off : Icons.visibility,
                          size: 18),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _next,
                      obscureText: !_show,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'At least 8 characters'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _confirm,
                      obscureText: !_show,
                      decoration: const InputDecoration(
                          labelText: 'Confirm new password', isDense: true),
                      validator: (v) =>
                          v != _next.text ? 'Passwords do not match' : null,
                    ),
                  ),
                ]),
                if (state.passwordError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.expiredBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(state.passwordError!,
                        style: const TextStyle(
                            color: AppColors.expired, fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Change password'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlansCard extends StatelessWidget {
  const _PlansCard({required this.plans});

  final List<MembershipPlan> plans;

  Future<void> _edit(BuildContext context, {MembershipPlan? plan}) async {
    final bloc = context.read<SettingsBloc>();
    final result = await showDialog<PlanSaved>(
      context: context,
      builder: (_) => _PlanDialog(plan: plan),
    );
    if (result != null) bloc.add(result);
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Membership plans',
      subtitle: 'Plans are deactivated rather than deleted, so historical '
          'memberships keep resolving.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final plan in plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name,
                            style: TextStyle(
                                fontSize: 13,
                                color: plan.isActive
                                    ? AppColors.ink50
                                    : AppColors.ink600)),
                        Text(
                          '${plan.durationMonths} '
                          '${plan.durationMonths == 1 ? "month" : "months"}',
                          style: kMutedStyle,
                        ),
                      ],
                    ),
                  ),
                  Text(formatMinorUnits(plan.priceMinor),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.crimson400)),
                  const SizedBox(width: 16),
                  Switch(
                    value: plan.isActive,
                    activeThumbColor: AppColors.crimson500,
                    onChanged: (v) => context
                        .read<SettingsBloc>()
                        .add(PlanActiveToggled(plan.id, v)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () => _edit(context, plan: plan),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add plan'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({this.plan});
  final MembershipPlan? plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _months = TextEditingController(
      text: (widget.plan?.durationMonths ?? 1).toString());
  late final _price = TextEditingController(
      text: widget.plan == null
          ? ''
          : fromMinorUnits(widget.plan!.priceMinor).toStringAsFixed(0));

  @override
  void dispose() {
    _name.dispose();
    _months.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.ink900,
      title: Text(widget.plan == null ? 'Add plan' : 'Edit plan'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Plan name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _months,
                    decoration:
                        const InputDecoration(labelText: 'Duration (months)'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final parsed = int.tryParse((v ?? '').trim());
                      return (parsed == null || parsed < 1)
                          ? 'At least 1'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Price (PKR)'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final parsed = double.tryParse((v ?? '').trim());
                      return (parsed == null || parsed <= 0)
                          ? 'Enter a price'
                          : null;
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(PlanSaved(
              id: widget.plan?.id,
              name: _name.text.trim(),
              durationMonths: int.parse(_months.text.trim()),
              priceMinor: toMinorUnits(double.parse(_price.text.trim())),
              isActive: widget.plan?.isActive ?? true,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
