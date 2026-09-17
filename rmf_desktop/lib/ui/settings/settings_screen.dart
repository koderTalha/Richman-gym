import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/settings_bloc.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../domain/money.dart';
import '../../domain/reminder_schedule.dart';
import '../../services/historical_pricing_review.dart';
import '../../theme/app_theme.dart';
import 'backup_card.dart';
import 'delete_members_card.dart';
import 'historical_review_screen.dart';
import 'plan_price_change_dialog.dart';
import 'update_card.dart';

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
                Text('Settings',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textPrimary)),
                const SizedBox(height: 20),
                _GymInfoCard(settings: state.settings!),
                const SizedBox(height: 16),
                const _AccountCard(),
                const SizedBox(height: 16),
                _WhatsAppCard(settings: state.settings!, state: state),
                const SizedBox(height: 16),
                _ReminderCard(settings: state.settings!),
                const SizedBox(height: 16),
                _PlansCard(plans: state.plans),
                const SizedBox(height: 16),
                _HistoricalReviewCard(
                  card: ({required title, subtitle, required child}) =>
                      _Card(title: title, subtitle: subtitle, child: child),
                ),
                const SizedBox(height: 16),
                BackupCard(
                  card: ({required title, subtitle, required child}) =>
                      _Card(title: title, subtitle: subtitle, child: child),
                ),
                const SizedBox(height: 16),
                UpdateCard(
                  card: ({required title, subtitle, required child}) =>
                      _Card(title: title, subtitle: subtitle, child: child),
                ),
                const SizedBox(height: 16),
                // Last on the page on purpose: nothing below it to scroll to,
                // so it is never the thing under the cursor on the way to
                // somewhere else.
                DeleteMembersCard(
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
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: mutedStyleOf(context)),
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
  late final _receiptTemplate =
      TextEditingController(text: widget.settings.whatsappReceiptTemplate);
  late final _templateLanguage = TextEditingController(
      text: widget.settings.whatsappReceiptTemplateLanguage);
  late final _welcomeTemplate = TextEditingController(
      text: widget.settings.whatsappWelcomeTemplate ?? '');
  late final _welcomeTemplateLanguage = TextEditingController(
      text: widget.settings.whatsappWelcomeTemplateLanguage);

  bool _showToken = false;

  @override
  void dispose() {
    for (final c in [
      _phoneNumberId,
      _token,
      _businessAccountId,
      _businessNumber,
      _receiptTemplate,
      _templateLanguage,
      _welcomeTemplate,
      _welcomeTemplateLanguage,
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
          // Blank would mean no template at all, which is not a thing a
          // receipt can be sent as. An emptied field falls back to what the
          // gym actually registered.
          receiptTemplate: _blank(_receiptTemplate.text) ?? 'payment_receipt',
          receiptTemplateLanguage: _blank(_templateLanguage.text) ?? 'en',
          // Blank here is a real, valid choice, unlike the receipt template:
          // it means "keep sending the free-text welcome message" rather than
          // "fall back to a default name that may not exist in Meta."
          welcomeTemplate: _blank(_welcomeTemplate.text),
          welcomeTemplateLanguage:
              _blank(_welcomeTemplateLanguage.text) ?? 'en',
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
            segments: [
              const ButtonSegment(
                  value: WhatsAppProviderKind.mock,
                  label: Text('Mock (development)')),
              const ButtonSegment(
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
            Text(
              'Paste the values from Meta Business Suite. Ask whoever owns the '
              'WhatsApp Business account for these.',
              style: mutedStyleOf(context),
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
            const SizedBox(height: 14),
            // A receipt is sent as an approved template, because Meta only
            // accepts free-form messages inside the 24-hour window a member's
            // own message opens. Both values are chosen in WhatsApp Manager,
            // and a mismatch reads as "template does not exist" — so they are
            // editable here rather than compiled in.
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _receiptTemplate,
                  decoration: const InputDecoration(
                    labelText: 'Receipt template name',
                    helperText: 'Exactly as approved in WhatsApp Manager',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _templateLanguage,
                  decoration: const InputDecoration(
                    labelText: 'Template language',
                    helperText: 'en for English, en_US for English (US)',
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // Optional, unlike the receipt template: left blank, the welcome
            // message still goes out as free text exactly as it always has.
            // Filled in, a brand new member — who has essentially never
            // messaged the gym first — actually receives it, since a template
            // is not held to the 24-hour customer-service window.
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _welcomeTemplate,
                  decoration: const InputDecoration(
                    labelText: 'Welcome template name',
                    helperText: 'Optional — blank keeps sending free text',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _welcomeTemplateLanguage,
                  decoration: const InputDecoration(
                    labelText: 'Template language',
                    helperText: 'en for English, en_US for English (US)',
                    isDense: true,
                  ),
                ),
              ),
            ]),
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
                            ? context.palette.paid
                            : context.palette.expired,
                      ),
                    ),
                  ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.surfaceBase,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.palette.border),
              ),
              child: Text(
                'Mock mode records realistic send results, but nothing leaves '
                'this machine. Use it until Meta credentials are available.',
                style: mutedStyleOf(context),
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _mockFails,
              onChanged: (v) => setState(() => _mockFails = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.palette.accent,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Always fail (for testing the retry flow)',
                  style: TextStyle(fontSize: 13, color: context.palette.textPrimary)),
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
                      color: context.palette.expiredBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(state.passwordError!,
                        style: TextStyle(
                            color: context.palette.expired, fontSize: 12)),
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

/// The entry point to `HistoricalReviewScreen`: how many months are waiting
/// for a decision, without the owner having to open the screen to find out.
///
/// Reads its count fresh every time this card builds, the same way
/// `billing_reconciliation.dart`'s startup report does — cheap enough for a
/// once-per-visit read, and correct even the moment after a correction is
/// made elsewhere and this settings screen happens to rebuild.
class _HistoricalReviewCard extends StatelessWidget {
  const _HistoricalReviewCard({required this.card});

  final Widget Function({
    required String title,
    String? subtitle,
    required Widget child,
  }) card;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HistoricalPricingCandidate>>(
      future: detectHistoricalPricingAnomalies(context.read<AppDatabase>()),
      builder: (context, snapshot) {
        final candidates = snapshot.data;
        final count = candidates?.length ?? 0;

        return card(
          title: 'Historical billing review',
          subtitle: 'Months that ended still billing a price the member had, '
              'by then, been moved off. Nothing here is ever changed '
              'automatically.',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  !snapshot.hasData
                      ? 'Checking…'
                      : count == 0
                          ? 'Nothing needs review right now.'
                          : '$count ${count == 1 ? 'month needs' : 'months need'} '
                              'a decision.',
                  style: TextStyle(
                    fontSize: 13,
                    color: count > 0
                        ? context.palette.due
                        : context.palette.textSecondary,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: snapshot.hasData
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const HistoricalReviewScreen(),
                        ))
                    : null,
                child: const Text('Open Review'),
              ),
            ],
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
    final repository = context.read<SettingsRepository>();
    final actorId = context.read<AuthBloc>().state.user?.id;

    final result = await showDialog<PlanSaved>(
      context: context,
      builder: (_) => _PlanDialog(plan: plan),
    );
    if (result == null) return;

    // Re-pricing a plan moves the open, unpaid bill of every active member on
    // it who has no fee of their own. That is the furthest-reaching thing this
    // screen can do, and it used to happen on the same silent button press as
    // fixing a typo in a plan's name.
    if (plan != null && plan.priceMinor != result.priceMinor) {
      final impact = await repository.planPricingImpact(plan.id);
      if (!context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => PlanPriceChangeDialog(
          planName: result.name,
          previousPriceMinor: plan.priceMinor,
          newPriceMinor: result.priceMinor,
          impact: impact,
        ),
      );
      if (confirmed != true) return;
    }

    bloc.add(result.by(actorId));
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
                                    ? context.palette.textPrimary
                                    : context.palette.textHint)),
                        Text(
                          '${plan.durationMonths} '
                          '${plan.durationMonths == 1 ? "month" : "months"}',
                          style: mutedStyleOf(context),
                        ),
                      ],
                    ),
                  ),
                  Text(formatMinorUnits(plan.priceMinor),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.palette.accentText)),
                  const SizedBox(width: 16),
                  Switch(
                    value: plan.isActive,
                    activeThumbColor: context.palette.accent,
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
      backgroundColor: context.palette.surfaceRaised,
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

/// Automatic payment reminders.
///
/// Auto-send is off until the owner turns it on here, and even then it is
/// bounded by the gym's own hours and a per-run cap: this app has no server,
/// so "automatic" means "when the counter machine is opened", and an app
/// reopened after a fortnight shut must not message the whole roster at once.
/// See `domain/reminder_schedule.dart`.
class _ReminderCard extends StatefulWidget {
  const _ReminderCard({required this.settings});

  final GymSetting settings;

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  late bool _autoSend = widget.settings.reminderAutoSend;
  late bool _onDueDate = widget.settings.reminderOnDueDate;
  late int _fromHour = widget.settings.reminderSendFromHour;
  late int _untilHour = widget.settings.reminderSendUntilHour;

  late final _daysBefore =
      TextEditingController(text: widget.settings.reminderDaysBefore);
  late final _daysAfter =
      TextEditingController(text: widget.settings.reminderDaysAfter);
  late final _maxPerRun = TextEditingController(
      text: widget.settings.reminderMaxPerRun.toString());
  late final _template = TextEditingController(
      text: widget.settings.whatsappReminderTemplate ?? '');
  late final _templateLanguage = TextEditingController(
      text: widget.settings.whatsappReminderTemplateLanguage);
  late final _instructions = TextEditingController(
      text: widget.settings.paymentInstructions ?? '');

  @override
  void dispose() {
    for (final c in [
      _daysBefore,
      _daysAfter,
      _maxPerRun,
      _template,
      _templateLanguage,
      _instructions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _blank(String v) => v.trim().isEmpty ? null : v.trim();

  void _save() => context.read<SettingsBloc>().add(
        ReminderSettingsSaved(
          autoSend: _autoSend,
          // Normalised through the same parser the schedule reads them with,
          // so what is stored is always something it can understand.
          daysBefore: formatOffsetDays(parseOffsetDays(_daysBefore.text)),
          onDueDate: _onDueDate,
          daysAfter: formatOffsetDays(parseOffsetDays(_daysAfter.text)),
          sendFromHour: _fromHour,
          sendUntilHour: _untilHour,
          maxPerRun: int.tryParse(_maxPerRun.text.trim()) ?? 25,
          template: _blank(_template.text),
          templateLanguage: _blank(_templateLanguage.text) ?? 'en',
          paymentInstructions: _blank(_instructions.text),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final noTemplate = _template.text.trim().isEmpty;

    return _Card(
      title: 'Payment reminders',
      subtitle: 'Who gets chased for a due payment, and when.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: _autoSend,
            onChanged: (v) => setState(() => _autoSend = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: context.palette.accent,
            title: Text('Send reminders automatically',
                style: TextStyle(
                    fontSize: 13, color: context.palette.textPrimary)),
            subtitle: Text(
              _autoSend
                  ? 'Sent when the app is opened, inside the hours below.'
                  : 'Off — reminders go out only from the Reminders screen.',
              style: mutedStyleOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _daysBefore,
                  decoration: const InputDecoration(
                    labelText: 'Days before due',
                    hintText: 'e.g. 3',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _daysAfter,
                  decoration: const InputDecoration(
                    labelText: 'Days after due',
                    hintText: 'e.g. 3,7',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _onDueDate,
            onChanged: (v) => setState(() => _onDueDate = v ?? true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: context.palette.accent,
            dense: true,
            title: Text('Also remind on the due date itself',
                style: TextStyle(
                    fontSize: 13, color: context.palette.textPrimary)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _fromHour,
                  decoration: const InputDecoration(
                      labelText: 'Send from', isDense: true),
                  items: [
                    for (var h = 0; h < 24; h++)
                      DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                  ],
                  onChanged: (v) => setState(() => _fromHour = v ?? _fromHour),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _untilHour,
                  decoration: const InputDecoration(
                      labelText: 'Send until', isDense: true),
                  items: [
                    for (var h = 0; h < 24; h++)
                      DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                  ],
                  onChanged: (v) =>
                      setState(() => _untilHour = v ?? _untilHour),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _maxPerRun,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Max per run', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('MESSAGE', style: labelStyleOf(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _template,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Approved template name',
                    hintText: 'e.g. payment_reminder',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _templateLanguage,
                  decoration: const InputDecoration(
                      labelText: 'Language', hintText: 'en', isDense: true),
                ),
              ),
            ],
          ),
          if (noTemplate) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.dueBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'No template set, so no reminder can be sent yet. Register one '
                'in Meta Business Manager with five placeholders — member '
                'name, amount due, due date, gym name, payment instructions — '
                'then put its name here.',
                style: TextStyle(fontSize: 12, color: context.palette.due),
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _instructions,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Payment instructions (optional)',
              hintText: 'e.g. Cash at the counter, or Easypaisa 0300-1234567',
              isDense: true,
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save reminder settings'),
            ),
          ),
        ],
      ),
    );
  }

  static String _hourLabel(int hour) =>
      '${hour.toString().padLeft(2, '0')}:00';
}
