import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class VoiceAssistantButton extends StatelessWidget {
  const VoiceAssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<VoiceProvider, AuthProvider>(
      builder: (context, voiceProvider, authProvider, child) {
        final isRecording = voiceProvider.isRecording;
        final isProcessing = voiceProvider.isProcessing;
        final isSpeaking = voiceProvider.isSpeaking;
        final isError = voiceProvider.isError;
        final isDjangoAuthenticated = authProvider.isDjangoAuthenticated;
        final isSyncing = authProvider.isSyncing;

        return GestureDetector(
          onTap: () {
            if (!isDjangoAuthenticated) {
              voiceProvider.clearResponse();
              authProvider.syncWithDjango();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Connecting to backend... Please wait.'),
                  duration: Duration(seconds: 2),
                ),
              );
            } else if (isProcessing || isSyncing) {
              // Allow tap to force reset if stuck
              voiceProvider.forceReset();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reset complete. Try again.'),
                  duration: Duration(seconds: 1),
                ),
              );
            } else if (isError) {
              // Clear error on tap
              voiceProvider.clearResponse();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hold the button to speak'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
          onLongPressStart: (_) {
            if (!isDjangoAuthenticated) {
              authProvider.syncWithDjango();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Connecting to backend... try again in a moment.'),
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            if (isProcessing || isSpeaking) return; // Don't start while busy
            voiceProvider.startRecording();
          },
          onLongPressEnd: (_) {
            if (isRecording) {
              voiceProvider.stopRecording();
            }
          },
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: () {}, // ripple effect
              customBorder: const CircleBorder(),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _getButtonColor(
                    isDjangoAuthenticated: isDjangoAuthenticated,
                    isRecording: isRecording,
                    isProcessing: isProcessing,
                    isSpeaking: isSpeaking,
                    isError: isError,
                    isSyncing: isSyncing,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _getShadowColor(
                        isDjangoAuthenticated: isDjangoAuthenticated,
                        isRecording: isRecording,
                        isError: isError,
                      ).withOpacity(0.3),
                      blurRadius: isRecording ? 16 : 8,
                      spreadRadius: isRecording ? 4 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: _buildButtonContent(
                    isDjangoAuthenticated: isDjangoAuthenticated,
                    isRecording: isRecording,
                    isProcessing: isProcessing,
                    isSpeaking: isSpeaking,
                    isError: isError,
                    isSyncing: isSyncing,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getButtonColor({
    required bool isDjangoAuthenticated,
    required bool isRecording,
    required bool isProcessing,
    required bool isSpeaking,
    required bool isError,
    required bool isSyncing,
  }) {
    if (!isDjangoAuthenticated || isSyncing) {
      return AppColors.primary.withOpacity(0.5);
    }
    if (isError) return AppColors.error;
    if (isRecording) return AppColors.error;
    if (isProcessing) return AppColors.warning;
    if (isSpeaking) return AppColors.primary;
    return AppColors.primary;
  }

  Color _getShadowColor({
    required bool isDjangoAuthenticated,
    required bool isRecording,
    required bool isError,
  }) {
    if (!isDjangoAuthenticated) return Colors.grey;
    if (isError) return AppColors.error;
    if (isRecording) return AppColors.error;
    return AppColors.primary;
  }

  Widget _buildButtonContent({
    required bool isDjangoAuthenticated,
    required bool isRecording,
    required bool isProcessing,
    required bool isSpeaking,
    required bool isError,
    required bool isSyncing,
  }) {
    // Syncing with backend
    if (isSyncing) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 2),
          Text('Syncing', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      );
    }

    // Processing voice
    if (isProcessing) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 2),
          Text('Thinking', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      );
    }

    // Error state — show error icon briefly
    if (isError) {
      return const Icon(Icons.error_outline, color: Colors.white, size: 30);
    }

    // Normal states
    IconData icon;
    if (!isDjangoAuthenticated) {
      icon = Icons.mic_off;
    } else if (isRecording) {
      icon = Icons.mic;
    } else if (isSpeaking) {
      icon = Icons.volume_up;
    } else {
      icon = Icons.mic_none;
    }

    return Icon(icon, color: Colors.white, size: 32);
  }
}
