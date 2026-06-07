import 'package:flutter/material.dart';

/// Encodes shift timing in job description (no DB migration).
class ShiftTimingMeta {
  ShiftTimingMeta._();

  static const String _tag = '|||JT_SHIFT|||';

  static String mergeIntoDescription(String userText, ShiftTimingState state) {
    final clean = stripMeta(userText);
    final encoded = '${_tag}${state.encode()}${_tag}';
    if (clean.isEmpty) return encoded;
    return '$encoded\n$clean';
  }

  static String stripMeta(String? text) {
    if (text == null || text.isEmpty) return '';
    final start = text.indexOf(_tag);
    if (start < 0) return text.trim();
    final end = text.indexOf(_tag, start + _tag.length);
    if (end < 0) return text.trim();
    final after = text.substring(end + _tag.length).trim();
    final before = text.substring(0, start).trim();
    return [before, after].where((s) => s.isNotEmpty).join('\n').trim();
  }

  static ShiftTimingState? parseFromDescription(String? text) {
    if (text == null || !text.contains(_tag)) return null;
    final start = text.indexOf(_tag);
    final end = text.indexOf(_tag, start + _tag.length);
    if (end < 0) return null;
    final payload = text.substring(start + _tag.length, end);
    return ShiftTimingState.decode(payload);
  }
}

class ShiftTimingState {
  /// `part_time_freelance` or `hours`
  String mode;
  int fromHour;
  int fromMinute;
  String fromMeridiem;
  int toHour;
  int toMinute;
  String toMeridiem;

  ShiftTimingState({
    required this.mode,
    required this.fromHour,
    required this.fromMinute,
    required this.fromMeridiem,
    required this.toHour,
    required this.toMinute,
    required this.toMeridiem,
  });

  factory ShiftTimingState.defaults() => ShiftTimingState(
        mode: 'hours',
        fromHour: 9,
        fromMinute: 0,
        fromMeridiem: 'AM',
        toHour: 6,
        toMinute: 0,
        toMeridiem: 'PM',
      );

  factory ShiftTimingState.fromLegacyShiftType(String? shiftType) {
    final s = ShiftTimingState.defaults();
    if (shiftType == 'part_time_freelance') {
      s.mode = 'part_time_freelance';
    }
    return s;
  }

  factory ShiftTimingState.fromJob({String? shiftType, String? description}) {
    final parsed = ShiftTimingMeta.parseFromDescription(description);
    if (parsed != null) return parsed;
    return ShiftTimingState.fromLegacyShiftType(shiftType);
  }

  String encode() {
    if (mode == 'part_time_freelance') return 'part_time_freelance';
    return 'hours|$fromHour|$fromMinute|$fromMeridiem|$toHour|$toMinute|$toMeridiem';
  }

  static ShiftTimingState? decode(String payload) {
    if (payload == 'part_time_freelance') {
      return ShiftTimingState(
        mode: 'part_time_freelance',
        fromHour: 9,
        fromMinute: 0,
        fromMeridiem: 'AM',
        toHour: 6,
        toMinute: 0,
        toMeridiem: 'PM',
      );
    }
    final parts = payload.split('|');
    if (parts.length < 7 || parts[0] != 'hours') return null;
    return ShiftTimingState(
      mode: 'hours',
      fromHour: int.tryParse(parts[1]) ?? 9,
      fromMinute: int.tryParse(parts[2]) ?? 0,
      fromMeridiem: parts[3],
      toHour: int.tryParse(parts[4]) ?? 6,
      toMinute: int.tryParse(parts[5]) ?? 0,
      toMeridiem: parts[6],
    );
  }

  String toApiShiftType() =>
      mode == 'part_time_freelance' ? 'part_time_freelance' : 'shift_based';

  String displayLabel(bool hindi) {
    if (mode == 'part_time_freelance') {
      return hindi ? 'पार्ट टाइम (फ्रीलांसिंग)' : 'Part time (freelancing)';
    }
    final f = _formatClock(fromHour, fromMinute, fromMeridiem);
    final t = _formatClock(toHour, toMinute, toMeridiem);
    return hindi ? '$f से $t तक' : '$f to $t';
  }

  static String _formatClock(int h, int m, String mer) {
    final mm = m.toString().padLeft(2, '0');
    return '$h:$mm $mer';
  }
}

class ShiftTimingLabels {
  final bool hindi;
  final String shiftTiming;
  final String partTimeFreelance;
  final String fromLabel;
  final String toLabel;

  const ShiftTimingLabels({
    required this.hindi,
    required this.shiftTiming,
    required this.partTimeFreelance,
    required this.fromLabel,
    required this.toLabel,
  });
}

class ShiftTimingPicker extends StatelessWidget {
  final ShiftTimingLabels labels;
  final ShiftTimingState state;
  final ValueChanged<ShiftTimingState> onChanged;

