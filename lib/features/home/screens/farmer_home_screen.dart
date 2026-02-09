import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/farmer_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/leaf_logo.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  int _selectedIndex = 0;
  final FarmerService _farmerService = FarmerService();
  String _farmerName = 'Farmer';
  bool _isLoading = true;

  // Sample scheme data - replace with actual API data
  final List<SchemeData> _schemes = [
    SchemeData(
      name: 'Pradhan Mantri Fasal Bima Yojana',
      benefit: '₹ 2 Lakhs Crop Insurance',
      deadline: '31st March 2024',
      status: SchemeStatus.open,
    ),
    SchemeData(
      name: 'Kisan Credit Card Scheme',
      benefit: '₹ 1.6 Lakhs Loan at 4% Interest',
      deadline: 'Ongoing',
      status: SchemeStatus.eligible,
    ),
    SchemeData(
      name: 'Soil Health Card Scheme',
      benefit: 'Free Soil Testing & Report',
      deadline: '15th April 2024',
      status: SchemeStatus.closingSoon,
    ),
    SchemeData(
      name: 'PM Kisan Samman Nidhi',
      benefit: '₹ 6,000 Annual Direct Support',
      deadline: 'Ongoing',
      status: SchemeStatus.open,
    ),
    SchemeData(
      name: 'National Food Security Mission',
      benefit: 'Subsidies for High-Yield Seeds',
      deadline: '30th June 2024',
      status: SchemeStatus.open,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadFarmerName();
  }

  Future<void> _loadFarmerName() async {
    try {
      final profile = await _farmerService.getFarmerProfile();
      if (profile != null && mounted) {
        setState(() {
          _farmerName = profile.fullName.isNotEmpty
              ? profile.fullName.split(' ').first // Get first name
              : 'Farmer';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading farmer name: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Handle navigation based on index
    switch (index) {
      case 0: // Home - already here
        break;
      case 1: // Applications
        _showComingSoon('Applications');
        break;
      case 2: // Upload Docs
        context.push(AppRouter.documentUpload);
        break;
      case 3: // Videos
        _showComingSoon('Videos');
        break;
      case 4: // Profile
        _showComingSoon('Profile');
        break;
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature - Coming Soon!'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            _buildAppBar(authProvider),

            // Greeting
            _buildGreeting(),

            // Schemes List
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _schemes.length,
                itemBuilder: (context, index) =>
                    _buildSchemeCard(_schemes[index]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAppBar(AuthProvider authProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Logo
          const LeafLogo(size: 36),
          const Spacer(),
          // Notification icon
          IconButton(
            onPressed: () => _showComingSoon('Notifications'),
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textPrimary,
          ),
          // Mic icon
          IconButton(
            onPressed: () => _showComingSoon('Voice Assistant'),
            icon: const Icon(Icons.mic_none_outlined),
            color: AppColors.textPrimary,
          ),
          // Logout
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            onSelected: (value) async {
              if (value == 'logout') {
                await authProvider.signOut();
                if (mounted) {
                  context.go(AppRouter.welcome);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _isLoading
            ? const SizedBox(
                height: 32,
                width: 200,
                child: LinearProgressIndicator(),
              )
            : Text(
                'Hello, $_farmerName!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
              ),
      ),
    );
  }

  Widget _buildSchemeCard(SchemeData scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scheme Name
          Text(
            scheme.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 12),

          // Benefit Row
          _buildInfoRow('Benefit:', scheme.benefit),
          const SizedBox(height: 8),

          // Deadline Row
          _buildInfoRow('Deadline:', scheme.deadline),
          const SizedBox(height: 8),

          // Status Row with Apply Button
          Row(
            children: [
              Text(
                'Status:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(scheme.status),
              const Spacer(),
              // Apply Button
              ElevatedButton(
                onPressed: () {
                  _showComingSoon('Apply for ${scheme.name}');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(SchemeStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case SchemeStatus.open:
        bgColor = AppColors.primary;
        textColor = Colors.white;
        label = 'Open';
        break;
      case SchemeStatus.eligible:
        bgColor = AppColors.textSecondary.withOpacity(0.15);
        textColor = AppColors.textSecondary;
        label = 'Eligible';
        break;
      case SchemeStatus.closingSoon:
        bgColor = AppColors.warning;
        textColor = Colors.white;
        label = 'Closing Soon';
        break;
      case SchemeStatus.closed:
        bgColor = AppColors.error.withOpacity(0.15);
        textColor = AppColors.error;
        label = 'Closed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
              _buildNavItem(1, Icons.description_outlined, Icons.description,
                  'Applications'),
              _buildNavItem(2, Icons.upload_file_outlined, Icons.upload_file,
                  'Upload Docs'),
              _buildNavItem(3, Icons.play_circle_outline,
                  Icons.play_circle_filled, 'Videos'),
              _buildNavItem(4, Icons.person_outline, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;

    return InkWell(
      onTap: () => _onNavItemTapped(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Data Models
enum SchemeStatus { open, eligible, closingSoon, closed }

class SchemeData {
  final String name;
  final String benefit;
  final String deadline;
  final SchemeStatus status;

  SchemeData({
    required this.name,
    required this.benefit,
    required this.deadline,
    required this.status,
  });
}
