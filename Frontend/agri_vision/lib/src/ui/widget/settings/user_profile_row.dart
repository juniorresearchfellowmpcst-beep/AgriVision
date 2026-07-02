import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Profile row inside the USER PROFILE section card.
/// Shows a dark circular avatar with initials, the user's full name,
/// role + email, and a chevron to navigate to the profile edit screen.
class UserProfileRow extends StatelessWidget {
  const UserProfileRow({
    super.key,
    required this.initials,
    required this.name,
    required this.role,
    required this.email,
    this.onTap,
  });

  final String initials;
  final String name;
  final String role;
  final String email;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          children: [
            // avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary,
              child: Text(
                initials,
                style: AppTextStyle.textMdBold.copyWith(
                  color: AppColors.light100,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // name + role · email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyle.textMdSemibold),
                  const SizedBox(height: 2),
                  RichText(
                    text: TextSpan(
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                      children: [
                        TextSpan(text: '$role · '),
                        TextSpan(
                          text: email,
                          style: AppTextStyle.textSmRegular.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.light900),
          ],
        ),
      ),
    );
  }
}
