import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
<<<<<<< HEAD
=======
import 'translation_service.dart';
>>>>>>> new

enum SchemeStatus { open, eligible, closingSoon, closed }

class SchemeModel {
  final String id;
  final String name;
  final String benefit;
  final String deadline;
  final SchemeStatus status;
  final String? description;

  SchemeModel({
    required this.id,
    required this.name,
    required this.benefit,
    required this.deadline,
    required this.status,
    this.description,
  });

  factory SchemeModel.fromJson(Map<String, dynamic> json) {
    // Map status string from DB to Enum
    SchemeStatus status = SchemeStatus.open;
    String statusStr = (json['status'] ?? 'open').toString().toLowerCase();

    if (statusStr.contains('eligible')) {
      status = SchemeStatus.eligible;
    } else if (statusStr.contains('closing')) {
      status = SchemeStatus.closingSoon;
    } else if (statusStr.contains('closed')) {
      status = SchemeStatus.closed;
    }

    return SchemeModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown Scheme',
      // Map 'benefit' or 'description' from DB
      benefit: json['benefit'] ?? json['description'] ?? 'View details',
      deadline: json['deadline'] ?? 'Ongoing',
      status: status,
      description: json['description'],
    );
  }
<<<<<<< HEAD
=======

  SchemeModel copyWith({
    String? id,
    String? name,
    String? benefit,
    String? deadline,
    SchemeStatus? status,
    String? description,
  }) {
    return SchemeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      benefit: benefit ?? this.benefit,
      deadline: deadline ?? this.deadline,
      status: status ?? this.status,
      description: description ?? this.description,
    );
  }
>>>>>>> new
}

class SchemeService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  /// Fetch all schemes from the 'schemes' table
<<<<<<< HEAD
  Future<List<SchemeModel>> getSchemes() async {
=======
  Future<List<SchemeModel>> getSchemes({String? languageCode}) async {
>>>>>>> new
    try {
      final response = await _supabase
          .from('schemes')
          .select()
          .order('created_at', ascending: false);

      final data = response as List<dynamic>;
<<<<<<< HEAD
      return data.map((json) => SchemeModel.fromJson(json)).toList();
=======
      final schemes = data.map((json) => SchemeModel.fromJson(json)).toList();

      // If language is provided and not English, translate dynamic content
      if (languageCode != null &&
          languageCode.isNotEmpty &&
          languageCode != 'en') {
        try {
          final translatedSchemes = await Future.wait(
            schemes.map((scheme) async {
              // Translate visible fields
              final tName =
                  await TranslationService.translate(scheme.name, languageCode);
              final tBenefit = await TranslationService.translate(
                  scheme.benefit, languageCode);

              String? tDesc;
              if (scheme.description != null &&
                  scheme.description!.isNotEmpty) {
                tDesc = await TranslationService.translate(
                    scheme.description!, languageCode);
              }

              return scheme.copyWith(
                name: tName,
                benefit: tBenefit,
                description: tDesc,
              );
            }),
          );
          return translatedSchemes;
        } catch (e) {
          debugPrint('Translation error: $e');
          // Return original schemes if translation fails
          return schemes;
        }
      }

      return schemes;
>>>>>>> new
    } catch (e) {
      debugPrint('SchemeService: Error fetching schemes - $e');
      return [];
    }
  }
}
