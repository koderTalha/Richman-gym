import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/app_version.dart';

/// This decides whether the gym's computer downloads and runs an installer, so
/// the interesting cases are the ones where it must say "no".
void main() {
  AppVersion v(String raw) => AppVersion.tryParse(raw)!;

  group('parsing', () {
    test('reads a plain version', () {
      expect(v('1.2.3'), const AppVersion(1, 2, 3));
    });

    test('reads the v-prefixed form the release tags use', () {
      expect(v('v1.2.3'), const AppVersion(1, 2, 3));
      expect(v('V1.2.3'), const AppVersion(1, 2, 3));
    });

    test('ignores the build number pubspec carries', () {
      expect(v('1.1.0+4'), const AppVersion(1, 1, 0));
      expect(v('1.1.0+4'), v('1.1.0'));
    });

    test('a missing patch reads as zero', () {
      expect(v('1.2'), const AppVersion(1, 2, 0));
    });

    test('tolerates surrounding whitespace', () {
      expect(v('  v1.2.3\n'), const AppVersion(1, 2, 3));
    });

    test('refuses a pre-release rather than rounding it down', () {
      // Treating this as 1.2.0 would let a release candidate published by
      // mistake install itself on the gym's computer.
      expect(AppVersion.tryParse('1.2.0-rc1'), isNull);
      expect(AppVersion.tryParse('v2.0.0-beta.1'), isNull);
    });

    test('refuses anything that is not a version', () {
      for (final bad in [
        null,
        '',
        '   ',
        'latest',
        '1',
        '1.2.3.4',
        '1..3',
        '1.x.3',
        'v',
        '-1.2.3',
        '1.2.-3',
        ' 1.2. 3',
        '1.2.3abc',
        '99999999.0.0',
      ]) {
        expect(AppVersion.tryParse(bad), isNull, reason: 'should reject "$bad"');
      }
    });
  });

  group('ordering', () {
    test('the tenth patch beats the ninth', () {
      // The bug this class exists to prevent: as text, "1.0.10" < "1.0.9".
      expect(v('1.0.10').isNewerThan(v('1.0.9')), isTrue);
      expect(v('1.0.9').isNewerThan(v('1.0.10')), isFalse);
    });

    test('major beats minor beats patch', () {
      expect(v('2.0.0').isNewerThan(v('1.99.99')), isTrue);
      expect(v('1.2.0').isNewerThan(v('1.1.99')), isTrue);
      expect(v('1.1.1').isNewerThan(v('1.1.0')), isTrue);
    });

    test('the same version is not newer than itself', () {
      expect(v('1.1.0').isNewerThan(v('1.1.0')), isFalse,
          reason: 'reinstalling what is already there is not an update');
      expect(v('1.1.0+4').isNewerThan(v('1.1.0+3')), isFalse,
          reason: 'a rebuild of the same version is not a new release');
    });

    test('an older release is never offered as an update', () {
      expect(v('1.0.3').isNewerThan(v('1.1.0')), isFalse);
    });

    test('this release is newer than what the gym is running', () {
      expect(v('1.1.0').isNewerThan(v('1.0.3')), isTrue);
    });

    test('sorts a list of releases', () {
      final versions = ['1.0.9', 'v2.0.0', '1.0.10', '1.1.0', '1.0.3']
          .map((r) => v(r))
          .toList()
        ..sort();

      expect(versions.map((x) => x.toString()),
          ['1.0.3', '1.0.9', '1.0.10', '1.1.0', '2.0.0']);
    });
  });
}
