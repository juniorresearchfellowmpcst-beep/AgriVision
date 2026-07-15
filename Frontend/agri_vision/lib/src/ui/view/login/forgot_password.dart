import 'package:agri_vision/src/src.dart';
import 'package:flutter/material.dart';

/// Password recovery via a 6-digit OTP.
///
/// Two steps in one page, mirroring the plain-widget style of [SignInPage]
/// (local state + direct [AuthService] calls, no cubit):
///   1. enter email  -> backend emails a code (or returns `debug_otp` in dev)
///   2. enter code + new password -> backend resets it -> back to sign in
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

enum _Step { requestCode, resetPassword }

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();

  _Step _step = _Step.requestCode;
  bool _obscure = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.themeError : AppColors.darkGreen,
        content: Text(message),
      ),
    );
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _toast('Enter a valid email address', error: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await _authService.forgotPassword(email: email);
      if (!mounted) return;

      // Dev convenience: when the backend has no SMTP configured it returns the
      // OTP directly so the flow can be completed without a real inbox.
      final debugOtp = result['debug_otp']?.toString();
      if (debugOtp != null && debugOtp.isNotEmpty) {
        _otpController.text = debugOtp;
        _toast('Dev mode: code $debugOtp (email not configured)');
      } else {
        _toast('If that email exists, a reset code has been sent.');
      }
      setState(() => _step = _Step.resetPassword);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final otp = _otpController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (otp.length != 6) {
      _toast('Enter the 6-digit code', error: true);
      return;
    }
    if (password.length < 6) {
      _toast('Password must be at least 6 characters', error: true);
      return;
    }
    if (password != confirm) {
      _toast('Passwords do not match', error: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.resetPassword(
        email: _emailController.text.trim(),
        otp: otp,
        password: password,
      );
      if (!mounted) return;
      _toast('Password reset. Please sign in.');
      Navigator.of(context).pop();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRequest = _step == _Step.requestCode;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.dark900,
        elevation: 0,
        title: const Text('Reset password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                isRequest ? 'Forgot your password?' : 'Enter your new password',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1F1C),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isRequest
                    ? 'We\'ll send a 6-digit code to your email to verify it\'s you.'
                    : 'Enter the code sent to ${_emailController.text.trim()} and choose a new password.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7A72)),
              ),
              const SizedBox(height: 28),

              if (isRequest) ..._requestStep() else ..._resetStep(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _requestStep() {
    return [
      _label('EMAIL'),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: _fieldDecoration('user@gmail.com'),
      ),
      const SizedBox(height: 28),
      _primaryButton(
        label: _isSubmitting ? 'Sending…' : 'Send reset code',
        onPressed: _isSubmitting ? null : _sendCode,
      ),
    ];
  }

  List<Widget> _resetStep() {
    return [
      _label('6-DIGIT CODE'),
      TextField(
        controller: _otpController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: _fieldDecoration('123456').copyWith(counterText: ''),
      ),
      const SizedBox(height: 18),
      _label('NEW PASSWORD'),
      TextField(
        controller: _passwordController,
        obscureText: _obscure,
        decoration: _fieldDecoration('At least 6 characters').copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF8A958E),
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _label('CONFIRM PASSWORD'),
      TextField(
        controller: _confirmController,
        obscureText: _obscure,
        decoration: _fieldDecoration('Re-enter password'),
      ),
      const SizedBox(height: 28),
      _primaryButton(
        label: _isSubmitting ? 'Resetting…' : 'Reset password',
        onPressed: _isSubmitting ? null : _resetPassword,
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: _isSubmitting ? null : _sendCode,
          child: const Text(
            'Resend code',
            style: TextStyle(color: AppColors.darkGreen, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ];
  }

  // ── Shared styling (kept local to match SignInPage) ────────────────────────

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Color(0xFF6B7A72),
      ),
    ),
  );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE3E6E2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE3E6E2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.darkGreen, width: 1.5),
    ),
  );

  Widget _primaryButton({required String label, VoidCallback? onPressed}) =>
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
}
