import 'package:add_2_calendar/add_2_calendar.dart';

/// Zero-permission calendar integration.
///
/// DueToday never declares READ_CALENDAR / WRITE_CALENDAR. Instead,
/// add_2_calendar fires `Intent.ACTION_INSERT` on `CalendarContract.Events`,
/// which opens the user's own calendar app (Google, Samsung, ...) with the
/// fields pre-filled. The user confirms and saves there; we never touch the
/// Calendar ContentProvider directly. Do not replace this with a plugin that
/// writes events itself (e.g. device_calendar): that requires dangerous
/// runtime permissions and breaks the CI permission check.
class CalendarService {
  CalendarService._();

  static const Duration eventLength = Duration(hours: 1);

  /// Builds the event the calendar app will be pre-filled with.
  static Event buildEvent({
    required String courseCode,
    required String title,
    required DateTime dueDate,
    String? notes,
  }) {
    return Event(
      title: '[$courseCode] $title',
      description: notes ?? 'Imported via DueToday assignment tracker.',
      startDate: dueDate,
      endDate: dueDate.add(eventLength),
      allDay: false,
    );
  }

  /// Opens the device calendar's "new event" screen. Returns true when the
  /// calendar app was launched (not necessarily when the user saved).
  static Future<bool> addAssignmentToDeviceCalendar({
    required String courseCode,
    required String title,
    required DateTime dueDate,
    String? notes,
  }) async {
    final Event event = buildEvent(
      courseCode: courseCode,
      title: title,
      dueDate: dueDate,
      notes: notes,
    );
    // Fires native Android Intent: Intent.ACTION_INSERT (CalendarContract.Events)
    return await Add2Calendar.addEvent2Cal(event);
  }
}
