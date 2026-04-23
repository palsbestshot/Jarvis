// Settings screen — currently houses the People → Phone contact map so the
// email task sheet can one-tap-dial the delegate or boss. Future settings
// (theme, notifications, etc.) can slot in as additional sections below.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import '../../core/constants.dart';
import '../../core/people_directory.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import '../../widgets/call_followup_sheet.dart';

class SettingsScreen extends StatefulWidget {
  final UserProfile user;

  const SettingsScreen({super.key, required this.user});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _svc = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      appBar: AppBar(
        backgroundColor: JarvisTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: JarvisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings', style: JarvisTheme.headingMedium),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // People -> Phone section is Pallav-only (Bosses + Subordinates are
    // his HVAC org chart, baked into PeopleDirectory). Rakhi has no use
    // for it and shouldn't see Pallav's team, so short-circuit her to
    // a simple placeholder.
    if (widget.user.id != AppConstants.pallavUserId) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          JarvisTheme.md,
          JarvisTheme.xl,
          JarvisTheme.md,
          JarvisTheme.xxl,
        ),
        children: [
          Text(
            'Profile',
            style: JarvisTheme.headingMedium
                .copyWith(color: widget.user.accentColor),
          ),
          const SizedBox(height: JarvisTheme.sm),
          Text(
            widget.user.name,
            style: JarvisTheme.displayMedium,
          ),
          const SizedBox(height: JarvisTheme.xs),
          Text(
            'Signed in on this device',
            style: JarvisTheme.bodySmall
                .copyWith(color: JarvisTheme.textMuted),
          ),
          const SizedBox(height: JarvisTheme.lg),
          Text(
            'More settings coming soon.',
            style: JarvisTheme.bodyMedium
                .copyWith(color: JarvisTheme.textSecondary),
          ),
        ],
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _svc.contactMapStream(widget.user.id),
      builder: (ctx, snap) {
        final map = <String, String>{};
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            map[doc.id] = (doc.data()['phone'] ?? '').toString();
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            JarvisTheme.md,
            JarvisTheme.sm,
            JarvisTheme.md,
            JarvisTheme.xxl,
          ),
          children: [
            _sectionHeader('People → Phone'),
            _sectionHelp(
              'Map each person Jarvis knows to a phone from your address book. '
              'Then the email task sheet shows a one-tap call icon when you '
              'need to reach them.',
            ),
            const SizedBox(height: JarvisTheme.sm),
            _subHeader('Bosses'),
            for (final p in PeopleDirectory.bosses)
              _buildPersonTile(p, map[p.key]),
            const SizedBox(height: JarvisTheme.md),
            _subHeader('Team (Subordinates)'),
            for (final p in PeopleDirectory.subordinates)
              _buildPersonTile(p, map[p.key]),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: JarvisTheme.headingMedium
            .copyWith(color: widget.user.accentColor),
      ),
    );
  }

  Widget _subHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: JarvisTheme.sm, bottom: 4),
      child: Text(
        text,
        style: JarvisTheme.labelMedium
            .copyWith(color: JarvisTheme.textSecondary),
      ),
    );
  }

  Widget _sectionHelp(String text) {
    return Text(
      text,
      style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
    );
  }

  Widget _buildPersonTile(KnownPerson person, String? phone) {
    final hasPhone = phone != null && phone.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: widget.user.accentColor.withOpacity(0.2),
            child: Text(
              person.name.isNotEmpty ? person.name[0] : '?',
              style: TextStyle(
                color: widget.user.accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  style: JarvisTheme.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  person.role,
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasPhone) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (hasPhone) ...[
            IconButton(
              tooltip: 'Call',
              icon: Icon(Icons.call, color: widget.user.accentColor),
              onPressed: () => showCallFollowupSheet(
                context: context,
                user: widget.user,
                personName: person.name,
                phone: phone,
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.close, color: JarvisTheme.textMuted, size: 20),
              onPressed: () => _removePhone(person),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () => _pickContactFor(person),
              icon: Icon(Icons.add_link,
                  size: 16, color: widget.user.accentColor),
              label: Text(
                'Link',
                style: TextStyle(color: widget.user.accentColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickContactFor(KnownPerson person) async {
    // 1. Permission
    final granted = await fc.FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Contacts permission denied. Enable it in system settings.')),
      );
      return;
    }
    // 2. Load all contacts with phone numbers. For ~hundreds this is fine.
    final contacts = await fc.FlutterContacts.getContacts(withProperties: true);
    final withPhone = contacts
        .where((c) => c.phones.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayName
          .toLowerCase()
          .compareTo(b.displayName.toLowerCase()));
    if (!mounted) return;
    // 3. Pick one — bottom sheet with search
    final picked = await _showContactPicker(withPhone, person.name);
    if (picked == null) return;
    // 4. If multiple phones, ask which
    String phone;
    if (picked.phones.length == 1) {
      phone = picked.phones.first.number;
    } else {
      final pickedPhone = await _showPhonePicker(picked);
      if (pickedPhone == null) return;
      phone = pickedPhone;
    }
    // 5. Normalise + save
    final clean = phone.replaceAll(RegExp(r'\s+'), '');
    await _svc.setContactPhone(
      userId: widget.user.id,
      personKey: person.key,
      name: person.name,
      phone: clean,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Linked ${person.name} → $clean')),
    );
  }

  Future<fc.Contact?> _showContactPicker(
    List<fc.Contact> contacts,
    String personName,
  ) async {
    String query = '';
    return showModalBottomSheet<fc.Contact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarvisTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final q = query.toLowerCase();
            final filtered = q.isEmpty
                ? contacts
                : contacts
                    .where((c) =>
                        c.displayName.toLowerCase().contains(q) ||
                        c.phones.any((p) =>
                            p.number.replaceAll(' ', '').contains(q)))
                    .toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx2, scrollController) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(ctx2).viewInsets.bottom,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: JarvisTheme.textMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Pick a contact for $personName',
                        style: JarvisTheme.bodyLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        autofocus: false,
                        style: JarvisTheme.bodyMedium,
                        onChanged: (v) => setLocal(() => query = v),
                        decoration: InputDecoration(
                          hintText: 'Search name or number',
                          hintStyle: JarvisTheme.bodyMedium
                              .copyWith(color: JarvisTheme.textMuted),
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: JarvisTheme.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final phoneLabel = c.phones
                                .map((p) => p.number)
                                .join(', ');
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: JarvisTheme.surface2,
                                child: Text(
                                  c.displayName.isNotEmpty
                                      ? c.displayName[0].toUpperCase()
                                      : '?',
                                  style: JarvisTheme.bodySmall,
                                ),
                              ),
                              title: Text(
                                c.displayName,
                                style: JarvisTheme.bodyMedium,
                              ),
                              subtitle: Text(
                                phoneLabel,
                                style: JarvisTheme.bodySmall.copyWith(
                                    color: JarvisTheme.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(ctx2, c),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<String?> _showPhonePicker(fc.Contact contact) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: JarvisTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pick a number for ${contact.displayName}',
                  style: JarvisTheme.bodyLarge
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                for (final p in contact.phones)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.phone),
                    title: Text(p.number),
                    subtitle: Text(p.label.name,
                        style: JarvisTheme.bodySmall
                            .copyWith(color: JarvisTheme.textMuted)),
                    onTap: () => Navigator.pop(ctx, p.number),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _removePhone(KnownPerson person) async {
    await _svc.removeContactPhone(
      userId: widget.user.id,
      personKey: person.key,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unlinked ${person.name}')),
    );
  }

}
