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

  String labelFor(bool hindi) =>
      hindi && labelHi.isNotEmpty ? labelHi : JobTaxonomyCatalog.toTitleCase(labelEn);
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

  String labelFor(bool hindi) =>
      hindi && labelHi.isNotEmpty ? labelHi : JobTaxonomyCatalog.toTitleCase(labelEn);

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

  String labelFor(bool hindi) =>
      hindi && labelHi.isNotEmpty ? labelHi : JobTaxonomyCatalog.toTitleCase(labelEn);
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

  /// Dominant taxonomy category from `category/subId` compounds in [skills].
  static String? categoryIdFromSkills(Iterable<String> skills) {
    final counts = <String, int>{};
    for (final s in skills) {
      final slash = s.indexOf('/');
      if (slash <= 0) continue;
      final cat = s.substring(0, slash).trim();
      if (cat.isEmpty) continue;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Role id for labels/API: explicit [jobRole] wins when set (avoids wrong title from stale skills).
  static String effectiveCategoryId({
    required String jobRole,
    required List<String> skills,
  }) {
    if (jobRole.isNotEmpty && jobRole != 'other') return jobRole;
    final fromSkills = categoryIdFromSkills(skills);
    if (fromSkills != null && fromSkills.isNotEmpty) return fromSkills;
    return jobRole;
  }

  /// Keep only skills that belong to [jobRole] (fixes stale skills from prior job type).
  static List<String> skillsMatchingRole(String jobRole, Iterable<String> skills) {
    if (jobRole.isEmpty || jobRole == 'other') return List<String>.from(skills);
    final prefix = '$jobRole/';
    final matched = skills.where((s) => s.startsWith(prefix)).toList();
    return matched.isNotEmpty ? matched : List<String>.from(skills);
  }

  static void invalidateCache() => _cached = null;

  /// Localized job title for owner/seeker UI (custom name → taxonomy → legacy map → title case).
  String displayRoleLabel({
    required String? customRoleName,
    required String jobRole,
    required List<String> skills,
    required bool hindi,
    Map<String, String>? legacyRoleLabels,
  }) {
    if (customRoleName != null && customRoleName.trim().isNotEmpty) {
      return customRoleName.trim();
    }
    final id = effectiveCategoryId(jobRole: jobRole, skills: skills);
    final cat = categoryById(id);
    if (cat != null) return cat.labelFor(hindi);
    if (legacyRoleLabels != null) {
      final localized = legacyRoleLabels[id];
      if (localized != null) return localized;
    }
    if (id.isEmpty) return '';
    return id
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w.length == 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Resolve `category/subId` or plain `subId` (legacy) to a display line.
  String compoundLabel(String compound, bool hindi) {
    final parts = compound.split('/');
    if (parts.length >= 2) {
      final cat = categoryById(parts[0]);
      final sub = cat?.subByLocalId(parts[1]);
      if (sub != null) return sub.labelFor(hindi);
    }
    return hindi ? compound : toTitleCase(compound.replaceAll('/', ' / '));
  }

  List<JobTaxonomyCategory> allCategories() {
    final out = <JobTaxonomyCategory>[];
    for (final s in sections) {
      out.addAll(s.categories);
    }
    return out;
  }

  /// English display: title-case each word (e.g. "hair spa" → "Hair Spa").
  static String toTitleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((word) {
          if (word.contains('/')) {
            return word
                .split('/')
                .map((p) => _titleCaseToken(p))
                .join('/');
          }
          if (word.contains('-')) {
            return word
                .split('-')
                .map((p) => _titleCaseToken(p))
                .join('-');
          }
          return _titleCaseToken(word);
        })
        .join(' ');
  }

  static String _titleCaseToken(String token) {
    if (token.isEmpty) return token;
    if (token.length == 1) return token.toUpperCase();
    return '${token[0].toUpperCase()}${token.substring(1).toLowerCase()}';
  }
}
