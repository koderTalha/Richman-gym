import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController =
      TextEditingController(text: 'admin@richmanfitness.local');
  final _passwordController = TextEditingController();

  /// Hidden by default. The gym's screen sits where members can see it, so
  /// revealing the password has to be a deliberate act.
  bool _obscurePassword = true;

  /// Held as a field rather than built inline: a node created during build
  /// would be replaced on every rebuild and never disposed.
  final _revealFocusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _revealFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
          AuthSignInRequested(
            email: _emailController.text,
            password: _passwordController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final submitting = state.status == AuthStatus.submitting;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Wordmark(),
                    const SizedBox(height: 8),
                    Text('Admin sign in', style: mutedStyleOf(context)),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: context.palette.surfaceRaised,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.palette.border),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                              keyboardType: TextInputType.emailAddress,
                              autofocus: true,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Email is required'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  // Read aloud by screen readers and shown on
                                  // hover; the icon alone does not say what
                                  // pressing it will do.
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  // Keeps Tab going Email → Password → Sign in
                                  // rather than stopping on the eye.
                                  focusNode: _revealFocusNode,
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              obscureText: _obscurePassword,
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Password is required'
                                  : null,
                            ),
                            if (state.error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: context.palette.expiredBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: context.palette.expired
                                          .withValues(alpha: .4)),
                                ),
                                child: Text(
                                  state.error!,
                                  style: TextStyle(
                                      color: context.palette.expired, fontSize: 13),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: submitting ? null : _submit,
                              child:
                                  Text(submitting ? 'Signing in…' : 'Sign in'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Authorised staff only.',
                      style: TextStyle(fontSize: 11, color: context.palette.textHint),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: context.palette.textPrimary,
        ),
        children: [
          const TextSpan(text: 'RICH MAN'),
          TextSpan(
            text: ' FITNESS',
            style: TextStyle(color: context.palette.accent),
          ),
        ],
      ),
    );
  }
}
