import 'package:due_today/models/assignment.dart';
import 'package:due_today/models/due_label.dart';
import 'package:due_today/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 27, 15); // Tuesday 3 PM

DueLabel _label(DateTime? due, {bool completed = false}) =>
    DueLabel.of(Assignment(id: 'x', courseCode: 'CSC 3380', title: 'HW', dueAt: due, completed: completed), _now);

void main() {
  group('DueLabel', () {
    test('counts down within 24 hours', () {
      expect(_label(DateTime(2026, 10, 27, 19)).text, 'Due in 4h');
      expect(_label(DateTime(2026, 10, 27, 15, 20)).text, 'Due in 20m');
      expect(_label(DateTime(2026, 10, 28, 9)).text, 'Due in 18h'); // tomorrow, but within 24h
      expect(_label(DateTime(2026, 10, 27, 19)).urgency, Urgency.imminent);
    });

    test('names tomorrow, the weekday, then the date', () {
      expect(_label(DateTime(2026, 10, 28, 23, 59)).text, 'Tomorrow');
      expect(_label(DateTime(2026, 10, 29, 23, 59)).text, 'Thursday');
      expect(_label(DateTime(2026, 11, 2, 23, 59)).text, 'Monday');
      expect(_label(DateTime(2026, 11, 12)).text, 'Nov 12');
      expect(_label(DateTime(2027, 1, 15)).text, 'Jan 15, 2027');
    });

    test('grades urgency', () {
      expect(_label(DateTime(2026, 10, 29, 23, 59)).urgency, Urgency.soon); // < 3 days
      expect(_label(DateTime(2026, 11, 12)).urgency, Urgency.calm);
    });

    test('reports how overdue an item is', () {
      expect(_label(DateTime(2026, 10, 27, 14, 30)).text, 'Overdue');
      expect(_label(DateTime(2026, 10, 27, 9)).text, 'Overdue 6h');
      expect(_label(DateTime(2026, 10, 24, 23, 59)).text, 'Overdue 2d');
      expect(_label(DateTime(2026, 10, 24)).urgency, Urgency.overdue);
    });

    test('done and undated items are calm', () {
      expect(_label(DateTime(2026, 10, 20), completed: true).text, 'Done');
      expect(_label(null).text, 'No date');
      expect(_label(null).urgency, Urgency.calm);
    });
  });

  group('course colors', () {
    test('are stable per course code and case-insensitive', () {
      expect(courseColorIndexFor('CSC 3380'), courseColorIndexFor('csc 3380'));
      expect(courseColorIndexFor('CSC 3380'), inInclusiveRange(0, courseColors.length - 1));
      final indexes = {for (final code in ['CSC 3380', 'CSC 4330', 'MATH 2057', 'ENGL 2000', 'PHYS 2101']) courseColorIndexFor(code)};
      expect(indexes.length, greaterThan(1)); // the hash spreads codes across the palette
    });
  });
}
