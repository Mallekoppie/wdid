/// Helpers for the ordered list of names on a support entry, timer or draft.
///
/// A person is a name, not an entity: names are trimmed, empty values are
/// dropped, and case-insensitive duplicates keep the first spelling and
/// position. The service applies the same rules, so the client's optimistic
/// view agrees with what is stored.
library;

List<String> normalizePeople(Iterable<String> names) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in names) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) result.add(name);
  }
  return result;
}

/// The display form of several names, in the order they were chosen.
String peopleLabel(Iterable<String> names) => names.join(', ');
