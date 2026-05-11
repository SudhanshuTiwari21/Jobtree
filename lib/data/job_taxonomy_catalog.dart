import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One selectable skill under a job category.
@immutable
class JobTaxonomySub {
  final String id;
  final String labelEn;
  final String labelHi;

  const JobTaxonomySub({required this.id, required this.labelEn, required this.labelHi});

  String labelFor(bool hindi) => hindi && labelHi.isNotEmpty ? labelHi : labelEn;
}

/// Job category (maps to `job_role` / seeker `preferred_role`).
@immutable
class JobTaxonomyCategory {
  final String id;
  final String labelEn;
  final String labelHi;
  final List<JobTaxonomySub> subcategories;

  const JobTaxonomyCategory({
    required this.id,
    required this.labelEn,
    required this.labelHi,
    required this.subcategories,
  });

  String labelFor(bool hindi) => hindi && labelHi.isNotEmpty ? labelHi : labelEn;

  /// Stored in API `skills` JSON array.
  String compoundId(JobTaxonomySub sub) => '$id/${sub.id}';

  JobTaxonomySub? subByLocalId(String localId) {
    for (final s in subcategories) {
      if (s.id == localId) return s;
    }
    return null;
  }
}

@immutable
class JobTaxonomySection {
  final String id;
  final String labelEn;
  final String labelHi;
  final List<JobTaxonomyCategory> categories;

  const JobTaxonomySection({
    required this.id,
    required this.labelEn,
    required this.labelHi,
    required this.categories,
  });

  String labelFor(bool hindi) => hindi && labelHi.isNotEmpty ? labelHi : labelEn;
}

@immutable
class JobTaxonomyPickResult {
  final String categoryId;
  final List<String> compoundSkillIds;

  const JobTaxonomyPickResult({required this.categoryId, required this.compoundSkillIds});
}

/// Loads [assets/data/job_taxonomy.json] once.
class JobTaxonomyCatalog {
  JobTaxonomyCatalog._(this.sections);

  final List<JobTaxonomySection> sections;

  static JobTaxonomyCatalog? _cached;

  static Future<JobTaxonomyCatalog> instance() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString('assets/data/job_taxonomy.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    final secList = (map['sections'] as List<dynamic>? ?? []).map((s) {
      final sm = s as Map<String, dynamic>;
      final cats = (sm['categories'] as List<dynamic>? ?? []).map((c) {
        final cm = c as Map<String, dynamic>;
        final subs = (cm['subcategories'] as List<dynamic>? ?? []).map((u) {
          final um = u as Map<String, dynamic>;
          return JobTaxonomySub(
            id: um['id']?.toString() ?? '',
            labelEn: um['labelEn']?.toString() ?? '',
            labelHi: um['labelHi']?.toString() ?? '',
          );
        }).toList();
        return JobTaxonomyCategory(
          id: cm['id']?.toString() ?? '',
          labelEn: cm['labelEn']?.toString() ?? '',
          labelHi: cm['labelHi']?.toString() ?? '',
          subcategories: subs,
        );
      }).toList();
      return JobTaxonomySection(
        id: sm['id']?.toString() ?? '',
        labelEn: sm['labelEn']?.toString() ?? '',
        labelHi: sm['labelHi']?.toString() ?? '',
        categories: cats,
      );
    }).toList();
    _cached = JobTaxonomyCatalog._(secList);
    return _cached!;
  }

  JobTaxonomyCategory? categoryById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final sec in sections) {
      for (final c in sec.categories) {
        if (c.id == id) return c;
      }
    }
    return null;
  }

  String categoryLabel(String? id, bool hindi) => categoryById(id)?.labelFor(hindi) ?? (id ?? '');

  /// Resolve `category/subId` or plain `subId` (legacy) to a display line.
  String compoundLabel(String compound, bool hindi) {
    final parts = compound.split('/');
    if (parts.length >= 2) {
      final cat = categoryById(parts[0]);
      final sub = cat?.subByLocalId(parts[1]);
      if (sub != null) return sub.labelFor(hindi);
    }
    return compound;
  }

  List<JobTaxonomyCategory> allCategories() {
    final out = <JobTaxonomyCategory>[];
    for (final s in sections) {
      out.addAll(s.categories);
    }
    return out;
  }
}
