import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
<<<<<<< HEAD
=======
import 'package:easy_localization/easy_localization.dart';
>>>>>>> new

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/leaf_logo.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            children: [
              const Spacer(flex: 2),
<<<<<<< HEAD
              
              // Logo and tagline section
              _buildLogoSection(context),
              
              const Spacer(flex: 1),
              
              // Get Started Button
              _buildGetStartedButton(context),
              
=======

              // Logo and tagline section
              _buildLogoSection(context),

              const Spacer(flex: 1),

              // Get Started Button
              _buildGetStartedButton(context),

>>>>>>> new
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Leaf Logo
        const LeafLogo(size: 80),
<<<<<<< HEAD
        
        const SizedBox(height: 24),
        
        // Tagline
        Text(
          'Something for the one who gives us food',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
          ),
=======

        const SizedBox(height: 24),

        // Tagline
        Text(
          'auth.tagline'.tr(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
>>>>>>> new
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGetStartedButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          context.go(AppRouter.farmerLogin);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
<<<<<<< HEAD
          'Get Started',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
=======
          'common.get_started'.tr(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
>>>>>>> new
        ),
      ),
    );
  }
}
