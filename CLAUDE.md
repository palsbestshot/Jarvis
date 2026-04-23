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

## Rakhi PWA deploy (`rakhi-web` branch only)

Web-build + deploy Rakhi's Jarvis PWA — lives at `https://jarvis-78573.web.app`:
```powershell
.\scripts\deploy-web.ps1                 # build + deploy to hosting + functions
.\scripts\deploy-web.ps1 -BuildOnly      # build only, skip deploy
.\scripts\deploy-web.ps1 -FunctionsOnly  # skip web build, deploy functions only
```

The script backs up `env.json`, replaces it with `{}` during the build so
provider API keys don't end up in the browser bundle, runs
`flutter build web --dart-define-from-file=env.web.json`, restores
`env.json`, then runs `firebase deploy --only hosting,functions`.

**One-time setup before the first successful deploy** (if not yet done):

1. Firebase Console → `jarvis-78573` → Project settings → General → Your
   apps → Add app → Web.
   - Nickname: "Rakhi PWA".
   - Copy the generated `apiKey` + `appId` into BOTH
     `lib/firebase_options.dart` (the `web` block) AND
     `web/firebase-messaging-sw.js` — they must match exactly.
2. Firebase Console → Project settings → Cloud Messaging → Web Push
   certificates → Generate key pair. Paste the public key into
   `env.web.json` as `VAPID_PUBLIC_KEY`.
3. `functions/.env` already has `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
   `INGEST_SECRET`. Don't commit that file (it's gitignored).

**Regression test for Pallav's APK after any deploy that touches shared
code** (`claude_service.dart`, `openai_service.dart`, `notification_service.
dart`, `functions/index.js`):

1. Re-ship the APK: `.\scripts\deploy-apk.ps1`.
2. On his phone, open Chrome devtools → Network tab pointed at the APK
   (via `chrome://inspect` + USB debugging). Trigger chat + voice +
   TTS. Confirm the requests go to `api.anthropic.com` and
   `api.openai.com` directly — **zero requests** to
   `*.cloudfunctions.net/aiChat` or `/aiTranscribe` or `/aiTTS`.
3. Confirm widget tap → tasks tab, chat bar voice/camera still work,
   email triage still runs, bug reporting still writes to
   `users/pallav/bugs`.

**iPhone verification for Rakhi's side**:

1. In Safari on her iPhone, open `https://jarvis-78573.web.app`.
2. Share icon → "Add to Home Screen". Confirm the Jarvis icon appears.
3. Launch from home screen — should be standalone, no Safari chrome.
4. On first chat, grant mic + notification permissions if prompted.
5. Open devtools on the deployed site (via Safari Remote Inspector on
   macOS) and search the JS bundle for `sk-` — **should find nothing**.

## Rakhi's context for AI replies

Rakhi is a home chef + small-business entrepreneur, mother of a
2-year-old, married to Pallav, living in India. Her Claude system prompt
(`warm_companion` branch in `claude_service.dart`) already bakes this in,
plus a COOKING + MEAL CONTEXT block that biases suggestions toward:
- Indian home-style cooking (North + South + Indo-Chinese)
- Healthy / low-oil variants
- Toddler-friendly adaptations for lunch / dinner / brunch
- 20–30 minute prep times
- Seasonal / Ayurvedic cues when she asks

She does NOT have access to email triage, Outlook drafts, time logging,
or HVAC-category tools — those are Pallav-only via the tool-list gate
in `_buildTools(userId)`. She has: create_task, create_recurring_task,
save_thought, save_goal, save_finance, report_bug, and four meal tools
(save_meal, query_dishes, suggest_dish_from_ingredients, plan_day_meals).

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
