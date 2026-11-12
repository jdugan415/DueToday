import 'package:due_today/models/assignment.dart';
import 'package:due_today/models/course.dart';
import 'package:due_today/services/storage_service.dart';
import 'package:due_today/state/assignment_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('repeat imports preserve saved changes and add only new IDs', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    final store = AssignmentStore(storage);
    addTearDown(store.dispose);
    const course = Course(code: 'CSC 4330');
    final original = Assignment(
      id: 'lab-1',
      courseCode: course.code,
      title: 'Lab 1',
      dueAt: DateTime(2026, 11, 20),
    );
    const newItem = Assignment(
      id: 'lab-2',
      courseCode: 'GENERAL',
      title: 'Lab 2',
    );
    final correctedDeadline = DateTime(2026, 11, 23, 17);

    await store.addAll(course, [original]);
    await store.update(original.copyWith(
      dueAt: correctedDeadline,
      notes: 'Bring the draft',
      completed: true,
      addedToCalendar: true,
    ));
    await store.addAll(course, [original, newItem, newItem]);

    final reloaded = AssignmentStore(storage);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.assignments.map((item) => item.id), ['lab-1', 'lab-2']);
    final saved = reloaded.assignments.first;
    expect(saved.dueAt, correctedDeadline);
    expect(saved.notes, 'Bring the draft');
    expect(saved.completed, isTrue);
    expect(saved.addedToCalendar, isTrue);
    expect(reloaded.assignments.last.courseCode, course.code);
  });
}
