// The 10 activity categories from the HVAC roadmap docx (Phase 1B), plus
// their default revenue-generating flag and a colour/icon for UI.
//
// User can override `is_revenue` per log entry, but these defaults mirror
// the docx's framing: direct client-facing + selling work is revenue,
// admin/email/travel/learning/MIS is non-revenue.

import 'package:flutter/material.dart';

class TimeCategory {
  final String id;           // stable key stored on log docs
  final String label;        // display name
  final bool defaultRevenue; // revenue-generating by default?
  final IconData icon;
  final Color color;         // used in the analytics breakdown bar

  const TimeCategory({
    required this.id,
    required this.label,
    required this.defaultRevenue,
    required this.icon,
    required this.color,
  });
}

class TimeCategories {
  static const client_meeting = TimeCategory(
    id: 'client_meeting',
    label: 'Client Meetings',
    defaultRevenue: true,
    icon: Icons.people,
    color: Color(0xFF4CAF50), // green
  );
  static const calls = TimeCategory(
    id: 'calls',
    label: 'Calls',
    defaultRevenue: true,
    icon: Icons.call,
    color: Color(0xFF8BC34A),
  );
  static const quotation = TimeCategory(
    id: 'quotation',
    label: 'Quotation / Proposal',
    defaultRevenue: true,
    icon: Icons.description,
    color: Color(0xFFCDDC39),
  );
  static const team_mgmt = TimeCategory(
    id: 'team_mgmt',
    label: 'Team Management',
    defaultRevenue: true, // indirect, but docx tracks separately
    icon: Icons.groups,
    color: Color(0xFF009688),
  );
  static const strategy = TimeCategory(
    id: 'strategy',
    label: 'Planning & Strategy',
    defaultRevenue: true,
    icon: Icons.lightbulb,
    color: Color(0xFF00BCD4),
  );
  static const email = TimeCategory(
    id: 'email',
    label: 'Email & WhatsApp',
    defaultRevenue: false,
    icon: Icons.email,
    color: Color(0xFFFF9800), // amber
  );
  static const travel = TimeCategory(
    id: 'travel',
    label: 'Travel',
    defaultRevenue: false,
    icon: Icons.directions_car,
    color: Color(0xFFFFB300),
  );
  static const mis = TimeCategory(
    id: 'mis',
    label: 'MIS & Reporting',
    defaultRevenue: false,
    icon: Icons.bar_chart,
    color: Color(0xFF9C27B0),
  );
  static const admin = TimeCategory(
    id: 'admin',
    label: 'Admin & Misc',
    defaultRevenue: false,
    icon: Icons.folder,
    color: Color(0xFFF44336), // red
  );
  static const learning = TimeCategory(
    id: 'learning',
    label: 'Learning & Dev',
    defaultRevenue: false, // investment, not revenue today
    icon: Icons.school,
    color: Color(0xFF3F51B5),
  );

  static const List<TimeCategory> all = [
    client_meeting,
    calls,
    quotation,
    team_mgmt,
    strategy,
    email,
    travel,
    mis,
    admin,
    learning,
  ];

  static TimeCategory? byId(String? id) {
    if (id == null) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}

// Visit/contact type — used only on time_logs with kind='visit'.
class VisitContactType {
  final String id;
  final String label;
  final IconData icon;

  const VisitContactType({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class VisitContactTypes {
  static const architect = VisitContactType(
    id: 'architect',
    label: 'Architect',
    icon: Icons.architecture,
  );
  static const consultant = VisitContactType(
    id: 'consultant',
    label: 'MEP Consultant',
    icon: Icons.engineering,
  );
  static const builder = VisitContactType(
    id: 'builder',
    label: 'Builder / Developer',
    icon: Icons.business,
  );
  static const customer = VisitContactType(
    id: 'customer',
    label: 'Customer',
    icon: Icons.person,
  );
  static const oem = VisitContactType(
    id: 'oem',
    label: 'OEM / Vendor',
    icon: Icons.factory,
  );
  static const channel = VisitContactType(
    id: 'channel',
    label: 'Channel Partner',
    icon: Icons.handshake,
  );
  static const internal = VisitContactType(
    id: 'internal',
    label: 'Internal',
    icon: Icons.groups_2,
  );
  static const other = VisitContactType(
    id: 'other',
    label: 'Other',
    icon: Icons.more_horiz,
  );

  static const List<VisitContactType> all = [
    architect,
    consultant,
    builder,
    customer,
    oem,
    channel,
    internal,
    other,
  ];

  static VisitContactType? byId(String? id) {
    if (id == null) return null;
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }
}

// RAG thresholds — from the HVAC roadmap docx (Phase 1B targets).
// `greenIfGte` = green when metric ≥ this value (for "good when higher").
// `greenIfLte` = green when metric ≤ this value (for "good when lower").
enum RagBand { red, amber, green }

class TimeRagThresholds {
  // "Good when higher" — revenue %, day-coverage %.
  static const double revenuePctGreen = 50; // docx target Month 2
  static const double revenuePctAmber = 30; // below = red
  static const double coveragePctGreen = 85;
  static const double coveragePctAmber = 50;

  // "Good when lower" — admin/email %, email-min/day.
  static const double adminPctGreen = 15;   // docx target Month 2
  static const double adminPctAmber = 25;
  static const double emailMinGreen = 20;   // docx target < 20 min/day
  static const double emailMinAmber = 40;

  static RagBand higherIsBetter(double value, double green, double amber) {
    if (value >= green) return RagBand.green;
    if (value >= amber) return RagBand.amber;
    return RagBand.red;
  }

  static RagBand lowerIsBetter(double value, double green, double amber) {
    if (value <= green) return RagBand.green;
    if (value <= amber) return RagBand.amber;
    return RagBand.red;
  }

  static Color colorFor(RagBand b) {
    switch (b) {
      case RagBand.green:
        return const Color(0xFF4CAF50);
      case RagBand.amber:
        return const Color(0xFFFF9800);
      case RagBand.red:
        return const Color(0xFFE53935);
    }
  }
}
