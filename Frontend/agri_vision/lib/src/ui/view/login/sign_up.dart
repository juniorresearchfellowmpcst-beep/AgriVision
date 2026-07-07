import 'package:agri_vision/src/src.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _organisationController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _organisationController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the Terms & Conditions')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _authService.signUp(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully. Please sign in.'),
        ),
      );
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyle.textMdRegular.copyWith(color: AppColors.dark100),
      filled: true,
      fillColor: AppColors.light100,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.light700),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.light700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.themeError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.themeError, width: 1.5),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTextStyle.textXsSemibold.copyWith(
          letterSpacing: 0.4,
          color: AppColors.dark300,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Back button ---
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: AppColors.dark900),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: AppSpacing.md),

                // --- Logo + title ---
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.hub_outlined,
                      color: AppColors.light100,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Text(
                    'Create Account',
                    style: AppTextStyle.text2xlBold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: Text(
                    'Register to access AgriDrone GCS',
                    style: AppTextStyle.textSmRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl + AppSpacing.xs),

                // --- Full name ---
                _sectionLabel('FULL NAME'),
                TextFormField(
                  controller: _nameController,
                  style: AppTextStyle.textMdRegular,
                  decoration: _fieldDecoration('Raj Patel'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg + 2),

                // --- Organisation ---
                _sectionLabel('ORGANISATION'),
                TextFormField(
                  controller: _organisationController,
                  style: AppTextStyle.textMdRegular,
                  decoration: _fieldDecoration('AgriDrone Pvt. Ltd.'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Organisation is required'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg + 2),

                // --- Email ---
                _sectionLabel('EMAIL'),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: AppTextStyle.textMdRegular,
                  decoration: _fieldDecoration('raj.patel@agridrone.in'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg + 2),

                // --- Phone ---
                _sectionLabel('PHONE NUMBER'),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: AppTextStyle.textMdRegular,
                  decoration: _fieldDecoration('+91XXXXXXXXXX'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Phone is required'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg + 2),

                // --- Password ---
                _sectionLabel('PASSWORD'),
                Text(
                  "Please Set User Profile Password",
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: AppTextStyle.textMdRegular,
                  decoration: _fieldDecoration('••••••••').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.dark100,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 6) return 'Minimum 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg + 2),

                // --- Confirm password ---
                _sectionLabel('CONFIRM PASSWORD'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  style: AppTextStyle.textMdRegular,
                  decoration: _fieldDecoration('••••••••').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.dark100,
                        size: 20,
                      ),
                      onPressed: () => setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xxl - 2),

                // --- Terms checkbox ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: _agreedToTerms,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (value) =>
                            setState(() => _agreedToTerms = value ?? false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: RichText(
                          text: TextSpan(
                            style: AppTextStyle.textSmRegular.copyWith(
                              color: AppColors.dark300,
                            ),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(
                                text: 'Terms & Conditions',
                                style: AppTextStyle.textSmSemibold.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: AppTextStyle.textSmSemibold.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // --- Register button ---
                AppIconButton(
                  label: _isSubmitting
                      ? 'Creating account...'
                      : 'Create Account',
                  color: AppColors.primary,
                  pressedColor: AppColors.primary6,
                  showBorder: false,
                  textColor: AppColors.light100,
                  pressedTextColor: AppColors.light100,
                  textStyle: AppTextStyle.textLgSemibold,
                  width: double.infinity,
                  height: 52,
                  borderRadius: 14,
                  mainAxisAlignment: MainAxisAlignment.center,
                  onPressed: _isSubmitting ? null : _handleRegister,
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Back to sign in ---
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign In',
                          style: AppTextStyle.textSmBold.copyWith(
                            color: AppColors.primary,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
