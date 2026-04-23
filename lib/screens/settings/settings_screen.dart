// Settings screen — currently houses the People → Phone contact map so the
// email task sheet can one-tap-dial the delegate or boss. Future settings
// (theme, notifications, etc.) can slot in as additional sections below.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/people_directory.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/call_followup_sheet.dart';

class SettingsScreen extends StatefulWidget {
  final UserProfile user;

  const SettingsScreen({super.key, required this.user});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _svc = FirestoreService();
  bool _sendingTestPush = false;
  bool _registeringToken = false;
  String? _diagReport;

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
    // a simple placeholder + notification test controls.
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
          const SizedBox(height: JarvisTheme.xl),
          Text(
            'Notifications',
            style: JarvisTheme.headingMedium
                .copyWith(color: widget.user.accentColor),
          ),
          const SizedBox(height: JarvisTheme.sm),
          Text(
            kIsWeb
                ? "Tap Send — you'll see a pink banner appear INSIDE the app "
                  "confirming the push arrived. iOS suppresses the system banner "
                  "while the PWA is open. To test the real home-screen banner: "
                  "tap Send, then IMMEDIATELY press the home button to minimize "
                  "Jarvis. The banner arrives within 5 seconds."
                : "Tap Send to verify pushes land on your home screen. If "
                  "nothing arrives, tap Re-register device to refresh the token.",
            style: JarvisTheme.bodySmall
                .copyWith(color: JarvisTheme.textSecondary),
          ),
          const SizedBox(height: JarvisTheme.md),
          ElevatedButton.icon(
            onPressed: _sendingTestPush ? null : _sendTestPush,
            icon: _sendingTestPush
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  )
                : const Icon(Icons.notifications_active, size: 20),
            label: Text(
              _sendingTestPush ? 'Sending…' : 'Send test notification',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.user.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JarvisTheme.small),
              ),
            ),
          ),
          const SizedBox(height: JarvisTheme.sm),
          OutlinedButton.icon(
            onPressed: _registeringToken ? null : _reRegisterDevice,
            icon: _registeringToken
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.user.accentColor,
                      ),
                    ),
                  )
                : Icon(Icons.refresh,
                    size: 20, color: widget.user.accentColor),
            label: Text(
              _registeringToken
                  ? 'Re-registering…'
                  : 'Re-register this device for push',
              style: TextStyle(color: widget.user.accentColor),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: widget.user.accentColor.withOpacity(0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JarvisTheme.small),
              ),
            ),
          ),
          const SizedBox(height: JarvisTheme.sm),
          Text(
            kIsWeb
                ? 'Web: notification must be added to home screen (PWA) for pushes to appear on iOS.'
                : 'Android: pushes land in the system tray even when the app is closed.',
            style: JarvisTheme.bodySmall
                .copyWith(color: JarvisTheme.textMuted),
          ),
          const SizedBox(height: JarvisTheme.md),
          TextButton.icon(
            onPressed: _showDiagnostic,
            icon: Icon(Icons.bug_report_outlined,
                size: 18, color: JarvisTheme.textMuted),
            label: Text(
              'Show notification diagnostic',
              style: TextStyle(color: JarvisTheme.textMuted),
            ),
          ),
          if (_diagReport != null) ...[
            Container(
              margin: const EdgeInsets.only(top: JarvisTheme.xs),
              padding: const EdgeInsets.all(JarvisTheme.sm),
              decoration: BoxDecoration(
                color: JarvisTheme.surface2,
                borderRadius:
                    BorderRadius.circular(JarvisTheme.small),
                border: Border.all(
                  color: widget.user.accentColor.withOpacity(0.3),
                ),
              ),
              child: SelectableText(
                _diagReport!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: JarvisTheme.textPrimary,
                ),
              ),
            ),
          ],
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

  /// POST to the sendTestPush Cloud Function. The function reads
  /// users/{userId}/device_tokens/{primary,web} and dispatches to
  /// whichever exist. Response body tells us which channels actually
  /// received the push; the snackbar summarises that.
  ///
  /// On Android this ALSO triggers flutter_local_notifications as a
  /// belt-and-braces — so Pallav sees a notification even if FCM is
  /// flaky on his device.
  Future<void> _sendTestPush() async {
    setState(() => _sendingTestPush = true);
    try {
      // Android parallel path: show a local notification immediately so
      // Pallav sees something even if the cloud hop is slow.
      if (!kIsWeb) {
        try {
          await NotificationService().showTestNotification();
        } catch (_) {/* non-fatal */}
      }

      final resp = await http.post(
        Uri.parse(AppConstants.testPushUrl),
        headers: {
          'content-type': 'application/json',
          'x-ingest-secret': AppConstants.ingestSecret,
        },
        body: jsonEncode({'userId': widget.user.id}),
      );
      if (!mounted) return;

      String label;
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final sent = json['sent_to'] as Map<String, dynamic>? ?? {};

        // New detailed shape: sent_to.{primary,web} is an object with
        // exists / has_token / delivered / error / message_id. Summarise
        // into a human-readable status so Rakhi can see exactly what
        // broke (e.g. "token exists but FCM rejected it — dead token").
        String summarise(Map<String, dynamic>? ch, String label) {
          if (ch == null) return '';
          final exists = ch['exists'] == true;
          final hasToken = ch['has_token'] == true;
          final delivered = ch['delivered'] == true;
          final error = ch['error']?.toString();
          if (delivered) return '✓ $label delivered';
          if (!exists) return '$label: no token registered';
          if (!hasToken) return '$label: token field empty';
          if (error != null && error.isNotEmpty) return '$label failed: $error';
          return '$label: unknown state';
        }

        final webCh = sent['web'] as Map<String, dynamic>?;
        final primCh = sent['primary'] as Map<String, dynamic>?;
        final parts = <String>[];
        // Only surface the channel that matches the device running this
        // button — showing "android failed" on Rakhi's iPhone would be
        // confusing.
        if (kIsWeb) {
          parts.add(summarise(webCh, 'web'));
        } else {
          parts.add(summarise(primCh, 'android'));
        }
        label = parts.where((s) => s.isNotEmpty).join(' · ');
        if (label.isEmpty) {
          label =
              'No device registered. Tap "Re-register this device" below first.';
        }
      } else {
        label = 'Test push failed: HTTP ${resp.statusCode} — ${resp.body}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test push error: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingTestPush = false);
    }
  }

  /// Dump the current notification state so Rakhi (or the dev) can see
  /// exactly where the chain breaks. Reads:
  ///   - platform + isWeb flag
  ///   - FCM auth status (authorized / denied / not-determined)
  ///   - whether a token is currently in memory (prefix only)
  ///   - whether Firestore has the device_tokens/{web|primary} doc
  ///   - VAPID key configured flag (web only)
  Future<void> _showDiagnostic() async {
    final buf = StringBuffer();
    buf.writeln('Platform: ${kIsWeb ? 'web (browser PWA)' : 'native'}');
    buf.writeln('User: ${widget.user.id}');

    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      buf.writeln('Auth status: ${settings.authorizationStatus.name}');
    } catch (e) {
      buf.writeln('Auth status: ERROR ${e.toString()}');
    }

    if (kIsWeb) {
      buf.writeln(
        'VAPID key set: ${AppConstants.vapidPublicKey.isNotEmpty ? 'yes' : 'NO — push cannot work'}',
      );
    }

    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey: AppConstants.vapidPublicKey,
            )
          : await FirebaseMessaging.instance.getToken();
      if (token == null) {
        buf.writeln(
          'FCM token: NULL (permission denied or VAPID/SW issue)',
        );
      } else {
        buf.writeln('FCM token: ${token.substring(0, 20)}... (len ${token.length})');
      }
    } catch (e) {
      buf.writeln('FCM token: ERROR ${e.toString()}');
    }

    try {
      final docId = kIsWeb ? 'web' : 'primary';
      final snap = await FirebaseFirestore.instance
          .collection('users/${widget.user.id}/device_tokens')
          .doc(docId)
          .get();
      if (!snap.exists) {
        buf.writeln('Firestore token doc ($docId): MISSING');
      } else {
        final data = snap.data() ?? {};
        final stored = (data['fcm_token'] ?? '').toString();
        final updated = data['updated_at']?.toString() ?? '?';
        buf.writeln(
          'Firestore token doc ($docId): exists, '
          'token=${stored.isEmpty ? 'EMPTY' : '${stored.substring(0, 20)}...'}, '
          'updated=$updated',
        );
      }
    } catch (e) {
      buf.writeln('Firestore token doc: ERROR ${e.toString()}');
    }

    if (!mounted) return;
    setState(() => _diagReport = buf.toString());
  }

  /// Re-run the notification onboarding for this device. Asks the OS
  /// for notification permission (idempotent — if already granted the
  /// prompt doesn't re-appear), reads the FCM token (web build passes
  /// the VAPID key) and re-saves it under device_tokens/{web|primary}.
  /// Useful after clearing Safari data, reinstalling the PWA, or
  /// switching devices.
  Future<void> _reRegisterDevice() async {
    setState(() => _registeringToken = true);
    try {
      // Permission grant (iOS Safari shows the native prompt only if
      // not-yet-determined; once denied, the user has to go to Safari
      // settings themselves. We surface that case via the FCM status).
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'Notifications blocked in Safari. Open iPhone Settings → Safari → Advanced → Website Data → allow notifications for jarvis-78573.web.app.'
                  : 'Notifications blocked — enable in Android app settings.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      // NotificationService.initialize handles token fetch + Firestore
      // save under device_tokens/{web|primary} + onTokenRefresh listener.
      await NotificationService().initialize(widget.user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Device re-registered. Now tap "Send test notification" above.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Re-register error: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _registeringToken = false);
    }
  }
}
