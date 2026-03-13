// Pure Dart utility — no Flutter imports required.
// Mirrors the logic of the pg function evaluate_restaurant_schedules().

class BusinessHoursHelper {
  static const List<String> _dayKeys = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static const Map<String, String> _dayLabels = {
    'monday': 'lunes',
    'tuesday': 'martes',
    'wednesday': 'miércoles',
    'thursday': 'jueves',
    'friday': 'viernes',
    'saturday': 'sábado',
    'sunday': 'domingo',
  };

  // ─── Time helpers ─────────────────────────────────────────

  /// Parses "HH:MM" (24-hour) into a Duration from midnight.
  static Duration _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]));
  }

  /// Formats a Duration from midnight back to "HH:MM".
  static String _formatTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Current local time as Duration from midnight.
  /// v1: Uses UTC-6 fixed offset (approximate for America/Mexico_City).
  /// When the 'timezone' package is added, replace with proper tz lookup.
  static Duration _nowDuration(String tz) {
    // UTC-6 standard offset for Mexico City (covers most of the year).
    // CDT (UTC-5) applies May–Oct, a ≤60 min difference, acceptable for v1.
    final nowUtc = DateTime.now().toUtc();
    final nowLocal = nowUtc.subtract(const Duration(hours: 6));
    return Duration(hours: nowLocal.hour, minutes: nowLocal.minute);
  }

  /// Returns the day key ('monday', 'tuesday', …) for right now.
  static String _currentDayKey(String tz) {
    final nowUtc = DateTime.now().toUtc();
    final nowLocal = nowUtc.subtract(const Duration(hours: 6));
    // DateTime.weekday: 1=Monday … 7=Sunday
    return _dayKeys[nowLocal.weekday - 1];
  }

  // ─── Public API ───────────────────────────────────────────

  /// Returns true if the restaurant should currently be open per its schedule.
  /// Returns false if [hours] is null or if the current day/time is outside hours.
  static bool isCurrentlyOpen(Map<String, dynamic>? hours, String tz) {
    if (hours == null) return false;
    final dayKey = _currentDayKey(tz);
    final day = hours[dayKey] as Map<String, dynamic>?;
    if (day == null) return false;
    if (day['enabled'] != true) return false;
    final nowD  = _nowDuration(tz);
    final openD = _parseTime(day['open'] as String);
    final closD = _parseTime(day['close'] as String);
    return nowD >= openD && nowD < closD;
  }

  /// Returns a human-readable label for the next relevant schedule event.
  ///
  /// Examples:
  ///   "Abierto · Cierra a las 21:00"
  ///   "Cerrado · Abre hoy a las 09:00"
  ///   "Cerrado · Abre el lunes a las 09:00"
  ///   "Sin días disponibles esta semana"
  static String? nextEventLabel(Map<String, dynamic>? hours, String tz) {
    if (hours == null) return null;
    final nowD   = _nowDuration(tz);
    final todayI = _currentDayIndex(tz);
    final todayKey  = _dayKeys[todayI];
    final todayData = hours[todayKey] as Map<String, dynamic>?;

    if (todayData != null && todayData['enabled'] == true) {
      final openD = _parseTime(todayData['open'] as String);
      final closD = _parseTime(todayData['close'] as String);
      if (nowD >= openD && nowD < closD) {
        return 'Abierto · Cierra a las ${_formatTime(closD)}';
      }
      if (nowD < openD) {
        return 'Cerrado · Abre hoy a las ${_formatTime(openD)}';
      }
    }

    // Look forward up to 7 days for the next open day
    for (int i = 1; i <= 7; i++) {
      final key  = _dayKeys[(todayI + i) % 7];
      final data = hours[key] as Map<String, dynamic>?;
      if (data != null && data['enabled'] == true) {
        final openD = _parseTime(data['open'] as String);
        final label = i == 1 ? 'mañana' : 'el ${_dayLabels[key]}';
        return 'Cerrado · Abre $label a las ${_formatTime(openD)}';
      }
    }

    return 'Sin días disponibles esta semana';
  }

  /// Returns the index (0=Mon) of the current local weekday.
  static int _currentDayIndex(String tz) {
    final nowUtc   = DateTime.now().toUtc();
    final nowLocal = nowUtc.subtract(const Duration(hours: 6));
    return nowLocal.weekday - 1; // 1=Mon → 0-based
  }

  /// Returns a default schedule map with all days enabled, 09:00–21:00.
  static Map<String, dynamic> defaultSchedule() {
    return {
      for (final key in _dayKeys)
        key: {'enabled': true, 'open': '09:00', 'close': '21:00'},
    };
  }

  /// Returns the localized day label for a key (e.g. 'monday' → 'lunes').
  static String dayLabel(String key) => _dayLabels[key] ?? key;

  /// Returns the ordered list of day keys starting from Monday.
  static List<String> get orderedDayKeys => List.unmodifiable(_dayKeys);
}
