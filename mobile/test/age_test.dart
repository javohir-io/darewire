import 'package:flutter_test/flutter_test.dart';
import 'package:darewire/core/config.dart';

void main() {
  test('minimum age matches the server (16)', () => expect(minAge, 16));

  test('ageOn counts whole years and respects the birthday', () {
    final birth = DateTime(2010, 6, 15);
    expect(ageOn(birth, DateTime(2026, 6, 14)), 15);   // the day before the 16th birthday
    expect(ageOn(birth, DateTime(2026, 6, 15)), 16);   // on it
    expect(ageOn(birth, DateTime(2028, 6, 14)), 17);
    expect(ageOn(birth, DateTime(2028, 6, 15)), 18);
    expect(ageOn(DateTime(2008, 12, 31), DateTime(2026, 1, 1)), 17);   // month before day
    expect(ageOn(DateTime(2008, 2, 29), DateTime(2026, 2, 28)), 17);   // leap day birthdays
  });
}
