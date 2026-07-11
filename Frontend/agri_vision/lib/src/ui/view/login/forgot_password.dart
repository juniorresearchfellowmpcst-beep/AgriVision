import 'package:agri_vision/src/src.dart';
import 'package:flutter/material.dart';

/// Two-step password recovery:
///   Step 1 — enter the account email, request an OTP.
///   Step 2 — enter the OTP plus a new password, submit the reset.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();

  bool _otpSent = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.themeError : null,
        content: Text(text),
      ),
    );
  }

  Future<void> _handleSendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Please enter your email', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await _authService.forgotPassword(email: email);
      if (!mounted) return;
      setState(() => _otpSent = true);

      final debugOtp = response['debug_otp']?.toString();
      if (debugOtp != null && debugOtp.isNotEmpty) {
        // Backend has no mail server configured (development build).
        _showMessage('Development OTP: $debugOtp');
      } else {
        _showMessage('OTP sent to $email');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleResetPassword() async {
    final otp = _otpController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (otp.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showMessage('Please fill in all the fields', isError: true);
      return;
    }
    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters', isError: true);
      return;
    }
    if (password != confirm) {
      _showMessage('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _authService.resetPassword(
        email: _emailController.text.trim(),
        otp: otp,
        newPassword: password,
      );
      if (!mounted) return;
      _showMessage('Password reset successfully. Please sign in.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
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
  }

  Widget _sectionLabel(String text) {
    return Padding(
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
  }

  Widget _primaryButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Text(
          _isSubmitting ? 'Please wait...' : label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: const Color(0xFF1A1F1C),
        title: const Text(
          'Forgot Password',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: LogoMark(scale: 0.8),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  _otpSent
                      ? 'Enter the OTP sent to your email and choose a new password'
                      : 'Enter your account email and we will send you a one-time password (OTP)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7A72),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // --- Email ---
              _sectionLabel('EMAIL'),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_otpSent,
                decoration: _fieldDecoration('user@gmail.com'),
              ),
              const SizedBox(height: 18),

              if (!_otpSent) ...[
                const SizedBox(height: 12),
                _primaryButton(label: 'Send OTP', onTap: _handleSendOtp),
              ] else ...[
                // --- OTP ---
                _sectionLabel('OTP CODE'),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: _fieldDecoration('6-digit code').copyWith(
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 18),

                // --- New password ---
                _sectionLabel('NEW PASSWORD'),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _fieldDecoration('').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF8A958E),
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // --- Confirm password ---
                _sectionLabel('CONFIRM NEW PASSWORD'),
                TextField(
                  controller: _confirmController,
                  obscureText: _obscurePassword,
                  decoration: _fieldDecoration(''),
                ),
                const SizedBox(height: 30),

                _primaryButton(
                  label: 'Reset Password',
                  onTap: _handleResetPassword,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _isSubmitting ? null : _handleSendOtp,
                    child: const Text(
                      'Resend OTP',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
