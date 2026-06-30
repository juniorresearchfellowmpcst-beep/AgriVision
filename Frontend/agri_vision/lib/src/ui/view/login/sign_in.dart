import 'package:agri_vision/src/src.dart';
import 'package:flutter/material.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  UserRole _selectedRole = UserRole.operator;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignIn() {
    // TODO: call context.read<AuthCubit>().signIn(
    //   username: _usernameController.text,
    //   password: _passwordController.text,
    //   role: _selectedRole,
    // );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // --- Logo + title ---
              Center(child: LogoMark(scale: 0.8)),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'AgriVision CMS',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1F1C),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Crop health monitoring V1.0',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7A72)),
                ),
              ),
              const SizedBox(height: 28),

              // --- Username ---
              _sectionLabel('USERNAME / EMAIL'),
              TextField(
                controller: _usernameController,
                keyboardType: TextInputType.emailAddress,
                decoration: _fieldDecoration('user@gmail.com'),
              ),
              const SizedBox(height: 18),

              // --- Password ---
              _sectionLabel('PASSWORD'),
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
              const SizedBox(height: 22),
              SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _handleSignIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // --- Divider with "or" ---
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFD9DED9))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'or',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFD9DED9))),
                ],
              ),
              const SizedBox(height: 16),

              // --- Create new account ---
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRouterNames.signUp);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD9DED9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Create New Account',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1F1C),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // --- Footer link ---
              Center(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    children: [
                      const TextSpan(text: 'Need access? '),
                      TextSpan(
                        text: 'Register your organisation',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable role card. Shows a leading icon, title, subtitle,
/// and a check mark + highlighted border/background when selected —
/// matching the AgriDrone GCS design.
class RoleSelectorCard extends StatelessWidget {
  final RoleOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const RoleSelectorCard({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  static const _darkGreen = Color(0xFF1F4D38);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _darkGreen.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _darkGreen : const Color(0xFFE3E6E2),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? _darkGreen : const Color(0xFFEFF1EE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                option.icon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFF5B6760),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1F1C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7A72),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: _darkGreen, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Describes one selectable role on the Sign In screen.
/// Kept as a plain UI-level model (not a domain entity) since it's
/// only used to drive this screen's selector widget.
enum UserRole { operator, fieldEngineer, administrator }

class RoleOption {
  final UserRole role;
  final String title;
  final String subtitle;
  final IconData icon;

  const RoleOption({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  static const List<RoleOption> all = [
    RoleOption(
      role: UserRole.operator,
      title: 'Operator',
      subtitle: 'Fly & monitor missions',
      icon: Icons.person_outline,
    ),
    RoleOption(
      role: UserRole.fieldEngineer,
      title: 'Field Engineer',
      subtitle: 'Configure & maintain drones',
      icon: Icons.build_outlined,
    ),
    RoleOption(
      role: UserRole.administrator,
      title: 'Administrator',
      subtitle: 'Fleet management & reports',
      icon: Icons.shield_outlined,
    ),
  ];
}
