# Claude Code instructions — Jarvis project

This file is loaded automatically at the start of every Claude Code session
in this repo. Keep it tight — only workflows that future sessions MUST follow.

## Branch awareness — check `git branch --show-current` FIRST

This repo has two long-running branches. Before making ANY code change, run
`git status` / `git branch --show-current` and confirm which branch the user
is targeting:

| Branch | Scope |
|---|---|
| `pallav-apk` | Pallav's stable Android APK. Bug fixes, APK ship-worthy changes. |
| `rakhi-web` | Rakhi's Web PWA work (Flutter Web + meal plan + AI meal tools + FCM web push). |

Rules:
- Never commit changes that mix both scopes in a single session unless the
  user explicitly says so.
- If a shared file (e.g. `claude_service.dart`, `firestore_service.dart`)
  needs a Pallav-only fix, make it on `pallav-apk`, then the user can merge
  into `rakhi-web` when they switch sessions.
- At session end, remind the user to `git push` if there are unpushed
  commits on the current branch.
- Tags: `v1.0.0+8-pallav-stable` marks the pre-Rakhi-PWA baseline.

## Bug-fix workflow

Pallav reports bugs via the Jarvis chat on his phone (typing or voice):

> "bug: draft button spins forever when attachments >5MB"

The chat's `report_bug` tool writes them to Firestore
`users/pallav/bugs/{bugId}` with `status: 'new'`. Sessions on the PC
consume the queue.

### When the user says "check bugs" / "clear bugs" / "any new bugs"

1. **Run the list command** — never read Firestore directly, always go
   through the helper so the query stays consistent:
   ```powershell
   .\scripts\bugs.ps1 list
   ```
   This prints every bug with `status ∈ {'new','in_progress'}`, each with
   its `id`, title, severity, screen, and the full description.

2. **Triage + fix each bug**. Read the description carefully — it's
   Pallav's verbatim report, often captured by voice so may have minor
   transcription errors. Ask for clarification only if genuinely ambiguous.

3. **After fixing, ALWAYS mark it fixed** before moving to the next one:
   ```powershell
   .\scripts\bugs.ps1 fix <bugId> "one-sentence summary of the fix"
   ```
   This flips `status` to `'fixed'` in Firestore so subsequent `list`
   calls don't show it again. **If you skip this step, you will loop on
   the same bug forever.** The user has explicitly called this out.

4. **At the end of the session**, run `bugs.ps1 list` once more — should
   be empty (or only contain bugs you deliberately deferred, which you
   should mention to the user).

### When to NOT treat something as a bug

- If the user says "bug:" in chat but it's actually a feature request,
  still log it via `report_bug` (tool description covers this). Severity
  will be `low` or `medium`. Same queue works fine for both.
- If the user says "check bugs" but nothing is new, say so and move on —
  don't invent fixes.
- If a listed bug is vague ("something is broken") and blocks understanding,
  leave it as `new` and ask the user to clarify in chat. They'll update
  the bug via a follow-up message.

## APK distribution

After any code change that affects the mobile app, ship it to Pallav's
phone in one step:
```powershell
.\scripts\deploy-apk.ps1                         # uses last git commit as notes
.\scripts\deploy-apk.ps1 -Notes "Fix widget bug"  # override notes
```
This bumps `versionCode` in `pubspec.yaml`, runs `flutter build apk --release`,
and distributes via Firebase App Distribution to the `pallav-phone` group.
Push notification lands on his phone's "App Tester" app in ~10s.

**Do not skip the versionCode bump** — App Tester only shows "Update
available" when `versionCode` increments. If you re-ship the same version,
Pallav has to manually uninstall/reinstall.

## Firebase Cloud Functions

Project: `jarvis-78573` (Blaze plan). Region: `us-central1`.

Deploy changed functions:
```
firebase deploy --only functions:<name1>,functions:<name2>
```
Full deploy: `firebase deploy --only functions` (slower, avoid unless many
functions changed).

Relevant bug-tracker endpoints (already deployed):
- `GET  /listOpenBugs?secret=<INGEST_SECRET>` — used by `bugs.ps1 list`
- `POST /markBugFixed?secret=…&bugId=…&fix_notes=…` — used by `bugs.ps1 fix`
- `POST /reopenBug?secret=…&bugId=…` — used by `bugs.ps1 reopen`

## User context

- **User:** Pallav Farsoiya (`palsbestshot@gmail.com`), owner-operator of
  Jarvis. Service Head CPSD-MP at Blue Star India.
- **Device:** Mostly uses the Jarvis Android app on his phone, develops
  via Chrome Remote Desktop to his home PC.
- **Preferences:** Direct, concise responses. Hindi/Hinglish comfortable.
  No markdown formatting in chat responses to the user (it renders poorly
  in the app). Code comments are fine in markdown-friendly prose.

## Never

- Never auto-send emails. Drafts only.
- Never delete tasks without explicit instruction.
- Never skip pre-commit hooks (`--no-verify`) or force-push without asking.
- Never mark a bug as fixed if the fix is incomplete — keep it `in_progress`
  instead by editing the Firestore doc manually, or just leave it `new`.
