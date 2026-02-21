import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Old profile form screen - now redirects to the new onboarding wizard.
/// Kept for backward compatibility in routing.
class FarmerProfileFormScreen extends StatefulWidget {
  const FarmerProfileFormScreen({super.key});

  @override
  State<FarmerProfileFormScreen> createState() =>
      _FarmerProfileFormScreenState();
}

class _FarmerProfileFormScreenState extends State<FarmerProfileFormScreen> {
  @override
  void initState() {
    super.initState();
    // Redirect to the new onboarding wizard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go(AppRouter.documentUpload);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      ),
    );
  }
}
