// Flat directory of every named person Jarvis knows about on the email side.
// Mirrors the names in `functions/context/user_context.md` — keep the two in
// sync when the team changes. The Settings screen iterates this list so the
// user can map each name to a device contact (→ phone number), which the
// email task sheet then uses for one-tap dialling.
//
// NOTE: the `name` field is the canonical lookup key — it must match the
// exact spelling Jarvis uses in `delegate_to` on tasks. `key()` lowercases
// it for the contact_map Firestore document.

class KnownPerson {
  final String name;
  final String role;
  final bool isBoss;

  const KnownPerson({
    required this.name,
    required this.role,
    this.isBoss = false,
  });

  String get key => name.trim().toLowerCase();
}

class PeopleDirectory {
  // Bosses first so the Settings screen shows them at the top.
  static const List<KnownPerson> bosses = <KnownPerson>[
    KnownPerson(
      name: 'Ravi Ramanathan',
      role: 'Regional Head, Western Region (Mumbai)',
      isBoss: true,
    ),
    KnownPerson(
      name: 'Micheal Angre',
      role: 'CPSD Division Head (all-India)',
      isBoss: true,
    ),
    KnownPerson(
      name: 'Mangesh Raje',
      role: 'All India Revamp Head',
      isBoss: true,
    ),
  ];

  static const List<KnownPerson> subordinates = <KnownPerson>[
    KnownPerson(
      name: 'Harshit Laad',
      role: 'Revamp Sales Head, Indore',
    ),
    KnownPerson(
      name: 'Ankit Hetawal',
      role: 'AMC Sales Head, Indore',
    ),
    KnownPerson(
      name: 'Kaushal Kadam',
      role: 'GET — AMC Support, Indore',
    ),
    KnownPerson(
      name: 'Prateek Sen',
      role: 'Service Delivery Head, Bhopal',
    ),
    KnownPerson(
      name: 'Hemanth Rathore',
      role: 'Service Engineer, Indore',
    ),
    KnownPerson(
      name: 'Sawan Chauhan',
      role: 'Service Engineer, Indore',
    ),
    KnownPerson(
      name: 'Vinay Nikhade',
      role: 'Commercial Team, Indore',
    ),
  ];

  static List<KnownPerson> get all => [...bosses, ...subordinates];

  /// Case-insensitive lookup by the exact name Jarvis uses on a task.
  static KnownPerson? findByName(String? name) {
    if (name == null) return null;
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final p in all) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// Normalise a name to the contact_map document key.
  static String keyOf(String name) => name.trim().toLowerCase();
}