  const ShiftTimingPicker({
    super.key,
    required this.labels,
    required this.state,
    required this.onChanged,
  });

  static const _hours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  static const _minutes = [0, 15, 30, 45];
  static const _meridiems = ['AM', 'PM'];

  void _patch(ShiftTimingState Function(ShiftTimingState) fn) {
    onChanged(fn(state));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labels.shiftTiming,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        RadioListTile<String>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            labels.partTimeFreelance,
            style: const TextStyle(fontSize: 14),
          ),
          value: 'part_time_freelance',
          groupValue: state.mode,
          activeColor: const Color(0xFF3D3D7B),
          onChanged: (v) => _patch((s) => ShiftTimingState(
                mode: v!,
                fromHour: s.fromHour,
                fromMinute: s.fromMinute,
                fromMeridiem: s.fromMeridiem,
                toHour: s.toHour,
                toMinute: s.toMinute,
                toMeridiem: s.toMeridiem,
              )),
        ),
        RadioListTile<String>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            labels.hindi ? 'समय सीमा चुनें' : 'Choose time slot',
            style: const TextStyle(fontSize: 14),
          ),
          value: 'hours',
          groupValue: state.mode,
          activeColor: const Color(0xFF3D3D7B),
          onChanged: (v) => _patch((s) => ShiftTimingState(
                mode: v!,
                fromHour: s.fromHour,
                fromMinute: s.fromMinute,
                fromMeridiem: s.fromMeridiem,
                toHour: s.toHour,
                toMinute: s.toMinute,
                toMeridiem: s.toMeridiem,
              )),
        ),
        if (state.mode == 'hours') ...[
          const SizedBox(height: 8),
          _TimeRow(
            label: labels.fromLabel,
            hour: state.fromHour,
            minute: state.fromMinute,
            meridiem: state.fromMeridiem,
            onHour: (h) => _patch((s) => ShiftTimingState(
                  mode: s.mode,
                  fromHour: h,
                  fromMinute: s.fromMinute,
                  fromMeridiem: s.fromMeridiem,
                  toHour: s.toHour,
                  toMinute: s.toMinute,
                  toMeridiem: s.toMeridiem,
                )),
            onMinute: (m) => _patch((s) => ShiftTimingState(
                  mode: s.mode,
                  fromHour: s.fromHour,
                  fromMinute: m,
                  fromMeridiem: s.fromMeridiem,
                  toHour: s.toHour,
                  toMinute: s.toMinute,
                  toMeridiem: s.toMeridiem,
                )),
            onMeridiem: (mer) => _patch((s) => ShiftTimingState(
                  mode: s.mode,
                  fromHour: s.fromHour,
                  fromMinute: s.fromMinute,
                  fromMeridiem: mer,
                  toHour: s.toHour,
                  toMinute: s.toMinute,
                  toMeridiem: s.toMeridiem,
                )),
          ),
          const SizedBox(height: 10),
          _TimeRow(
            label: labels.toLabel,
            hour: state.toHour,
            minute: state.toMinute,
            meridiem: state.toMeridiem,
            onHour: (h) => _patch((s) => ShiftTimingState(
                  mode: s.mode,
                  fromHour: s.fromHour,
                  fromMinute: s.fromMinute,
                  fromMeridiem: s.fromMeridiem,
                  toHour: h,
                  toMinute: s.toMinute,
                  toMeridiem: s.toMeridiem,
                )),
            onMinute: (m) => _patch((s) => ShiftTimingState(
                  mode: s.mode,
                  fromHour: s.fromHour,
                  fromMinute: s.fromMinute,
                  fromMeridiem: s.fromMeridiem,
                  toHour: s.toHour,
                  toMinute: m,
                  toMeridiem: s.toMeridiem,
                )),
            onMeridiem: (mer) => _patch((s) => ShiftTimingState(
                  mode: s.mode,
                  fromHour: s.fromHour,
                  fromMinute: s.fromMinute,
                  fromMeridiem: s.fromMeridiem,
                  toHour: s.toHour,
                  toMinute: s.toMinute,
                  toMeridiem: mer,
                )),
          ),
        ],
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final int hour;
  final int minute;
  final String meridiem;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final ValueChanged<String> onMeridiem;

  const _TimeRow({
    required this.label,
    required this.hour,
    required this.minute,
    required this.meridiem,
    required this.onHour,
    required this.onMinute,
    required this.onMeridiem,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121A2C),
            ),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: hour,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: ShiftTimingPicker._hours
                .map((h) => DropdownMenuItem(value: h, child: Text('$h')))
                .toList(),
            onChanged: (v) {
              if (v != null) onHour(v);
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: minute,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: ShiftTimingPicker._minutes
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m.toString().padLeft(2, '0')),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onMinute(v);
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: meridiem,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: ShiftTimingPicker._meridiems
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) {
              if (v != null) onMeridiem(v);
            },
          ),
        ),
      ],
    );
  }
}
