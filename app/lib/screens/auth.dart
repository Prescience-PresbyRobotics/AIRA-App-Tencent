import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/companion.dart';
import '../widgets/ui.dart';

class AuthScreen extends StatefulWidget {
  final AiraController controller;
  final bool recovery;
  const AuthScreen({
    super.key,
    required this.controller,
    this.recovery = false,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool login = true, busy = false, hide = true;
  String note = '';
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> act(String kind) async {
    if (!widget.controller.configured) {
      setState(
        () => note = 'Accounts are not connected yet. You can explore the interface preview below.',
      );
      return;
    }
    if (kind != 'google' && kind != 'reset' && !form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      note = '';
    });
    try {
      final auth = widget.controller.client!.auth;
      final redirect = Uri.base.origin;
      if (kind == 'google') {
        await auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirect);
      } else if (kind == 'reset') {
        if (!email.text.contains('@')) {
          throw const AuthException('Enter your email address first.');
        }
        await auth.resetPasswordForEmail(
          email.text.trim(),
          redirectTo: redirect,
        );
        note = 'If there is an account for this address, a password reset link is on its way.';
      } else if (kind == 'recover') {
        await auth.updateUser(UserAttributes(password: password.text));
        widget.controller.recovering = false;
        await widget.controller.signOut();
        note = 'Password updated. Please sign in again.';
      } else if (login) {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        final result = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: redirect,
        );
        note = result.session != null ? 'Your account is ready.' : 'Check your email to verify your account, then come back and sign in.';
      }
    } catch (e) {
      note = AiraController.cleanError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final wide = MediaQuery.sizeOf(c).width > 850;
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 18,
          runSpacing: 12,
          children: [
            const Text(
              'AIRA',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: AiraColors.forest,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AiraColors.sage,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'Made for everyday connection',
                style: TextStyle(fontSize: 13, color: AiraColors.forest),
              ),
            ),
          ],
        ),
        AiraGap(height: wide ? 44 : 12),
        Center(
          child: Companion(
            size: (wide ? 300 : 200) * (widget.controller.largerText ? .9 : .8),
          ),
        ),
        Text(
          'A little company,\nevery day.',
          style: Theme.of(c).textTheme.headlineLarge
              ?.copyWith(fontSize: wide ? 50 : 36),
        ),
        const AiraGap(height: 18),
        const Text(
          'A little chat. A friendly voice.\nSomeone to share your day with.',
          style: TextStyle(fontSize: 21, height: 1.6, color: AiraColors.muted),
        ),
        const AiraGap(height: 28),
        const Wrap(
          spacing: 9,
          runSpacing: 8,
          children: [
            Icon(
              Icons.favorite_outline_rounded,
              size: 19,
              color: AiraColors.forest,
            ),
            AiraGap(width: 9),
            Text(
              'Your AI companion, at your pace.',
              style: TextStyle(fontSize: 15, color: AiraColors.forest),
            ),
          ],
        ),
      ],
    );
    final card = AiraCard(
      padding: EdgeInsets.all(wide ? 40 : 24),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.recovery
                  ? 'Choose a new password'
                  : login
                  ? 'Welcome to AIRA'
                  : 'Let’s get to know you',
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            const AiraGap(height: 12),
            Text(
              widget.recovery
                  ? 'Use a unique password for your account.'
                  : 'Your space for a conversation that feels familiar.',
              style: Theme.of(c).textTheme.bodyMedium
                  ?.copyWith(color: AiraColors.muted),
            ),
            const AiraGap(height: 28),
            if (!widget.recovery) ...[
              OutlinedButton(
                onPressed: busy ? null : () => act('google'),
                child: const Text(
                  'Continue with Google',
                  textAlign: TextAlign.center,
                ),
              ),
              const AiraPadding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    'or use email',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AiraColors.muted),
                  ),
                ),
              ),
              const Text(
                'Email address',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const AiraGap(height: 8),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(hintText: 'you@example.com'),
                validator: (v) =>
                    v != null &&
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)
                    ? null
                    : 'Please enter a valid email address.',
              ),
              const AiraGap(height: 18),
            ],
            const Text(
              'Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const AiraGap(height: 8),
            TextFormField(
              controller: password,
              obscureText: hide,
              autofillHints: [
                login && !widget.recovery
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              decoration: InputDecoration(
                hintText: login && !widget.recovery
                    ? 'Your password'
                    : 'At least 10 characters',
                suffixIcon: IconButton(
                  tooltip: hide ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => hide = !hide),
                  icon: Icon(
                    hide
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter your password.';
                if ((!login || widget.recovery) && v.length < 10) {
                  return 'Use at least 10 characters.';
                }
                return null;
              },
              onFieldSubmitted: (_) =>
                  act(widget.recovery ? 'recover' : 'email'),
            ),
            if (note.isNotEmpty) ...[const AiraGap(height: 14), Notice(note)],
            const AiraGap(height: 20),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => act(widget.recovery ? 'recover' : 'email'),
              child: Text(
                busy
                    ? 'Please wait…'
                    : widget.recovery
                    ? 'Update password'
                    : login
                    ? 'Log in'
                    : 'Create account',
              ),
            ),
            if (!widget.recovery) ...[
              const AiraGap(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  login = !login;
                  note = '';
                }),
                child: Text(
                  login
                      ? 'New here? Create an account'
                      : 'Already have an account? Log in',
                ),
              ),
              const Divider(height: 32),
              OutlinedButton(
                onPressed: () => widget.controller.startPreview(),
                child: const Text('Explore the interface'),
              ),
              const AiraGap(height: 12),
              const Text(
                'Preview only · No account needed\nSign in for live calls and saved conversations.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AiraColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AiraLayout.of(c).insets(
            EdgeInsets.symmetric(
              horizontal: wide ? 60 : 20,
              vertical: wide ? 52 : 24,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: intro),
                        const AiraGap(width: 84),
                        Expanded(child: card),
                      ],
                    )
                  : Column(
                      children: [
                        intro,
                        const AiraGap(height: 30),
                        card,
                        const AiraGap(height: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
