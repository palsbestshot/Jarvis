# Your Work Context (for email triage)
# ---------------------------------------------------------------
# This file is read by the triageEmails Cloud Function on every
# Claude call. Edit it any time your role, team, or reporting line
# changes and redeploy (`firebase deploy --only functions:triageEmails`).
#
# Keep entries terse. Jarvis uses this to decide whether YOU must
# act on a mail or whether to delegate, and to generate the email
# summary. Jarvis reads this BEFORE looking at any email and
# addresses you directly (second person) in every task and reply.
# ---------------------------------------------------------------

## Who you are
- **Name:** Pallav Farsoiya
- **Work email:** pallavf@bluestarindia.com
- **Company:** Blue Star India
- **Designation:** Service Head, Commercial AC Service Division (CPSD) — Madhya Pradesh Branch
- **Location:** Indore, Madhya Pradesh (head office; most of your team sits here)
- **Segment:** Commercial AC service — Revamp, AMC, Service Delivery (MP region)

## Your bosses (mails from them are almost always high-priority — handle yourself)
- **Ravi Ramanathan** — Regional Head, Western Region — sits in Mumbai — your regional boss
- **Micheal Angre** — CPSD Division Head (all-India) — your division head
- **Mangesh Raje** — All India Revamp Head — functional boss over the revamp vertical (Harshit's work directly touches him)

Rule: any mail FROM Ravi, Micheal, or Mangesh → **handle it yourself**, treat as top priority regardless of topic.

## Your subordinates (report directly to you)

### Harshit Laad — Revamp Sales Head (Indore)
- **email:** harshitl@bluestarindia.com
- Owns all revamp/replacement sales for your MP branch
- Functional visibility: Mangesh Raje tracks Harshit's revamp numbers — mails from Mangesh about revamp targets/numbers likely need you + Harshit both, but you respond.
- Delegate to him: revamp project enquiries, customer follow-ups on revamp proposals, revamp pipeline/status reviews

### Ankit Hetawal — AMC Sales Head (Indore)
- **email:** ankith@bluestarindia.com
- Owns AMC (Annual Maintenance Contract) sales for your MP branch
- Supported by: **Kaushal Kadam** (GET — assists Ankit on AMC; email: kaushalk@bluestarindia.com)
- Delegate to him: AMC renewals, new AMC leads, AMC pricing queries

### Prateek Sen — Service Delivery Head (Bhopal)
- **email:** prateeks@bluestarindia.com
- Owns on-ground service delivery and execution across MP; only team member NOT in Indore
- Supported by:
  - **Hemanth Rathore** — Service Engineer, Indore (email: hemanthr@bluestarindia.com)
  - **Sawan Chauhan** — Service Engineer, Indore (email: sawanc@bluestarindia.com)
- Delegate to him: breakdown complaints, service visit scheduling, spare part dispatch, technician deployment, SLA escalations from customers in MP

### Vinay Nikhade — Commercial Team (Indore)
- **email:** vinayn@bluestarindia.com
- Owns commercial operations for your MP branch — quotations, purchase orders, contract paperwork, commercial terms, pricing/billing paperwork, commercial approvals
- Delegate to him: PO follow-ups, quotation/pricing paperwork, contract and commercial terms queries, billing/payment paperwork, commercial approvals

## Your peers / cross-functional contacts
- Other support functions exist (finance, logistics, projects, HR) — if their mails need a decision from you → handle yourself; if purely operational/informational → fyi, no task.

## External (customers, vendors, channel partners)
- Customer mails: reply personally unless the mail is clearly about a specific engineer's site — then delegate to Prateek Sen.
- Vendor / OEM / spare-parts supplier mails: operational/shipment → Prateek Sen; pricing/commercial → you.
- Channel partner mails: sales-related → Harshit (revamp) or Ankit (AMC); service-related → Prateek.

## Delegation rules
1. Mail from Ravi Ramanathan, Micheal Angre, or Mangesh Raje → **handle yourself**, high priority.
2. Mail requiring a decision, approval, price sign-off, customer commitment, or management reply → **handle yourself**.
3. Revamp enquiry, project proposal, revamp follow-up → **delegate to Harshit Laad**.
4. AMC renewal, AMC lead, AMC pricing query → **delegate to Ankit Hetawal**.
5. Breakdown, service call, site visit, technician/spare request, SLA issue → **delegate to Prateek Sen**.
6. Sub-tasks under Prateek's territory (involving Hemanth or Sawan) → still show Prateek as delegate.
7. PO / quotation / contract paperwork / pricing or billing paperwork / commercial terms / commercial approvals → **delegate to Vinay Nikhade**.
8. CC / FYI broadcast with no direct ask → **no task**.
9. Unclear ownership → **handle yourself** with note "decide ownership".
10. Never delegate to someone not listed in this file.

## Output contract for each email that becomes a task
- **email_summary** (2-3 lines): who wrote, the gist, what outcome they want — phrased TO you, in second person ("Ravi is asking you for…", NOT "Ravi is asking Pallav for…").
- **action_type**: `"self"` or `"delegate"`
- **delegate_to**: null if self, else the subordinate's name from above.
- **task title**: `"Do it yourself: <title>"` or `"Delegate to <Name>: <title>"`
- **how_to_close**: concrete next steps — phrased as instructions to you ("Reply to Ravi with…", "Ask Harshit to…"), not third-person narration.
