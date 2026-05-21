import 'package:flutter/material.dart';

import '../data/job_taxonomy_catalog.dart';

/// Full-screen picker: choose category, then multi-select sub-skills. Returns [JobTaxonomyPickResult].
class JobTaxonomySelectionScreen extends StatefulWidget {
  final bool hindi;
  final JobTaxonomyCatalog catalog;
  final String? initialCategoryId;
  final List<String> initialCompoundSkills;

  const JobTaxonomySelectionScreen({
    super.key,
    required this.hindi,
    required this.catalog,
    this.initialCategoryId,
    this.initialCompoundSkills = const [],
  });

  @override
  State<JobTaxonomySelectionScreen> createState() => _JobTaxonomySelectionScreenState();
}

class _JobTaxonomySelectionScreenState extends State<JobTaxonomySelectionScreen> {
  int _step = 0;
  String _query = '';
  JobTaxonomyCategory? _cat;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _cat = widget.catalog.categoryById(widget.initialCategoryId) ??
        (widget.catalog.allCategories().isNotEmpty ? widget.catalog.allCategories().first : null);
    for (final x in widget.initialCompoundSkills) {
      _picked.add(x);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hi = widget.hindi;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121A2C),
        elevation: 0,
        title: Text(
          _step == 0
              ? (hi ? 'भूमिका चुनें' : 'Choose role')
              : (hi ? 'कौशल चुनें' : 'Select skills'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == 1) {
              setState(() => _step = 0);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_step == 1 && _cat != null)
            TextButton(
              onPressed: () {
                final skills = _picked.where((e) => e.startsWith('${_cat!.id}/')).toList();
                Navigator.pop(
                  context,
                  JobTaxonomyPickResult(categoryId: _cat!.id, compoundSkillIds: skills),
                );
              },
              child: Text(hi ? 'पूर्ण' : 'Done', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _step == 0 ? _buildCategoryStep(hi) : _buildSubStep(hi),
    );
  }

  Widget _buildCategoryStep(bool hi) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: hi ? 'खोजें…' : 'Search roles…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.catalog.sections.length,
            itemBuilder: (context, si) {
              final sec = widget.catalog.sections[si];
              final children = sec.categories
                  .where((c) {
                    final q = _query.trim().toLowerCase();
                    if (q.isEmpty) return true;
                    return c.labelEn.toLowerCase().contains(q) ||
                        c.labelHi.toLowerCase().contains(q) ||
                        c.id.toLowerCase().contains(q);
                  })
                  .toList();
              if (children.isEmpty) return const SizedBox.shrink();
              return ExpansionTile(
                initiallyExpanded: _query.isNotEmpty || si == 0,
                title: Text(sec.labelFor(hi), style: const TextStyle(fontWeight: FontWeight.w600)),
                children: children
                    .map(
                      (c) => ListTile(
                        title: Text(c.labelFor(hi), maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() {
                            _cat = c;
                            _step = 1;
                          });
                        },
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubStep(bool hi) {
    final c = _cat!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          c.labelFor(hi),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF121A2C)),
        ),
        const SizedBox(height: 4),
        Text(
          hi ? 'उम्मीदवार को क्या क्या आना चाहिए' : 'What should the applicant know',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: c.subcategories.map((s) {
            final compound = c.compoundId(s);
            final on = _picked.contains(compound);
            return FilterChip(
              label: Text(s.labelFor(hi), style: const TextStyle(fontSize: 12)),
              selected: on,
              onSelected: (_) {
                setState(() {
                  if (on) {
                    _picked.remove(compound);
                  } else {
                    _picked.add(compound);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
