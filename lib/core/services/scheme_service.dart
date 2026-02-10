import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

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
}

class SchemeService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  /// Fetch all schemes from the 'schemes' table
  Future<List<SchemeModel>> getSchemes() async {
    try {
      final response = await _supabase
          .from('schemes')
          .select()
          .order('created_at', ascending: false);

      final data = response as List<dynamic>;
      return data.map((json) => SchemeModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('SchemeService: Error fetching schemes - $e');
      return [];
    }
  }
}
