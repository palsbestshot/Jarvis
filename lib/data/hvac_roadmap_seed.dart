// Seed content for the "AI HVAC Sales Leadership Roadmap" goal.
//
// This is a hardcoded snapshot of the 24-month roadmap from
// AI_HVAC_Sales_Leadership_Roadmap.docx — 4 phases, 12 sections,
// 47 checkpoints. Tapping "Import HVAC Roadmap" on the Goals tab
// passes this map straight into FirestoreService.seedHvacRoadmap()
// which creates the goal doc under users/{userId}/goals/.
//
// If the docx ever changes, edit the checkpoint text here and re-seed
// (the seed function is idempotent by title + type, so you'd need to
// delete the old goal from Firestore first).

const Map<String, dynamic> kHvacRoadmapSeed = {
  'title': 'AI HVAC Sales Leadership Roadmap',
  'description':
      'A 24-month action plan to systematically delegate routine and core '
      'tasks to AI, while building the skills needed for national HVAC sales '
      'leadership in India. Phased: Clear the Deck → Upgrade the Core → '
      'Build Authority → Scale & Lead.',
  'type': 'roadmap',
  'status': 'active',
  'phases': [
    {
      'id': 'p1',
      'title': 'Clear the Deck',
      'monthsLabel': 'Months 1–3',
      'monthStart': 1,
      'monthEnd': 3,
      'focus':
          'Eliminate routine tasks, set up email & daily tracking',
      'automationTarget': '90% routine tasks automated',
      'sections': [
        {
          'id': '1a',
          'title': 'Email Tracking & Actionable Task Extraction',
          'summary':
              'Power Automate / Apps Script flows to auto-flag, convert to tasks, '
              'digest daily, and remind on missed follow-ups.',
          'checkpoints': [
            {
              'id': '1a-1',
              'title': 'Power Automate / Apps Script account created and connected',
            },
            {
              'id': '1a-2',
              'title': 'VIP sender list configured with 25+ contacts',
            },
            {
              'id': '1a-3',
              'title': 'Flow 1 (Important Email Highlighter) live and tested for 3 days',
            },
            {
              'id': '1a-4',
              'title': 'Flow 2 (Email-to-Task) live — tasks appearing automatically',
            },
            {
              'id': '1a-5',
              'title': 'Flow 3 (Daily Digest) delivering every morning for 1 week',
            },
            {
              'id': '1a-6',
              'title': 'Flow 4 (Follow-Up Reminder) catching missed replies',
            },
            {
              'id': '1a-7',
              'title': 'Email triage time reduced by 50%+ over 2 weeks (measured)',
            },
            {
              'id': '1a-8',
              'title': 'Connect Power Automate tasks to JARVIS via Firebase webhook',
            },
          ],
        },
        {
          'id': '1b',
          'title': 'Daily Activity & Time Tracking System',
          'summary':
              '2-step setup: first track (voice log / form / sheet), then optimise. '
              'Know where your hours go before reclaiming them.',
          'checkpoints': [
            {
              'id': '1b-1',
              'title': 'Tracking method chosen and set up (JARVIS voice / Google Form / Sheet)',
            },
            {
              'id': '1b-2',
              'title': 'Logged activities for 5 consecutive workdays',
            },
            {
              'id': '1b-3',
              'title': 'Completed first weekly time audit (where do my hours go?)',
            },
            {
              'id': '1b-4',
              'title': 'Identified top 3 time-wasting activities',
            },
            {
              'id': '1b-5',
              'title': 'Dashboard / pivot table created showing category breakdown',
            },
            {
              'id': '1b-6',
              'title': 'Revenue-generating vs. non-revenue time ratio calculated',
            },
            {
              'id': '1b-7',
              'title':
                  'First optimisation action taken (e.g. batched meetings, reduced email checks)',
            },
            {
              'id': '1b-8',
              'title': 'Shared weekly summary with self for 4 consecutive weeks',
            },
          ],
        },
        {
          'id': '1c',
          'title': 'Other Routine Tasks to Automate (Weeks 3–12)',
          'summary':
              'Visit reports via JARVIS voice → CRM, 10 follow-up templates in Claude, '
              'auto MIS on Mondays, quotation template, daily Telugu practice.',
          'checkpoints': [
            {
              'id': '1c-1',
              'title': 'Zero manually typed visit reports by Week 6 (JARVIS voice → CRM)',
            },
            {
              'id': '1c-2',
              'title': '10 follow-up message templates created in Claude',
            },
            {
              'id': '1c-3',
              'title': 'Auto MIS / pipeline report running every Monday 7 AM',
            },
            {
              'id': '1c-4',
              'title': 'Quotation app Phase 1 / Claude quotation template ready',
            },
            {
              'id': '1c-5',
              'title': 'Telugu practice started (daily 15–20 min, 50 HVAC phrases in Month 1)',
            },
          ],
        },
      ],
    },
    {
      'id': 'p2',
      'title': 'Upgrade the Core',
      'monthsLabel': 'Months 3–6',
      'monthStart': 3,
      'monthEnd': 6,
      'focus': 'AI handles main tasks, build strategic skills',
      'automationTarget': '50% main tasks delegated',
      'sections': [
        {
          'id': '2a',
          'title': 'Main Tasks to Delegate to AI',
          'summary':
              'Proposals (AI 70% / you 30%), pre-meeting dossiers, training content, '
              'initial hiring screens.',
          'checkpoints': [
            {
              'id': '2a-1',
              'title': 'Proposal brief template created and tested on 3 real proposals',
            },
            {
              'id': '2a-2',
              'title': 'Pre-meeting research workflow taking < 15 min per meeting',
            },
            {
              'id': '2a-3',
              'title': 'At least 3 training modules created from your real experiences',
            },
            {
              'id': '2a-4',
              'title': 'Hiring Kit used for 1+ real hiring round with scorecard',
            },
          ],
        },
        {
          'id': '2b',
          'title': 'Skills to Build Personally',
          'summary':
              'Energy consulting (ECBC/BEE/IGBC), presentation structure, '
              'body language in B2B meetings, Telugu depth.',
          'checkpoints': [
            {
              'id': '2b-1',
              'title': 'ECBC 2017 key clauses studied and summarised',
            },
            {
              'id': '2b-2',
              'title':
                  'Presented using Problem-Cost-Solution-Proof structure at least twice',
            },
            {
              'id': '2b-3',
              'title': 'Recorded and reviewed yourself presenting at least 3 times',
            },
            {
              'id': '2b-4',
              'title': 'Consciously practiced 1 body language habit for 4+ weeks',
            },
            {
              'id': '2b-5',
              'title': 'Telugu vocabulary at 100+ business phrases',
            },
          ],
        },
      ],
    },
    {
      'id': 'p3',
      'title': 'Build Authority',
      'monthsLabel': 'Months 6–12',
      'monthStart': 6,
      'monthEnd': 12,
      'focus': 'Industry presence, thought leadership',
      'automationTarget': 'Content & research automated',
      'sections': [
        {
          'id': '3a',
          'title': 'LinkedIn & Content Strategy',
          'summary':
              '2 posts/week drafted by AI and edited for voice; long-form articles '
              'shared with top consultants; builds inbound leads.',
          'checkpoints': [
            {
              'id': '3a-1',
              'title': 'LinkedIn profile updated with HVAC leadership positioning',
            },
            {
              'id': '3a-2',
              'title': 'First 8 LinkedIn posts published (1 month of 2x/week)',
            },
            {
              'id': '3a-3',
              'title': 'First long-form article written and shared with consultants',
            },
            {
              'id': '3a-4',
              'title': '500+ relevant LinkedIn connections in HVAC/construction',
            },
            {
              'id': '3a-5',
              'title': '1+ inbound enquiry or introduction from content/networking',
            },
          ],
        },
        {
          'id': '3b',
          'title': 'Financial Fluency',
          'summary':
              'Speak IRR / payback / TCO / NPV — not just price. Present cost-of-ownership '
              'to CFOs.',
          'checkpoints': [
            {
              'id': '3b-1',
              'title': 'Financial statements course completed (10 hours)',
            },
            {
              'id': '3b-2',
              'title': 'Lifecycle cost analysis created for top 3 product lines',
            },
          ],
        },
        {
          'id': '3c',
          'title': 'Negotiation Skills',
          'summary':
              'Chris Voss tactical empathy applied in Indian B2B context — calibrated '
              'questions, labelling, late-night-DJ voice.',
          'checkpoints': [
            {
              'id': '3c-1',
              'title': '"Never Split the Difference" read and 4+ techniques practiced',
            },
          ],
        },
        {
          'id': '3d',
          'title': 'Strategic Stakeholder Mapping',
          'summary':
              'Influence map (specifier, approver, blocker, informal influencer) for '
              'every major project > 25 lakhs.',
          'checkpoints': [
            {
              'id': '3d-1',
              'title': 'Stakeholder mapping done for 3+ major live projects',
            },
          ],
        },
      ],
    },
    {
      'id': 'p4',
      'title': 'Scale & Lead',
      'monthsLabel': 'Months 12–24',
      'monthStart': 12,
      'monthEnd': 24,
      'focus': 'Operate at national leadership level',
      'automationTarget': 'Full systems leadership',
      'sections': [
        {
          'id': '4a',
          'title': 'Target Daily Calendar by Month 12',
          'summary':
              'AI dashboard review → high-value meetings → lunch networking → coaching → '
              'strategy → content → learning → end-of-day review.',
          'checkpoints': [
            {
              'id': '4a-1',
              'title':
                  'Daily calendar matches the target structure for 4+ consecutive weeks',
            },
            {
              'id': '4a-2',
              'title':
                  'Team operating with 70%+ AI-assisted first drafts for proposals/quotes',
            },
          ],
        },
        {
          'id': '4b',
          'title': 'Skills for National Scale',
          'summary':
              'Cross-functional leadership, national consultant network, people '
              'management through regional leads.',
          'checkpoints': [
            {
              'id': '4b-1',
              'title':
                  'Cross-functional shadowing completed (projects / service team, 2–3 days)',
            },
            {
              'id': '4b-2',
              'title': 'Spoken or moderated at 1+ industry event (ACREX / ISHRAE)',
            },
            {
              'id': '4b-3',
              'title':
                  'Relationships built with 5+ national-level MEP consultants outside Hyderabad',
            },
          ],
        },
        {
          'id': '4c',
          'title': 'National Leadership Narrative',
          'summary':
              'Positioning statement refined. Story: "I didn\'t just hit targets — '
              'I built systems that can replicate across 5 regions in 6 months."',
          'checkpoints': [
            {
              'id': '4c-1',
              'title':
                  'National sales leadership positioning statement refined and tested',
            },
            {
              'id': '4c-2',
              'title': 'Applied to or had discussions about 2+ national-level roles',
            },
            {
              'id': '4c-3',
              'title':
                  'Sales playbook documented and transferable to new team members',
            },
          ],
        },
      ],
    },
  ],
};
