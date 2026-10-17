import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/branding_cubit.dart';
import '../theme/app_theme.dart';
import 'reset_password_screen.dart';
import 'widgets/brand_photo.dart';
import 'widgets/rotating_rings.dart';

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

  Future<void> _forgotPassword() async {
    final reset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(email: _emailController.text.trim()),
      ),
    );
    if (reset != true || !mounted) return;

    _passwordController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password reset. Sign in with your new password.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The handoff's split sign-in: brand art on the left, the form on a fixed
    // 460 column on the right. Below 900 the art panel is dropped rather than
    // squeezed — on a narrow window the form is the only part that matters.
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;

          final form = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final submitting = state.status == AuthStatus.submitting;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!wide) ...[
                      const _Wordmark(),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Sign in to manage members and payments.',
                        style: mutedStyleOf(context)),
                    const SizedBox(height: 24),
                    Form(
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
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: submitting ? null : _forgotPassword,
                              child: const Text('Forgot password?'),
                            ),
                          ],
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
          );

          if (!wide) return form;

          return Row(
            children: [
              const Expanded(flex: 2, child: _BrandPanel()),
              SizedBox(width: 460, child: form),
            ],
          );
        },
      ),
    );
  }
}

/// The art half of the sign-in screen.
///
/// A radial wash in the gym's own brand colours with the slowly rotating ring
/// motif from the handoff, the wordmark and the gym's address in the corner.
/// The gym's own photograph sits behind all of it once the owner sets one in
/// Appearance; until then the drawn artwork is the finished look rather than an
/// empty slot.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.2),
          radius: 1.2,
          colors: [
            Color.lerp(palette.surfaceRaised, palette.accent, 0.08)!,
            palette.surfaceBase,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Behind the rings and the wordmark: the photograph is the backdrop,
          // not a layer competing with the brand marks drawn on top of it.
          BlocBuilder<BrandingCubit, BrandingState>(
            buildWhen: (a, b) =>
                a.draft.loginPhotoPath != b.draft.loginPhotoPath,
            builder: (context, state) => BrandPhoto(
              path: state.draft.loginPhotoPath,
              slot: BrandPhotoSlot.login,
            ),
          ),
          const Positioned(
            left: -120,
            bottom: -160,
            child: RotatingRings(size: 620),
          ),
          Positioned(
            left: 40,
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Wordmark(),
                const SizedBox(height: 8),
                Text(
                  'Block Broadway, Paragon City, Lahore',
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
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
