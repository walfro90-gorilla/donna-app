import 'package:flutter/material.dart';
import 'package:doa_repartos/core/utils/business_hours_helper.dart';

/// Reusable widget for editing restaurant business hours and enabling
/// automatic online/offline scheduling.
///
/// Usage:
/// ```dart
/// BusinessHoursEditorWidget(
///   initialHours: restaurant.businessHours,
///   initialEnabled: restaurant.businessHoursEnabled,
///   initialTimezone: restaurant.timezone,
///   onChanged: (hours, enabled, tz) {
///     setState(() {
///       _businessHours = hours;
///       _businessHoursEnabled = enabled;
///       _timezone = tz;
///     });
///   },
/// )
/// ```
class BusinessHoursEditorWidget extends StatefulWidget {
  final Map<String, dynamic>? initialHours;
  final bool initialEnabled;
  final String initialTimezone;
  final void Function(
    Map<String, dynamic> hours,
    bool enabled,
    String timezone,
  ) onChanged;

  const BusinessHoursEditorWidget({
    super.key,
    required this.initialHours,
    required this.initialEnabled,
    required this.initialTimezone,
    required this.onChanged,
  });

  @override
  State<BusinessHoursEditorWidget> createState() =>
      _BusinessHoursEditorWidgetState();
}

class _BusinessHoursEditorWidgetState extends State<BusinessHoursEditorWidget> {
  late Map<String, dynamic> _hours;
  late bool _enabled;
  late String _timezone;

  static const List<Map<String, String>> _timezoneOptions = [
    {'value': 'America/Mexico_City', 'label': 'Ciudad de México (CST/CDT)'},
    {'value': 'America/Chihuahua',   'label': 'Chihuahua (MST/MDT)'},
    {'value': 'America/Tijuana',     'label': 'Tijuana (PST/PDT)'},
    {'value': 'America/Cancun',      'label': 'Cancún (EST)'},
  ];

  @override
  void initState() {
    super.initState();
    _enabled  = widget.initialEnabled;
    _timezone = widget.initialTimezone;
    // Deep-copy so we don't mutate the original map
    final source = widget.initialHours ?? BusinessHoursHelper.defaultSchedule();
    _hours = {
      for (final key in BusinessHoursHelper.orderedDayKeys)
        key: Map<String, dynamic>.from(
          (source[key] as Map<String, dynamic>?) ??
              {'enabled': true, 'open': '09:00', 'close': '21:00'},
        ),
    };
  }

  void _notifyParent() {
    widget.onChanged(_hours, _enabled, _timezone);
  }

  void _toggleDayEnabled(String dayKey, bool value) {
    setState(() {
      (_hours[dayKey] as Map<String, dynamic>)['enabled'] = value;
    });
    _notifyParent();
  }

  void _toggleScheduleEnabled(bool value) {
    setState(() => _enabled = value);
    _notifyParent();
  }

  void _setTimezone(String tz) {
    setState(() => _timezone = tz);
    _notifyParent();
  }

  Future<void> _pickTime(String dayKey, String field) async {
    final dayData = _hours[dayKey] as Map<String, dynamic>;
    final current = _parseTimeOfDay(dayData[field] as String);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        (_hours[dayKey] as Map<String, dynamic>)[field] = formatted;
      });
      _notifyParent();
    }
  }

  TimeOfDay _parseTimeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  // ─── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOpen = BusinessHoursHelper.isCurrentlyOpen(_hours, _timezone);
    final previewLabel =
        BusinessHoursHelper.nextEventLabel(_hours, _timezone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: title + master toggle ──────────────────
        Row(
          children: [
            Icon(Icons.schedule_outlined,
                color: colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Horario Automático',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    'El restaurante se abre y cierra solo según este horario',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Switch(
              value: _enabled,
              onChanged: _toggleScheduleEnabled,
              activeColor: colorScheme.primary,
            ),
          ],
        ),

        // ── Live preview chip ───────────────────────────────
        if (_enabled && previewLabel != null) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (isOpen ? Colors.green : Colors.orange)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isOpen ? Colors.green : Colors.orange)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isOpen
                      ? Icons.check_circle_outline
                      : Icons.access_time_outlined,
                  color: isOpen ? Colors.green.shade700 : Colors.orange.shade700,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    previewLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: isOpen
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '(máx. 5 min)',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (!_enabled) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Horario desactivado. El estado se controla manualmente.',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── Day rows ────────────────────────────────────────
        ...BusinessHoursHelper.orderedDayKeys.map((dayKey) {
          final dayData = _hours[dayKey] as Map<String, dynamic>;
          final dayEnabled = dayData['enabled'] == true;
          return _DayRow(
            dayKey: dayKey,
            dayLabel: BusinessHoursHelper.dayLabel(dayKey),
            enabled: dayEnabled,
            openTime: dayData['open'] as String,
            closeTime: dayData['close'] as String,
            onEnabledChanged: (v) => _toggleDayEnabled(dayKey, v),
            onOpenTap: () => _pickTime(dayKey, 'open'),
            onCloseTap: () => _pickTime(dayKey, 'close'),
          );
        }),

        const SizedBox(height: 8),

        // ── Timezone ────────────────────────────────────────
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Zona horaria: ${_timezoneOptions.firstWhere((t) => t['value'] == _timezone, orElse: () => {'label': _timezone})['label']}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            children: [
              DropdownButtonFormField<String>(
                value: _timezone,
                decoration: const InputDecoration(
                  labelText: 'Zona horaria',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _timezoneOptions
                    .map((tz) => DropdownMenuItem<String>(
                          value: tz['value'],
                          child: Text(tz['label']!),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) _setTimezone(v);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Day Row ──────────────────────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  final String dayKey;
  final String dayLabel;
  final bool enabled;
  final String openTime;
  final String closeTime;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onOpenTap;
  final VoidCallback onCloseTap;

  const _DayRow({
    required this.dayKey,
    required this.dayLabel,
    required this.enabled,
    required this.openTime,
    required this.closeTime,
    required this.onEnabledChanged,
    required this.onOpenTap,
    required this.onCloseTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Checkbox
          SizedBox(
            width: 36,
            child: Checkbox(
              value: enabled,
              onChanged: (v) => onEnabledChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: colorScheme.primary,
            ),
          ),
          // Day name
          SizedBox(
            width: 78,
            child: Text(
              dayLabel[0].toUpperCase() + dayLabel.substring(1),
              style: TextStyle(
                fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
                color: enabled ? colorScheme.onSurface : disabledColor,
                fontSize: 13,
              ),
            ),
          ),
          // Open time button
          _TimeButton(
            time: openTime,
            enabled: enabled,
            onTap: onOpenTap,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('–',
                style: TextStyle(
                    color: enabled ? colorScheme.onSurface : disabledColor)),
          ),
          // Close time button
          _TimeButton(
            time: closeTime,
            enabled: enabled,
            onTap: onCloseTap,
          ),
          // Closed chip
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Cerrado',
                  style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String time;
  final bool enabled;
  final VoidCallback onTap;

  const _TimeButton({
    required this.time,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !enabled,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? colorScheme.outline
                  : colorScheme.outline.withValues(alpha: 0.35),
            ),
            borderRadius: BorderRadius.circular(6),
            color: enabled ? null : colorScheme.surfaceContainerHighest,
          ),
          child: Text(
            time,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
