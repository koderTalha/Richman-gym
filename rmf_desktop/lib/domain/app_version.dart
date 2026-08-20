/// A released version of the app, as both `pubspec.yaml` and the GitHub release
/// tags express it.
///
/// Comparison is numeric per component, which is the whole reason this exists:
/// compared as text, "1.0.10" sorts *below* "1.0.9" and the tenth patch release
/// would never be offered to anybody.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, [this.patch = 0]);

  final int major;
  final int minor;
  final int patch;

  /// Parses "1.2.3", the "v1.2.3" form the release tags use, and the "1.2.3+4"
  /// form pubspec uses. Returns null for anything else.
  ///
  /// Deliberately strict. This drives a decision to download and execute an
  /// installer, so a string nobody anticipated must read as "no update", never
  /// as a version that happens to sort high.
  static final _digits = RegExp(r'^\d{1,6}$');

  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;

    var text = raw.trim();
    if (text.isEmpty) return null;

    // Release tags are written v1.2.3.
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }

    // pubspec carries a build number after '+', which says nothing about
    // whether one release is newer than another.
    final plus = text.indexOf('+');
    if (plus != -1) text = text.substring(0, plus);

    // A pre-release suffix is refused rather than ignored: treating "1.2.0-rc1"
    // as 1.2.0 would let a release candidate that was published by mistake
    // install itself on the gym's computer.
    if (text.contains('-')) return null;

    final parts = text.split('.');
    if (parts.length < 2 || parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      // int.parse would accept "+1", "-1" and " 1"; a version component is
      // digits and nothing else.
      if (!_digits.hasMatch(part)) return null;
      numbers.add(int.parse(part));
    }

    return AppVersion(
      numbers[0],
      numbers[1],
      numbers.length == 3 ? numbers[2] : 0,
    );
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}
