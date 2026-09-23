import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/seed.dart';
import '../data/settings_repository.dart';
import '../theme/app_theme.dart';

/// The way back in for an owner who has forgotten their password.
///
/// There is no email or phone to send a code to, so the proof asked for is
/// the password the app ships with. Pops with true once the password has been
/// replaced, leaving the owner on the sign-in form to use it.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.email = defaultAdminEmail});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _default = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  /// Held as a field rather than built inline: a node created during build
  /// would be replaced on every rebuild and never disposed.
  final _revealFocusNode = FocusNode(skipTraversal: true);

  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _default.dispose();
    _next.dispose();
    _confirm.dispose();
    _revealFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final problem = await context.read<SettingsRepository>().resetPassword(
          email: _email.text,
          defaultPassword: _default.text,
          newPassword: _next.text,
        );

    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Reset your password',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the default password the app was installed with, '
                    'then choose a new password for this account.',
                    style: mutedStyleOf(context),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.palette.surfaceRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _email,
                          decoration:
                              const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Email is required'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _default,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Default password',
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              tooltip:
                                  _obscure ? 'Show passwords' : 'Hide passwords',
                              focusNode: _revealFocusNode,
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          autofocus: true,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter the default password'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _next,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                              labelText: 'New password'),
                          validator: (v) => (v == null || v.length < 8)
                              ? 'At least 8 characters'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                              labelText: 'Confirm new password'),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => v != _next.text
                              ? 'The two passwords do not match'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: context.palette.expiredBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_error!,
                                style: TextStyle(
                                    color: context.palette.expired,
                                    fontSize: 13)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _saving ? null : _submit,
                          child: Text(_saving ? 'Saving…' : 'Reset password'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Back to sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
