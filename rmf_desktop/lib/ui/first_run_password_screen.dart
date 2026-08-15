import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../data/settings_repository.dart';
import '../theme/app_theme.dart';

/// Stands between the owner and the app for as long as the account still has
/// the password every copy of this app ships with.
///
/// That password is in the source, and the app holds every payment the gym has
/// ever taken. Suggesting a change is not enough — the machine sits on a
/// counter, and a prompt that can be dismissed is a prompt that is dismissed.
class FirstRunPasswordScreen extends StatefulWidget {
  const FirstRunPasswordScreen({super.key});

  @override
  State<FirstRunPasswordScreen> createState() => _FirstRunPasswordScreenState();
}

class _FirstRunPasswordScreenState extends State<FirstRunPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
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
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    _revealFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthBloc>();
    final settings = context.read<SettingsRepository>();
    final userId = auth.state.user?.id;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final problem = await settings.changePassword(
      userId: userId,
      currentPassword: _current.text,
      newPassword: _next.text,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = problem;
    });

    if (problem == null) auth.add(const AuthPasswordChanged());
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
                    'Choose your password',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This account still has the password the app is installed '
                    'with, which is the same on every copy. Set one of your '
                    'own before going any further — your members’ records '
                    'and every payment you have taken are behind it.',
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
                          controller: _current,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Current password',
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
                              ? 'Enter the password you signed in with'
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
                          child: Text(_saving ? 'Saving…' : 'Save and continue'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () =>
                          context.read<AuthBloc>().add(const AuthSignOutRequested()),
                      child: const Text('Sign out instead'),
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
