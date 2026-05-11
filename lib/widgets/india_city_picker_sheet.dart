import 'package:flutter/material.dart';

/// Searchable bottom sheet to pick one city from [cities]. Returns selected name or null.
Future<String?> showIndiaCityPickerSheet(
  BuildContext context, {
  required List<String> cities,
  required bool isLoading,
  String? selected,
  required String title,
  required String searchHint,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _IndiaCityPickerBody(
        cities: cities,
        isLoading: isLoading,
        selected: selected,
        title: title,
        searchHint: searchHint,
      );
    },
  );
}

class _IndiaCityPickerBody extends StatefulWidget {
  const _IndiaCityPickerBody({
    required this.cities,
    required this.isLoading,
    required this.selected,
    required this.title,
    required this.searchHint,
  });

  final List<String> cities;
  final bool isLoading;
  final String? selected;
  final String title;
  final String searchHint;

  @override
  State<_IndiaCityPickerBody> createState() => _IndiaCityPickerBodyState();
}

class _IndiaCityPickerBodyState extends State<_IndiaCityPickerBody> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.text.isEmpty
        ? widget.cities
        : widget.cities
            .where((city) => city.toLowerCase().contains(_search.text.toLowerCase()))
            .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF121A2C),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final location = filtered[index];
                      final isSelected = location == widget.selected;
                      return ListTile(
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: isSelected ? const Color(0xFF3D3D7B) : Colors.grey,
                        ),
                        title: Text(
                          location,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? const Color(0xFF3D3D7B) : const Color(0xFF121A2C),
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF3D3D7B)) : null,
                        onTap: () => Navigator.of(context).pop(location),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
