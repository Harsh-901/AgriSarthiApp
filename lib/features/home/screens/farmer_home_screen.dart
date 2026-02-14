import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/farmer_service.dart';
import '../../../core/services/scheme_service.dart';
import '../../../core/services/application_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/leaf_logo.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/widgets/voice_assistant_button.dart';
import '../../voice/widgets/voice_assistant_overlay.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  int _selectedIndex = 0;
  final FarmerService _farmerService = FarmerService();
  final SchemeService _schemeService = SchemeService();
  final ApplicationService _applicationService = ApplicationService();
  String _farmerName = 'Farmer';
  bool _isLoadingName = true;
  late Future<List<SchemeModel>> _schemesFuture;

  @override
  void initState() {
    super.initState();
    _loadFarmerName();
    _schemesFuture = _schemeService.getSchemes();

    // Wire up voice navigation after first frame (need context for Provider)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupVoiceNavigation();
    });
  }

  /// Set up the voice provider's navigation callback
  void _setupVoiceNavigation() {
    if (!mounted) return;
    final voiceProvider = Provider.of<VoiceProvider>(context, listen: false);
    voiceProvider.onNavigate = _handleVoiceNavigation;
  }

  /// Handle voice-driven navigation — maps backend action to routes
  void _handleVoiceNavigation(String action, Map<String, dynamic>? data) {
    if (!mounted) return;
    debugPrint('FarmerHomeScreen: 🧭 Voice navigation → $action');

    switch (action) {
      case 'show_schemes':
        // Already on home (shows schemes) — just stay
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Here are your eligible schemes'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case 'show_applications':
        context.push(AppRouter.applications);
        break;
      case 'show_profile':
      case 'complete_profile':
        context.push(AppRouter.farmerProfile);
        break;
      case 'show_documents':
        context.push(AppRouter.documentUpload);
        break;
      case 'show_help':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Help section coming soon!'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        break;
      default:
        debugPrint('FarmerHomeScreen: Unknown voice action: $action');
    }
  }

  Future<void> _loadFarmerName() async {
    try {
      final profile = await _farmerService.getFarmerProfile();
      if (profile != null && mounted) {
        setState(() {
          _farmerName = profile.fullName.isNotEmpty
              ? profile.fullName.split(' ').first // Get first name
              : 'Farmer';
          _isLoadingName = false;
        });
      } else {
        setState(() {
          _isLoadingName = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading farmer name: $e');
      if (mounted) {
        setState(() {
          _isLoadingName = false;
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
        context.push(AppRouter.applications);
        break;
      case 2: // Upload Docs
        context.push(AppRouter.documentUpload);
        break;
      case 3: // Videos
        _showComingSoon('Videos');
        break;
      case 4: // Profile
        context.push(AppRouter.farmerProfile);
        break;
    }
  }

  /// Apply for a scheme via Django backend
  Future<void> _applyForScheme(SchemeModel scheme) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Apply for ${scheme.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to apply for this scheme?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (scheme.benefit.isNotEmpty)
              Text(
                'Benefit: ${scheme.benefit}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apply Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Check if Django is authenticated
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isDjangoAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot connect to server. Please check your IP/Network.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 16),
            Text('Submitting application...'),
          ],
        ),
        duration: Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
      ),
    );

    // Call Django API to apply
    final result = await _applicationService.applyToScheme(scheme.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result['success'] == true) {
      final trackingId = result['data']?['tracking_id'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Application submitted! Tracking ID: $trackingId',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => context.push(AppRouter.applications),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to submit application'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        child: Stack(
          children: [
            Column(
              children: [
                // App Bar
                _buildAppBar(authProvider),
    
                // Greeting
                _buildGreeting(),
    
                // Schemes List
                Expanded(
                  child: FutureBuilder<List<SchemeModel>>(
                    future: _schemesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Text('Error loading schemes: ${snapshot.error}'),
                        );
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text('No schemes available at the moment.'),
                        );
                      }
    
                      final schemes = snapshot.data!;
                      return ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: schemes.length,
                        itemBuilder: (context, index) =>
                            _buildSchemeCard(schemes[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
            
            // Voice Assistant Overlay
            const VoiceAssistantOverlay(),
          ],
        ),
      ),
      floatingActionButton: const VoiceAssistantButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
          // Connection Status Indicator
          GestureDetector(
            onTap: () {
              authProvider.syncWithDjango();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Checking connection...')),
              );
            },
            child: Icon(
              authProvider.isDjangoAuthenticated ? Icons.cloud_done : Icons.cloud_off,
              size: 16,
              color: authProvider.isDjangoAuthenticated ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: 8),
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
        child: _isLoadingName
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

  Widget _buildSchemeCard(SchemeModel scheme) {
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
                onPressed: () => _applyForScheme(scheme),
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
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      color: AppColors.surface,
      elevation: 10,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
          _buildNavItem(1, Icons.description_outlined, Icons.description, 'Apps'),
          const SizedBox(width: 48), // Space for FAB
          _buildNavItem(2, Icons.upload_file_outlined, Icons.upload_file, 'Docs'),
          _buildNavItem(4, Icons.person_outline, Icons.person, 'Profile'),
        ],
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
