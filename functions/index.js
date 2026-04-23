// runtime: nodejs22 (bumped 2026-04-21)
// triage v5: strip HTML from email body before sending — fix invalid JSON from raw HTML chars
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');
const fs = require('fs');
const path = require('path');

admin.initializeApp();
const db = admin.firestore();

const EMAIL_USER = 'pallav';

function stripHtml(html) {
  return (html || '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

// Load user context once at cold start. Edit functions/context/user_context.md
// and redeploy to refresh. Triage reads this on every run.
let USER_CONTEXT = '';
try {
  USER_CONTEXT = fs.readFileSync(
    path.join(__dirname, 'context', 'user_context.md'),
    'utf8'
  );
  console.log(`[init] loaded user_context.md (${USER_CONTEXT.length} chars)`);
} catch (err) {
  console.error('[init] failed to load user_context.md:', err.message);
  USER_CONTEXT = '(user context file missing — triage without org info)';
}

// Parse subordinate name → email map from user_context.md once at cold start.
// Used by triageEmails to stamp delegate_email on tasks so Power Automate can
// create an Outlook "Forward" draft to the right person without any lookup.
function parseSubordinateEmails(md) {
  const map = {};
  let currentHeading = null;
  const lines = md.split('\n');
  for (const line of lines) {
    // Section heading: "### Harshit Laad — Revamp Sales Head (Indore)"
    const h = line.match(/^###\s+([^—\n]+?)\s+—/);
    if (h) { currentHeading = h[1].trim(); continue; }
    // Section-style email: "- **email:** harshitl@bluestarindia.com"
    const sectionEmail = line.match(/-\s*\*\*email:\*\*\s*([^\s,;)]+@[^\s,;)]+)/i);
    if (sectionEmail && currentHeading) {
      map[currentHeading.toLowerCase()] = sectionEmail[1].trim();
      continue;
    }
    // Inline: "**Kaushal Kadam** (... email: kaushalk@bluestarindia.com)"
    const inlineRe = /\*\*([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)+)\*\*[^\n(]*\([^)\n]*email:\s*([^\s,;)]+@[^\s,;)]+)/gi;
    let im;
    while ((im = inlineRe.exec(line)) !== null) {
      map[im[1].trim().toLowerCase()] = im[2].trim();
    }
  }
  return map;
}
const SUBORDINATE_EMAILS = parseSubordinateEmails(USER_CONTEXT);
console.log(`[init] parsed ${Object.keys(SUBORDINATE_EMAILS).length} subordinate emails: ${Object.keys(SUBORDINATE_EMAILS).join(', ')}`);

// HTML signature appended to every Outlook draft body (reply or forward).
// Edit in one place — pendingDrafts concatenates this onto `comment_html`
// and PA drops that straight into Graph createReply / createForward's
// `comment` field. Outlook mobile renders it below the user-written text
// and above the quoted original / forwarded thread.
const EMAIL_SIGNATURE_HTML = [
  'Regards, Pallav Farsoiya',
  '',
  'Blue Star Limited',
  '',
  '+91 63059 74905',
].join('<br>');

// ─── HELPER: Send FCM to user ───────────────────────────────────────────────
// Rakhi's iPhone PWA registers a token in `device_tokens/web`; Pallav's
// Android APK registers in `device_tokens/primary`. Both can coexist for
// the same user, and both should fire when present. We explicitly fetch
// the two well-known docs instead of scanning the whole collection, so
// any stale per-token docs left over from older versions don't cause
// duplicate pushes for Pallav.
async function sendFCMToUser(userId, title, body, data = {}) {
  const tokensRef = db.collection(`users/${userId}/device_tokens`);
  const [primarySnap, webSnap] = await Promise.all([
    tokensRef.doc('primary').get(),
    tokensRef.doc('web').get(),
  ]);

  const targets = [];
  if (primarySnap.exists && primarySnap.data().fcm_token) {
    targets.push({
      platform: 'android',
      token: primarySnap.data().fcm_token,
      ref: primarySnap.ref,
    });
  }
  if (webSnap.exists && webSnap.data().fcm_token) {
    targets.push({
      platform: 'web',
      token: webSnap.data().fcm_token,
      ref: webSnap.ref,
    });
  }
  if (targets.length === 0) return;

  await Promise.all(targets.map(async (t) => {
    const message = {
      token: t.token,
      notification: { title, body },
      data: { ...data, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
    };
    if (t.platform === 'web') {
      // Web push needs a webpush config, not the android block.
      // click_url is read by the service worker's notificationclick
      // handler to open / focus the PWA at the right screen.
      message.webpush = {
        notification: {
          icon: '/icons/Icon-192.png',
          badge: '/icons/Icon-192.png',
        },
        fcmOptions: { link: data.click_url || '/' },
      };
    } else {
      message.android = { priority: 'high' };
    }
    try {
      await admin.messaging().send(message);
    } catch (e) {
      // Token no longer valid (uninstalled, browser cleared, etc.) —
      // drop the doc so we stop hammering FCM with dead tokens. Any
      // other failure is just logged; don't throw because the caller
      // is usually a scheduled job and one send shouldn't block others.
      if (e && e.code === 'messaging/registration-token-not-registered') {
        await t.ref.delete().catch(() => {});
      } else {
        console.error(`[sendFCMToUser] ${userId} ${t.platform} send failed`, e);
      }
    }
  }));
}

// ─── HELPER: Save pending message to Firestore ───────────────────────────────
async function savePendingMessage(userId, content, messageType) {
  await db.collection(`users/${userId}/pending_messages`).add({
    content,
    message_type: messageType,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    fetched: false
  });
}

// ─── MORNING QUOTES ARRAY (fallback if Claude unavailable) ──────────────────
const MORNING_QUOTES = [
  "Success is the sum of small efforts repeated day in and day out.",
  "Don't watch the clock; do what it does. Keep going.",
  "The secret of getting ahead is getting started.",
  "Push yourself, because no one else is going to do it for you.",
  "Great things never come from comfort zones.",
  "Dream it. Wish it. Do it.",
  "Success doesn't just find you. You have to go out and get it.",
  "The harder you work for something, the greater you'll feel when you achieve it.",
  "Dream bigger. Do bigger.",
  "Don't stop when you're tired. Stop when you're done.",
  "Wake up with determination. Go to bed with satisfaction.",
  "Do something today that your future self will thank you for.",
  "Little things make big days.",
  "It's going to be hard, but hard is not impossible.",
  "Don't wait for opportunity. Create it.",
  "Sometimes we're tested not to show our weaknesses, but to discover our strengths.",
  "The key to success is to focus on goals, not obstacles.",
  "Discipline is doing what needs to be done even when you don't want to.",
  "Your only limit is your mind.",
  "Small daily improvements lead to stunning results."
];

// ─── AI BRIEFING HELPERS ────────────────────────────────────────────────────
// Claude Haiku reads today's task list and generates:
//   - quote: 1-line motivational opener (contextual to today)
//   - insight: 2-3 sentences on HOW to tackle today — sequencing,
//     what to batch, where to start.
//   - focus_one_thing: the single most important task to crack first.
//
// Called from morningBriefing once per user per day (~500 tokens in,
// ~250 out → effectively free on Haiku).
async function generateMorningBrief(userId, pendingTasks, rolledOverCount) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey || pendingTasks.length === 0) return null;

  const taskLines = pendingTasks.slice(0, 12).map((t, i) => {
    const importance = t.importance || 'medium';
    const action = t.action_type === 'delegate'
      ? `delegate to ${t.delegate_to || 'team'}`
      : 'self';
    const rollover = t.original_due_date ? ' [ROLLED OVER]' : '';
    return `${i + 1}. [${importance}] [${action}]${rollover} ${t.title}`;
  }).join('\n');

  const prompt = `You are Pallav's morning coach. Pallav is Service Head, Commercial AC Service Division at Blue Star India (MP branch, Indore). He has a small team he delegates to and bosses in Mumbai.

Today's date: ${new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Kolkata' })}
Pending tasks for today (${pendingTasks.length} total${rolledOverCount > 0 ? `, ${rolledOverCount} rolled over from earlier` : ''}):
${taskLines}

Generate a JSON object with exactly these keys:
{
  "quote": "1-line motivational opener (max 15 words, no clichés, feel like a coach who knows him)",
  "insight": "2-3 sentences on HOW to tackle today's list. Look at the mix. Call out what to batch (e.g. 'handle all three delegations in one 15-min burst before your first meeting'), what's urgent because of rollover, what he should do FIRST to unblock the team. Be specific, reference actual task titles where useful.",
  "focus_one_thing": "The single most important task title from the list — the one thing that if done by noon would make today a win."
}

Output ONLY the JSON, no preamble.`;

  try {
    const claude = new Anthropic({ apiKey });
    const response = await claude.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 600,
      messages: [{ role: 'user', content: prompt }],
    });
    const text = response.content[0].text;
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) throw new Error('no JSON in morning brief response');
    const parsed = JSON.parse(match[0]);
    console.log(`[morningBrief] generated for ${userId}: ${text.length} chars`);
    return parsed;
  } catch (err) {
    console.error(`[morningBrief] Claude call failed for ${userId}:`, err.message);
    return null;
  }
}

// Evening wrap: Claude reads today's done vs undone + tomorrow's due list
// and produces reflection + plan-for-tomorrow.
async function generateEveningBrief(userId, doneTasks, undoneTasks, tomorrowTasks) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return null;

  const doneLines = doneTasks.length === 0
    ? '(none)'
    : doneTasks.slice(0, 10).map((t, i) => `${i + 1}. ${t.title}`).join('\n');
  const undoneLines = undoneTasks.length === 0
    ? '(all clear)'
    : undoneTasks.slice(0, 10).map((t, i) => `${i + 1}. ${t.title}`).join('\n');
  const tomorrowLines = tomorrowTasks.length === 0
    ? '(nothing scheduled yet)'
    : tomorrowTasks.slice(0, 10).map((t, i) => {
        const imp = t.importance || 'medium';
        const action = t.action_type === 'delegate'
          ? `delegate to ${t.delegate_to || 'team'}`
          : 'self';
        return `${i + 1}. [${imp}] [${action}] ${t.title}`;
      }).join('\n');

  const prompt = `You are Pallav's evening coach. Pallav is Service Head, Commercial AC Service Division at Blue Star India (MP branch, Indore). Wrap his day in 3 short pieces.

Today:
  Completed (${doneTasks.length}):
${doneLines}

  Still pending (${undoneTasks.length}):
${undoneLines}

Tomorrow's scheduled tasks (${tomorrowTasks.length}):
${tomorrowLines}

Generate a JSON object with exactly these keys:
{
  "reflection": "2 sentences on today. Honest, not cheerleading. If he shipped a lot, say so. If there are rollovers, flag what will bite tomorrow. Reference specific task titles where useful.",
  "tomorrow_focus": "2-3 sentences on how to attack tomorrow. Look at the mix — which delegations to dispatch first thing so the team isn't blocked, which self-task to start on, what to batch. Reference specific titles.",
  "tomorrow_first_task": "The single best task title from tomorrow's list to start the day with — the one that unblocks others or is time-sensitive.",
  "quote": "1-line closing thought (max 15 words) that matches the day's tone — encouraging if he shipped, steadying if it was tough."
}

Output ONLY the JSON, no preamble.`;

  try {
    const claude = new Anthropic({ apiKey });
    const response = await claude.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 700,
      messages: [{ role: 'user', content: prompt }],
    });
    const text = response.content[0].text;
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) throw new Error('no JSON in evening brief response');
    const parsed = JSON.parse(match[0]);
    console.log(`[eveningBrief] generated for ${userId}: ${text.length} chars`);
    return parsed;
  } catch (err) {
    console.error(`[eveningBrief] Claude call failed for ${userId}:`, err.message);
    return null;
  }
}

// ─── FUNCTION 1: Check reminders every minute ────────────────────────────────
exports.checkReminders = functions.pubsub
  .schedule('every 1 minutes')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    const now = new Date();
    const nowISO = now.toISOString();
    const users = ['pallav', 'rakhi'];

    for (const userId of users) {
      try {
        const remindersSnap = await db
          .collection(`users/${userId}/reminders`)
          .where('fired', '==', false)
          .get();

        for (const doc of remindersSnap.docs) {
          const reminder = doc.data();
          let remindAt = reminder.remind_at;
          
          // Handle Firestore Timestamp object
          if (remindAt && typeof remindAt === 'object' && remindAt.toDate) {
            remindAt = remindAt.toDate().toISOString();
          }
          
          // Handle string format
          if (typeof remindAt === 'string' && remindAt <= nowISO) {
            console.log(`Firing reminder for ${userId}: ${reminder.message}`);
            
            try {
              await sendFCMToUser(
                userId,
                'JARVIS Reminder',
                reminder.message,
                { type: 'reminder', task_id: reminder.task_id || '' }
              );
              await doc.ref.update({ fired: true });
              console.log(`Reminder fired for ${userId}`);
            } catch (fcmError) {
              console.error(`FCM send failed for ${userId}:`, fcmError);
            }
          }
        }
      } catch (error) {
        console.error(`Error checking reminders for ${userId}:`, error);
      }
    }
    return null;
  });

// ─── FUNCTION 2: Morning briefing 7am IST ────────────────────────────────────
// Claude Haiku generates a contextual quote + insight on how to tackle today
// + the one-thing-to-do-first. Falls back to a random static quote if the
// Claude call fails so the user still gets a briefing.
exports.morningBriefing = functions.pubsub
  .schedule('0 7 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const users = ['pallav', 'rakhi'];
    const today = new Date();
    const dateStr = today.toLocaleDateString('en-US', {
      weekday: 'long', month: 'long', day: 'numeric',
      timeZone: 'Asia/Kolkata'
    });
    // Today's date in IST, not UTC.
    const istFmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Kolkata',
      year: 'numeric', month: '2-digit', day: '2-digit',
    });
    const todayStr = istFmt.format(new Date());

    for (const userId of users) {
      const tasksSnap = await db
        .collection(`users/${userId}/tasks`)
        .where('status', '==', 'pending')
        .where('due_date', '==', todayStr)
        .get();

      const tasks = tasksSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      const taskCount = tasks.length;
      const rolledOver = tasks.filter(t => !!t.original_due_date).length;

      // Ask Claude to generate the contextual quote + insight + focus.
      const ai = await generateMorningBrief(userId, tasks, rolledOver);
      const quote = (ai && ai.quote) ||
        MORNING_QUOTES[Math.floor(Math.random() * MORNING_QUOTES.length)];
      const insight = ai && ai.insight ? ai.insight : '';
      const focusOneThing = ai && ai.focus_one_thing ? ai.focus_one_thing : '';

      // Top 3 task titles for the collapsed card view (keeps legacy field).
      const topTasks = tasks.slice(0, 3).map(t => t.title);

      const briefing = JSON.stringify({
        type: 'morning_briefing',
        quote,
        insight,
        focus_one_thing: focusOneThing,
        date: dateStr,
        greeting: 'Good morning!',
        completedTasks: 0,
        totalTasks: taskCount,
        rolledOverCount: rolledOver,
        topTasks,
        aiGenerated: !!ai,
      });

      await savePendingMessage(userId, briefing, 'morning_briefing');
      // Notification body leads with the focus task if we got one from
      // Claude — makes the lock-screen peek actionable.
      const notifBody = focusOneThing
        ? `Focus first: ${focusOneThing}`
        : `${taskCount} task${taskCount !== 1 ? 's' : ''} due today`;
      await sendFCMToUser(
        userId,
        'Good Morning ☀️',
        notifBody,
        { type: 'briefing' }
      );
    }
    return null;
  });

// ─── FUNCTION 3: Mid-morning nudge 10:30am IST ───────────────────────────────
exports.midMorningNudge = functions.pubsub
  .schedule('30 10 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const users = ['pallav', 'rakhi'];
    const todayStr = new Date().toISOString().split('T')[0];

    for (const userId of users) {
      // Check if any tasks done today
      const doneSnap = await db
        .collection(`users/${userId}/tasks`)
        .where('status', '==', 'done')
        .where('due_date', '==', todayStr)
        .get();

      if (doneSnap.empty) {
        const message = "Hey, morning's moving fast — want to knock out your first task?";
        await savePendingMessage(userId, message, 'nudge');
        await sendFCMToUser(userId, 'JARVIS', message, { type: 'nudge' });
      }
    }
    return null;
  });

// ─── FUNCTION 4: Evening wrap 8pm IST ────────────────────────────────────────
// Claude reads today's done vs undone + tomorrow's scheduled tasks and
// generates: reflection on today, a concrete plan for tomorrow, the single
// best task to start tomorrow with, and a closing 1-liner.
exports.eveningWrap = functions.pubsub
  .schedule('0 20 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const users = ['pallav', 'rakhi'];
    const istFmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Kolkata',
      year: 'numeric', month: '2-digit', day: '2-digit',
    });
    const todayStr = istFmt.format(new Date());
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const tomorrowStr = istFmt.format(tomorrow);

    for (const userId of users) {
      const allSnap = await db
        .collection(`users/${userId}/tasks`)
        .where('due_date', '==', todayStr)
        .get();

      const allTasks = allSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      const doneTasks = allTasks.filter(t => t.status === 'done');
      const undoneTasks = allTasks.filter(t => t.status !== 'done');

      const tomorrowSnap = await db
        .collection(`users/${userId}/tasks`)
        .where('due_date', '==', tomorrowStr)
        .get();
      const tomorrowTasks = tomorrowSnap.docs
        .map(d => ({ id: d.id, ...d.data() }))
        .filter(t => t.status !== 'done');

      const total = allTasks.length;
      const done = doneTasks.length;

      const ai = await generateEveningBrief(
        userId, doneTasks, undoneTasks, tomorrowTasks);
      const reflection = ai && ai.reflection ? ai.reflection : '';
      const tomorrowFocus = ai && ai.tomorrow_focus ? ai.tomorrow_focus : '';
      const tomorrowFirstTask =
        ai && ai.tomorrow_first_task ? ai.tomorrow_first_task : '';
      const quote = ai && ai.quote ? ai.quote : '';

      const message = JSON.stringify({
        type: 'evening_wrap',
        date: todayStr,
        tomorrowDate: tomorrowStr,
        greeting: 'Evening wrap!',
        completedTasks: done,
        totalTasks: total,
        pendingTasks: undoneTasks,
        tomorrowTasks,
        reflection,
        tomorrow_focus: tomorrowFocus,
        tomorrow_first_task: tomorrowFirstTask,
        quote,
        aiGenerated: !!ai,
        isEvening: true,
      });

      await savePendingMessage(userId, message, 'evening_wrap');
      const notifBody = tomorrowFirstTask
        ? `Tomorrow start with: ${tomorrowFirstTask}`
        : `Today: ${done}/${total} done · ${tomorrowTasks.length} on deck tomorrow`;
      await sendFCMToUser(
        userId,
        'JARVIS Evening',
        notifBody,
        { type: 'briefing' }
      );
    }
    return null;
  });

// ─── FUNCTION 5: Weekly summary Sunday 7pm IST ───────────────────────────────
exports.weeklySummary = functions.pubsub
  .schedule('0 19 * * 0')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const users = ['pallav', 'rakhi'];

    for (const userId of users) {
      const weekAgo = new Date();
      weekAgo.setDate(weekAgo.getDate() - 7);
      const weekAgoStr = weekAgo.toISOString().split('T')[0];

      const doneSnap = await db
        .collection(`users/${userId}/tasks`)
        .where('status', '==', 'done')
        .where('due_date', '>=', weekAgoStr)
        .get();

      const thoughtsSnap = await db
        .collection(`users/${userId}/thoughts`)
        .orderBy('created_at', 'desc')
        .limit(3)
        .get();

      const message = `Weekly summary: ${doneSnap.size} tasks completed this week. ${thoughtsSnap.size} thoughts saved. Good work — what's the plan for next week?`;

      await savePendingMessage(userId, message, 'weekly_summary');
      await sendFCMToUser(userId, 'JARVIS Weekly', message, { type: 'briefing' });
    }
    return null;
  });

// ─── FUNCTION 6: Generate recurring task instances ───────────────────────────
exports.generateRecurringTasks = functions.pubsub
  .schedule('0 6 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const users = ['pallav', 'rakhi'];
    const today = new Date();
    const todayStr = today.toISOString().split('T')[0];
    const dayName = today.toLocaleDateString('en-US', {
      weekday: 'long', timeZone: 'Asia/Kolkata'
    });

    for (const userId of users) {
      const recurringSnap = await db
        .collection(`users/${userId}/recurring_tasks`)
        .where('active', '==', true)
        .get();

      for (const doc of recurringSnap.docs) {
        const task = doc.data();
        let shouldGenerate = false;

        if (task.frequency === 'daily') {
          shouldGenerate = true;
        } else if (task.frequency === 'weekly') {
          const days = (task.frequency_details || '').split(',').map(d => d.trim());
          shouldGenerate = days.some(d =>
            dayName.toLowerCase().startsWith(d.toLowerCase().substring(0, 3))
          );
        } else if (task.frequency === 'monthly') {
          const dayNum = parseInt(task.frequency_details || '1');
          shouldGenerate = today.getDate() === dayNum;
        }

        if (shouldGenerate) {
          // Check if already generated today
          const existingSnap = await db
            .collection(`users/${userId}/tasks`)
            .where('title', '==', task.title)
            .where('due_date', '==', todayStr)
            .get();

          if (existingSnap.empty) {
            await db.collection(`users/${userId}/tasks`).add({
              title: task.title,
              category: task.category,
              due_date: todayStr,
              due_time: task.time_of_day || null,
              status: 'pending',
              priority: task.priority || 'medium',
              notes: 'Auto-generated from recurring task',
              reminded: false,
              created_at: admin.firestore.FieldValue.serverTimestamp(),
              updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
          }

          // Update last_generated
          await doc.ref.update({
            last_generated: todayStr
          });
        }
      }
    }
    return null;
  });

// ─── FUNCTION 7: Breakfast reminder 9am IST ──────────────────────────────────
exports.breakfastReminder = functions.pubsub
  .schedule('0 9 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const messages = [
      "Breakfast time, Pallav. Fuel up — long day ahead.",
      "Don't skip breakfast. Your brain needs it.",
      "9am — eat something before the day runs away.",
    ];
    const msg = messages[Math.floor(Math.random() * messages.length)];
    await sendFCMToUser('pallav', 'JARVIS', msg, {type: 'nudge'});
    await sendFCMToUser('rakhi', 'JARVIS', 
      'Good morning! Time for breakfast 🌅', {type: 'nudge'});
    return null;
  });

// ─── FUNCTION 8: Lunch reminder 1:30pm IST ───────────────────────────────────
exports.lunchReminder = functions.pubsub
  .schedule('30 13 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    await sendFCMToUser('pallav', 'JARVIS', 
      'Lunch break, Pallav. Step away from work for 30 minutes.',
      {type: 'nudge'});
    await sendFCMToUser('rakhi', 'JARVIS',
      'Lunch time! 🍽️', {type: 'nudge'});
    return null;
  });

// ─── FUNCTION 9: Dinner reminder 9pm IST ─────────────────────────────────────
exports.dinnerReminder = functions.pubsub
  .schedule('0 21 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    // Also check pending tasks for evening nudge
    const todayStr = new Date().toISOString().split('T')[0];
    const pendingSnap = await db
      .collection('users/pallav/tasks')
      .where('status', '==', 'pending')
      .where('due_date', '==', todayStr)
      .get();

    let msg = 'Dinner time. ';
    if (pendingSnap.size > 0) {
      msg += `${pendingSnap.size} tasks still pending. Close them out after dinner.`;
    } else {
      msg += 'All tasks done today. Well earned rest.';
    }
    await sendFCMToUser('pallav', 'JARVIS', msg, {type: 'nudge'});
    await sendFCMToUser('rakhi', 'JARVIS',
      'Dinner time! 🌙', {type: 'nudge'});
    return null;
  });

// ─── FUNCTION: Rakhi meal-prep nudge 8am IST ────────────────────────────────
// Rakhi-only. Reads today's meal_plans doc and whispers the planned lunch
// + dinner ("Today's lunch: Dal Rice. Dinner: Roti + Paneer Bhurji.") so
// she can start prep timing in her head. No-op when nothing is planned.
function _istDateKey(date = new Date()) {
  // IST = UTC+05:30 regardless of daylight saving (India doesn't observe).
  const istMs = date.getTime() + 5.5 * 60 * 60 * 1000;
  return new Date(istMs).toISOString().split('T')[0];
}

async function _resolveDishName(userId, dishId) {
  if (!dishId) return null;
  try {
    const snap = await db.doc(`users/${userId}/dish_catalog/${dishId}`).get();
    if (!snap.exists) return null;
    return snap.data().name || null;
  } catch (e) {
    console.error('[_resolveDishName] failed', dishId, e.message || e);
    return null;
  }
}

exports.mealPrepReminder = functions.pubsub
  .schedule('0 8 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const userId = 'rakhi';
    const todayKey = _istDateKey();
    try {
      const planSnap = await db
        .doc(`users/${userId}/meal_plans/${todayKey}`)
        .get();
      if (!planSnap.exists) {
        console.log(`[mealPrepReminder] no plan for ${todayKey}`);
        return null;
      }
      const plan = planSnap.data() || {};
      const parts = [];

      const lunchDishId = plan.lunch?.dish_id;
      const dinnerDishId = plan.dinner?.dish_id;
      const [lunchName, dinnerName] = await Promise.all([
        _resolveDishName(userId, lunchDishId),
        _resolveDishName(userId, dinnerDishId),
      ]);

      if (lunchName) parts.push(`Lunch: ${lunchName}`);
      if (dinnerName) parts.push(`Dinner: ${dinnerName}`);

      if (parts.length === 0) {
        console.log(`[mealPrepReminder] plan has no lunch/dinner for ${todayKey}`);
        return null;
      }

      const body = `Today's plan — ${parts.join(' • ')}. Shall I prep the ingredient list?`;
      await sendFCMToUser(userId, 'Jarvis — meal prep', body, {
        type: 'meal_prep',
        date: todayKey,
        click_url: '/#/meals',
      });
      console.log(`[mealPrepReminder] sent for ${todayKey}: ${body}`);
    } catch (e) {
      console.error('[mealPrepReminder] failed', e);
    }
    return null;
  });

// ─── FUNCTION: Email ingest (Power Automate → Firestore) ────────────────────
// HTTPS endpoint that Power Automate posts to when a new Outlook email arrives.
// Idempotent: doc ID = messageId, so re-firing is a no-op.
exports.emailIngest = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'POST only' });
  }

  const secret = req.headers['x-ingest-secret'];
  const expected = process.env.INGEST_SECRET || '';
  if (!expected || secret !== expected) {
    return res.status(401).json({ error: 'invalid secret' });
  }

  const {
    messageId,
    subject,
    from,
    body,
    receivedAt,
    outlook_message_id,
    to,
    cc,
  } = req.body || {};
  if (!messageId) {
    return res.status(400).json({ error: 'messageId required' });
  }

  // Safe doc ID — Firestore disallows '/'
  const docId = String(messageId).replace(/[\/\s<>]/g, '_').slice(0, 300);
  const ref = db.doc(`users/${EMAIL_USER}/inbox_emails/${docId}`);
  const existing = await ref.get();
  if (existing.exists) {
    return res.json({ status: 'already_ingested', messageId: docId });
  }

  // Normalise recipients to array<string>. PA may send a comma-joined string
  // or an array; either way we want an array of clean email addresses.
  const toArr = Array.isArray(to)
    ? to.map(x => String(x).trim()).filter(Boolean)
    : (to ? String(to).split(/[,;]+/).map(x => x.trim()).filter(Boolean) : []);
  const ccArr = Array.isArray(cc)
    ? cc.map(x => String(x).trim()).filter(Boolean)
    : (cc ? String(cc).split(/[,;]+/).map(x => x.trim()).filter(Boolean) : []);

  await ref.set({
    messageId: docId,
    subject: subject || '(no subject)',
    from: from || 'unknown',
    body: (body || '').slice(0, 20000),
    receivedAt: receivedAt || new Date().toISOString(),
    // Fields for 1-click Outlook reply/forward — all optional, safe to be absent
    outlook_message_id: outlook_message_id || null,
    email_to: toArr,
    email_cc: ccArr,
    status: 'pending',
    ingestedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return res.json({ status: 'queued', messageId: docId });
});

// ─── FUNCTION: Triage pending emails via Claude every 15 min ────────────────
exports.triageEmails = functions.pubsub
  .schedule('every 15 minutes')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const apiKey = process.env.ANTHROPIC_API_KEY || '';
    if (!apiKey) {
      console.error('[triage] ANTHROPIC_API_KEY not configured');
      return null;
    }

    const pendingSnap = await db
      .collection(`users/${EMAIL_USER}/inbox_emails`)
      .where('status', '==', 'pending')
      .limit(5)
      .get();

    if (pendingSnap.empty) {
      console.log('[triage] no pending emails');
      return null;
    }

    const claude = new Anthropic({ apiKey });
    const emails = pendingSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    // Lock: mark processing first, so a re-run doesn't double-triage
    const batch = db.batch();
    for (const e of emails) {
      batch.update(db.doc(`users/${EMAIL_USER}/inbox_emails/${e.id}`), {
        status: 'processing'
      });
    }
    await batch.commit();

    // Fetch the user's currently-open email-intelligence tasks so Claude can
    // recognise when a new email is a reply/reminder on an existing thread
    // and choose to append notes instead of creating a duplicate task.
    const openTasksSnap = await db
      .collection(`users/${EMAIL_USER}/tasks`)
      .where('source', '==', 'email_intelligence')
      .where('status', '==', 'pending')
      .limit(50)
      .get();
    const openTasks = openTasksSnap.docs.map(d => {
      const td = d.data();
      return {
        id: d.id,
        title: (td.title || '').slice(0, 120),
        email_subject: (td.email_subject || '').slice(0, 120),
        email_from: (td.email_from || '').slice(0, 80),
        how_to_close: (td.how_to_close || '').slice(0, 120),
        created_at: td.created_at && td.created_at.toDate
          ? td.created_at.toDate().toISOString().slice(0, 10)
          : '',
      };
    });
    console.log(`[triage] ${openTasks.length} open email-tasks for dedup context`);

    const now = new Date().toISOString().slice(0, 16).replace('T', ' ');
    console.log(`[triage] processing ${emails.length} emails: ${emails.map(e => e.id.slice(0, 20)).join(', ')}`);
    const emailSummaries = emails.map((e, i) => {
      const cleanBody = stripHtml(e.body).slice(0, 600);
      const toList = Array.isArray(e.email_to) ? e.email_to.join(', ') : '';
      const ccList = Array.isArray(e.email_cc) ? e.email_cc.join(', ') : '';
      return `--- EMAIL ${i + 1} (ID: ${e.id}) ---\n` +
        `From: ${e.from}\n` +
        `To: ${toList}\n` +
        `Cc: ${ccList}\n` +
        `Subject: ${e.subject}\n` +
        `Date: ${e.receivedAt}\n` +
        `Body: ${cleanBody}`;
    }).join('\n\n');

    // Build the subordinate directory (name + email) so Claude can match
    // To/CC against them and delegate to the explicit recipient.
    const subordinateDirectory = Object.entries(SUBORDINATE_EMAILS)
      .map(([nameLower, emailAddr]) => {
        const displayName = nameLower
          .split(' ')
          .map(w => w.charAt(0).toUpperCase() + w.slice(1))
          .join(' ');
        return `  - ${displayName} <${emailAddr}>`;
      })
      .join('\n');

    const openTasksBlock = openTasks.length === 0
      ? '(no open email tasks)'
      : openTasks.map(t =>
          `[${t.id}] from=${t.email_from} | subject="${t.email_subject}" | created=${t.created_at}\n   title: ${t.title}\n   how_to_close: ${t.how_to_close}`
        ).join('\n\n');

    const triagePrompt = `You are JARVIS, the user's personal AI assistant. Address the user directly in the second person (you / your) in EVERY summary, task, next-step and reply you produce — never refer to them by name or in the third person. The user does NOT pre-filter their mail — you see EVERYTHING that hits their inbox (newsletters, notifications, OTPs, marketing, out-of-office replies, calendar invites, internal noise, genuine work). Your single most important job is to decide which of these are worth the user's attention and which are noise. Be RUTHLESS — a cluttered task board is worse than a missed fyi.

===== YOUR WORK CONTEXT (READ THIS FIRST, EVERY TIME) =====
${USER_CONTEXT}
===== END OF WORK CONTEXT =====

===== YOUR CURRENTLY OPEN EMAIL TASKS (for dedup) =====
${openTasksBlock}
===== END OF OPEN TASKS =====

TODAY: ${now}

${emailSummaries}

For EACH email decide:

1. importance: "critical" | "actionable" | "fyi" | "ignore"
   - critical: You personally need to respond or act TODAY. A real human is waiting on you, or a deadline lands today, or money/commitments/escalations are on the line.
   - actionable: Someone (you OR one of your subordinates) needs to do something in the next few days — respond, review, decide, submit, attend.
   - fyi: Relevant context but no action needed. Informational updates, team announcements you're cc'd on, read-only.
   - ignore: Noise. Newsletters, promotions, marketing, LinkedIn/job-board blasts, social notifications, automated system emails (shipping, billing receipts, OTP/verification codes already used, password resets, calendar auto-replies, out-of-office, read receipts, mailer-daemon, "no-reply@" bulk senders), cold outreach/sales pitches, webinar invites, recruiter spam, generic company-wide broadcasts not directed at you.

2. email_summary (2-3 lines): who wrote, the gist, and what outcome they want — phrased TO you, in second person ("Ravi is asking you for…", NOT "Ravi is asking Pallav for…"). ALWAYS provide this for critical/actionable. For fyi/ignore, keep it to one line.

3. action_type: "self" | "delegate" | null
   - "self": You yourself must handle this (boss asking you, customer asking you, decision / approval / sign-off needed, reply to senior).
   - "delegate": A subordinate from your list should handle this (operational chase, quotation follow-up, site coordination under someone's territory).
   - null: For importance "fyi" or "ignore".
   Apply the Delegation rules in the work context above to decide.

   🔴 STRONGEST DELEGATION SIGNAL — EXPLICIT RECIPIENT OVERRIDES TOPIC RULES:
   If the email's To field contains the email of one of your subordinates from the
   directory below, and the email is asking for action, DELEGATE TO THAT SUBORDINATE
   — the sender has already chosen who handles it, regardless of topic.
   Also: if a subordinate is CC'd on a mail that's addressed to you (their email in CC,
   your email in To), that's a hint the sender expects that subordinate to be looped in —
   usually means you own the reply but acknowledge the subordinate. Use judgement.

   SUBORDINATE DIRECTORY (for explicit-recipient matching):
${subordinateDirectory || '  (none configured)'}

4. delegate_to: If action_type is "delegate", the EXACT name of the subordinate from the work context. Otherwise null. NEVER delegate to someone not in the list. If a subordinate is in To or CC, their name MUST be the delegate_to — do not override based on topic rules when they are explicitly marked.

5. DEDUP — BEFORE creating a new task, check the OPEN TASKS list above. If this email is a reply/reminder/continuation of an existing thread (same subject after stripping RE:/FW:, same sender, or clearly same topic as an open task), set "update_existing_task_id" to that task's id and "update_note" to a short 1-line description of what this new email adds (e.g. "Ravi sent a gentle reminder — still waiting for MP numbers, asked by EOD today"). Then tasks MUST be []. Do NOT duplicate. Examples of when to update instead of create:
   - Original task: "Reply to Ravi on Q1 AGM MP values". New email: "Gentle reminder — please share the numbers today." → UPDATE, don't create.
   - Original task: "Delegate to Harshit: share Q2 VRF quotation with Aurobindo". New email from Aurobindo: "When can we expect the quotation?" → UPDATE the Harshit task.
   - DIFFERENT topic from the same sender → create new task (don't force-match).

6. tasks: CREATE A TASK ONLY IF importance is "critical" OR "actionable" AND no existing task matches. For "fyi" / "ignore" / dedup-update cases, tasks MUST be an empty array []. Do NOT invent tasks to justify noise. Do NOT create a task just because an email exists. If in doubt between actionable and fyi, choose fyi (no task). A task must represent a real, specific action; if you cannot write a concrete "how_to_close" with exact steps, it's not a task — drop it.

   TASK TITLE FORMAT — MANDATORY:
   - If action_type is "self": title MUST start with "Do it yourself: " — e.g. "Do it yourself: reply to Ravi on Telangana VRF pricing".
   - If action_type is "delegate": title MUST start with "Delegate to <Name>: " using the exact subordinate name — e.g. "Delegate to Harshit Laad: share Q2 VRF quotation with Aurobindo".

7. suggested_reply: For SELF email tasks needing a response, draft a brief reply written AS IF YOU (Pallav) are typing it yourself — FIRST PERSON ONLY.
   - INCLUDE a brief salutation at the top (e.g. "Hi Ravi,", "Dear Mr. Patel,", "Hello team,") when addressing a specific person.
   - Write as "I will share the numbers by EOD" / "I'll coordinate with Harshit" — NEVER instruct-style like "Pallav will share the numbers" or "You need to follow up with Harshit".
   - Do NOT include task-list phrasing ("follow up with the team", "check with Harshit and revert"). The draft IS the reply going to the sender. Make it sound like a natural message from you.
   - STOP after the last content sentence. Do NOT add any sign-off / closing line / name / designation / company / phone / email / "Regards," / "Thanks," / "Best," etc. at the bottom. The system automatically appends the canonical signature ("Regards, Pallav Farsoiya / Blue Star Limited / +91 63059 74905") to every draft — adding another sign-off here causes a duplicate.
   - For DELEGATE tasks, leave suggested_reply as null and use forward_note instead (next field).

8. forward_note: For DELEGATE email tasks, draft a 2-3 line note that YOU (Pallav) would write to the subordinate when forwarding this email. FIRST PERSON from Pallav addressing the delegate.
   - Start with a greeting by name: "Harshit," / "Prateek," / "Ankit,".
   - Say what you need them to do, with any deadline. Example: "Harshit, please action this — Aurobindo is asking for the Q2 VRF quotation. Share the revised number by Friday and keep me looped."
   - Do NOT phrase as instructions to yourself ("you need to ask Harshit"). Write as if you are talking to the delegate.
   - No sign-off — same rule as suggested_reply. Signature appended by the system.
   - For SELF tasks, set to null.

HARD RULES:
- Marketing, newsletters, promotional, LinkedIn/Naukri/job-board blasts, "your weekly digest", webinar invites, surveys, NPS asks, automated system notifications → importance: "ignore", tasks: [].
- OTPs, password resets, verification codes, receipts, delivery notifications → importance: "ignore", tasks: [].
- Out-of-office auto-replies, read receipts, mailer-daemon, undeliverables → importance: "ignore", tasks: [].
- Pure FYI / CC'd broadcasts where no one is asking anything → importance: "fyi", tasks: [].
- Never delegate to a name not listed in the work context. If ownership is unclear, default to action_type: "self" with notes: "decide ownership".
- When unsure, prefer fewer tasks. A missed task is recoverable; a board full of garbage is not.
- Every human-readable field (email_summary, title, how_to_close, notes, suggested_reply) MUST use second-person voice. No third-person references to the user by name.

Return JSON ONLY:
{
  "analysis": [
    {
      "email_id": "...",
      "importance": "critical|actionable|fyi|ignore",
      "email_summary": "2-3 lines — who wrote, the gist, what outcome they want (phrased TO you in second person)",
      "action_type": "self|delegate|null",
      "delegate_to": "Name from subordinate list or null",
      "update_existing_task_id": "the task id from OPEN TASKS block IF this email is a reply/reminder on that thread, else null",
      "update_note": "1-line note to append on the existing task (only when update_existing_task_id is set), else null",
      "forward_note": "First-person note Pallav writes to the delegate, or null for self tasks",
      "tasks": [
        {
          "title": "Do it yourself: X   OR   Delegate to <Name>: X",
          "priority": "high|medium|low",
          "category": "Work|Email Follow-up|Personal|Meeting|Document Review",
          "due_date": "YYYY-MM-DD or null",
          "how_to_close": "Exact steps for you (or the delegate) to take — phrased in second person",
          "notes": "Context"
        }
      ],
      "suggested_reply": "Draft or null"
    }
  ]
}`;

    let analyses = [];
    try {
      const response = await claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 8000,
        messages: [{ role: 'user', content: triagePrompt }]
      });
      const text = response.content[0].text;
      console.log(`[triage] Claude response: ${text.length} chars, stop_reason=${response.stop_reason}`);
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) throw new Error('no JSON in Claude response');
      analyses = JSON.parse(jsonMatch[0]).analysis || [];
    } catch (err) {
      console.error('[triage] Claude call failed:', err.message);
      // Roll back: put emails back to pending so next run retries
      const rollback = db.batch();
      for (const e of emails) {
        rollback.update(db.doc(`users/${EMAIL_USER}/inbox_emails/${e.id}`), {
          status: 'pending',
          lastError: err.message
        });
      }
      await rollback.commit();
      return null;
    }

    const emailLookup = Object.fromEntries(emails.map(e => [e.id, e]));
    const tasksRef = db.collection(`users/${EMAIL_USER}/tasks`);
    let tasksCreated = 0;

    for (const a of analyses) {
      const emailId = a.email_id;
      const email = emailLookup[emailId];
      if (!email) continue;

      const update = {
        status: 'processed',
        importance: a.importance || 'ignore',
        summary: a.email_summary || a.summary || '',
        emailSummary: a.email_summary || '',
        actionType: a.action_type || null,
        delegateTo: a.delegate_to || null,
        suggestedReply: a.suggested_reply || null,
        triagedAt: admin.firestore.FieldValue.serverTimestamp(),
        taskIds: []
      };

      // Thread-level dedup: Claude saw the open-tasks list and flagged this
      // email as a continuation. Append a note to the existing task, mark the
      // email as processed, and skip task creation entirely.
      const updateTargetId = (a.update_existing_task_id || '').toString().trim();
      if (updateTargetId) {
        try {
          const targetRef = tasksRef.doc(updateTargetId);
          const targetSnap = await targetRef.get();
          if (targetSnap.exists) {
            const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
            const appendedNote = (a.update_note && String(a.update_note).trim())
              || `Follow-up email received from ${email.from} on ${stamp} — "${(email.subject || '').slice(0, 80)}"`;
            const existingNotes = (targetSnap.data().notes || '').toString();
            const newNotes = existingNotes
              ? `${existingNotes}\n\n[${stamp}] ${appendedNote}`
              : `[${stamp}] ${appendedNote}`;
            await targetRef.update({
              notes: newNotes,
              last_email_touch_at: admin.firestore.FieldValue.serverTimestamp(),
              last_email_subject: email.subject || '',
              last_email_from: email.from || '',
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
            update.dedup_target_task_id = updateTargetId;
            update.dedup_note = appendedNote;
            console.log(`[triage] DEDUP: email ${emailId} → updated existing task ${updateTargetId}`);
          } else {
            console.log(`[triage] DEDUP: Claude targeted missing task ${updateTargetId}, falling through to create`);
          }
        } catch (e) {
          console.error(`[triage] DEDUP update failed for ${updateTargetId}:`, e.message);
        }
      }

      if (!updateTargetId
          && (a.importance === 'critical' || a.importance === 'actionable')
          && Array.isArray(a.tasks)) {
        // Dedup guard: skip if any task with this source_email_id already exists
        const existingTasks = await tasksRef
          .where('source_email_id', '==', emailId)
          .limit(1)
          .get();
        if (existingTasks.empty) {
          for (const t of a.tasks.slice(0, 3)) {
            const taskDoc = tasksRef.doc();
            // Enforce title prefix as a safety net — the model is instructed
            // to prefix, but strip/re-add so we never end up with a raw title.
            const rawTitle = (t.title || 'Email follow-up').trim();
            const actionType = a.action_type || 'self';
            const delegateTo = a.delegate_to || null;
            let finalTitle = rawTitle;
            // Accept both the legacy "Do it myself:" prefix and the new
            // second-person "Do it yourself:" — old tasks in the board
            // keep their existing prefix, new ones get the second-person one.
            const hasSelfPrefix = /^do it (myself|yourself)[:\-]/i.test(rawTitle);
            const hasDelegatePrefix = /^delegate to /i.test(rawTitle);
            if (actionType === 'delegate' && delegateTo && !hasDelegatePrefix) {
              finalTitle = `Delegate to ${delegateTo}: ${rawTitle}`;
            } else if (actionType !== 'delegate' && !hasSelfPrefix) {
              finalTitle = `Do it yourself: ${rawTitle}`;
            }

            // Build a rich notes block so every task is self-contained in the app
            const noteParts = [];
            noteParts.push(`From: ${email.from}`);
            noteParts.push(`Subject: ${email.subject}`);
            if (a.email_summary) { noteParts.push(''); noteParts.push(a.email_summary); }
            noteParts.push('');
            noteParts.push(`Decision: ${actionType === 'delegate' ? `Delegate to ${delegateTo}` : 'Handle yourself'}`);
            if (t.how_to_close) { noteParts.push(''); noteParts.push(`Next steps: ${t.how_to_close}`); }
            if (a.suggested_reply) { noteParts.push(''); noteParts.push(`Suggested reply: ${a.suggested_reply}`); }
            const richNotes = noteParts.join('\n').trim();

            // Look up the delegate's email via the name→email map parsed
            // from user_context.md at cold start. PA uses this to address
            // the forward without any lookup of its own.
            const delegateEmail = (actionType === 'delegate' && delegateTo)
              ? (SUBORDINATE_EMAILS[delegateTo.trim().toLowerCase()] || null)
              : null;

            await taskDoc.set({
              title: finalTitle,
              priority: t.priority || 'medium',
              category: t.category || 'Email Follow-up',
              due_date: t.due_date || null,
              notes: richNotes,
              how_to_close: t.how_to_close || '',
              status: 'pending',
              source: 'email_intelligence',
              source_email_id: emailId,
              email_subject: email.subject,
              email_from: email.from,
              email_to: email.email_to || [],
              email_cc: email.email_cc || [],
              outlook_message_id: email.outlook_message_id || null,
              email_summary: a.email_summary || '',
              action_type: actionType,
              delegate_to: delegateTo,
              delegate_email: delegateEmail,
              suggested_reply: a.suggested_reply || null,
              forward_note: a.forward_note || null,
              importance: a.importance,
              // Draft state for 1-click Outlook reply flow. Flutter flips
              // draft_status to 'requested'; PA picks it up and writes back
              // 'ready' (+ draft_id, draft_weblink) or 'error' (+ draft_error).
              draft_status: null,
              created_at: admin.firestore.FieldValue.serverTimestamp(),
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
            update.taskIds.push(taskDoc.id);
            tasksCreated++;
          }
        }
      }

      await db.doc(`users/${EMAIL_USER}/inbox_emails/${emailId}`).update(update);
    }

    console.log(`[triage] processed ${emails.length} emails → ${tasksCreated} tasks`);
    return null;
  });

// ─── FUNCTION: Power Automate polls this for pending Outlook drafts ─────────
// Pivoted away from the Firestore-onUpdate → POST-to-PA-webhook model because
// this tenant only exposes Power Automate "direct" URLs that require OAuth
// (no anonymous SAS token). Firebase can't call those anonymously.
//
// New flow:
//   1. Flutter sets task.draft_status='requested' when user taps the button.
//   2. PA scheduled flow (every 1 min) GETs this endpoint.
//   3. We return all 'requested' tasks with the comment_html pre-built (and
//      atomically flip each one to 'processing' so we don't hand it out twice).
//   4. PA loops, calls Graph createReply / createForward for each, then POSTs
//      the draft_id + webLink to `outlookDraftCallback` below.
//
// Auth: same X-Ingest-Secret header the emailIngest flow already uses.
exports.pendingDrafts = functions
  .region('us-central1')
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    if (req.method !== 'GET' && req.method !== 'POST') {
      return res.status(405).json({ error: 'GET or POST only' });
    }
    const secret = req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }

    const users = ['pallav', 'rakhi'];
    const callbackUrl = `https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/outlookDraftCallback`;
    const callbackSecret = process.env.OUTLOOK_CALLBACK_SECRET || '';
    const tasks = [];

    // ── Watchdog: reclaim tasks stuck in 'processing' for > 15 minutes.
    // Graph createReply/createForward can take 1-3 min in practice, and PA
    // retries on transient failures — 15 min is a safe "really broken" mark.
    // Shorter windows (e.g. 6 min) caused false-positive errors while the
    // draft WAS being created in the background.
    const STUCK_MS = 15 * 60 * 1000;
    const stuckCutoff = admin.firestore.Timestamp.fromMillis(Date.now() - STUCK_MS);
    for (const userId of users) {
      const stuckSnap = await db
        .collection(`users/${userId}/tasks`)
        .where('draft_status', '==', 'processing')
        .where('draft_claimed_at', '<', stuckCutoff)
        .limit(20)
        .get();
      for (const doc of stuckSnap.docs) {
        console.log(`[pendingDrafts] watchdog: task ${doc.id} stuck >15min, flipping to error`);
        await doc.ref.update({
          draft_status: 'error',
          draft_error:
            'Draft generation took over 15 minutes. The draft may still be in your Outlook Drafts folder — check there first. If not, tap Retry to requeue.',
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    for (const userId of users) {
      const snap = await db
        .collection(`users/${userId}/tasks`)
        .where('draft_status', '==', 'requested')
        .limit(20)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const actionType = (data.action_type || 'self').toString();
        const outlookMessageId = data.outlook_message_id;

        // Prereq fails → flip straight to error, don't bother PA.
        if (!outlookMessageId) {
          await doc.ref.update({
            draft_status: 'error',
            draft_error: 'Task has no outlook_message_id — ingested before 1-click feature',
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }
        if (actionType === 'delegate' && !data.delegate_email) {
          await doc.ref.update({
            draft_status: 'error',
            draft_error: 'No email address on file for delegate — add email: line under this person in functions/context/user_context.md',
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }

        // Atomically claim this task — if two pendingDrafts calls overlap
        // (e.g. PA retried), only one gets the task.
        const claimed = await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          if (!fresh.exists) return false;
          if ((fresh.data().draft_status || '') !== 'requested') return false;
          tx.update(doc.ref, {
            draft_status: 'processing',
            draft_claimed_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (!claimed) continue;

        // Reply (self)      → suggested_reply  (first-person to original sender)
        // Forward (delegate) → forward_note     (first-person Pallav → subordinate).
        // Fallback to how_to_close for older tasks that predate forward_note.
        // Signature appended here so PA never has to think about it.
        const userText = actionType === 'delegate'
          ? (data.forward_note || data.how_to_close || '')
          : (data.suggested_reply || '');
        const commentHtml =
          String(userText).replace(/\r?\n/g, '<br>') +
          '<br><br>' +
          EMAIL_SIGNATURE_HTML;

        tasks.push({
          userId,
          taskId: doc.id,
          action_type: actionType,                 // 'self' | 'delegate'
          outlook_message_id: outlookMessageId,    // Graph message id (AAMkA...)
          delegate_email: data.delegate_email || null,
          comment_html: commentHtml,               // drop straight into Graph `comment`
        });
      }
    }

    console.log(`[pendingDrafts] returning ${tasks.length} task(s)`);
    return res.json({ callbackUrl, callbackSecret, tasks });
  });

// ─── FUNCTION: Power Automate writes the draft result back here ─────────────
// After PA creates the Outlook draft via Graph, it POSTs the outcome to
// this endpoint. On success we flip draft_status to 'ready' and store
// draft_id + draft_weblink so the Flutter button can open it. On failure
// we surface draft_error to the user.
//
// Auth: shared secret in X-Callback-Secret header (same value in PA and
// in functions/.env → OUTLOOK_CALLBACK_SECRET).
exports.outlookDraftCallback = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'POST only' });
    }
    const secret = req.headers['x-callback-secret'];
    const expected = process.env.OUTLOOK_CALLBACK_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }

    const { userId, taskId, draft_id, draft_weblink, error } = req.body || {};
    if (!userId || !taskId) {
      return res.status(400).json({ error: 'userId and taskId required' });
    }

    const ref = db.doc(`users/${userId}/tasks/${taskId}`);
    const snap = await ref.get();
    if (!snap.exists) {
      return res.status(404).json({ error: 'task not found' });
    }

    if (error) {
      await ref.update({
        draft_status: 'error',
        draft_error: String(error).slice(0, 400),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`[outlookDraftCallback] task=${taskId} error=${String(error).slice(0, 120)}`);
      return res.json({ status: 'error_recorded' });
    }

    if (!draft_id) {
      return res.status(400).json({ error: 'draft_id required on success' });
    }

    await ref.update({
      draft_status: 'ready',
      draft_id: String(draft_id),
      draft_weblink: draft_weblink ? String(draft_weblink) : null,
      draft_error: null,
      draft_ready_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[outlookDraftCallback] task=${taskId} → ready`);
    return res.json({ status: 'ready' });
  });

// -----------------------------------------------------------------------------
// rolloverYesterdayTasks — auto-shift pending tasks from any past day to today
// -----------------------------------------------------------------------------
// Runs daily at 05:45 IST (before the work day starts). For every user, finds
// tasks where status == 'pending' and due_date < today (IST), bumps their
// due_date to today, and stamps `original_due_date` the FIRST time a task is
// rolled over (so the Board can show a "from <date>" chip). `rollover_count`
// tracks how many times a task has been rolled over.
//
// Timezone note: Firestore stores due_date as a 'YYYY-MM-DD' string keyed to
// the user's local day (IST). We MUST compute today's date in IST, not UTC —
// otherwise early-morning runs (before 05:30 IST) would read a UTC date that's
// still yesterday in India and skip the rollover.
// -----------------------------------------------------------------------------
exports.rolloverYesterdayTasks = functions
  .region('us-central1')
  .pubsub.schedule('45 5 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const users = ['pallav', 'rakhi'];
    const fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Kolkata',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    const todayStr = fmt.format(new Date()); // 'YYYY-MM-DD' in IST

    let grandTotal = 0;
    for (const userId of users) {
      const snap = await db
        .collection(`users/${userId}/tasks`)
        .where('status', '==', 'pending')
        .where('due_date', '<', todayStr)
        .get();

      if (snap.empty) {
        console.log(`[rollover] user=${userId} none to roll over`);
        continue;
      }

      // Firestore batch limit = 500; chunk just in case.
      const docs = snap.docs;
      for (let i = 0; i < docs.length; i += 400) {
        const chunk = docs.slice(i, i + 400);
        const batch = db.batch();
        for (const doc of chunk) {
          const data = doc.data();
          const update = {
            due_date: todayStr,
            rollover_count: admin.firestore.FieldValue.increment(1),
            last_rollover_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          };
          // Stamp original_due_date only on the FIRST rollover.
          if (!data.original_due_date) {
            update.original_due_date = data.due_date;
          }
          batch.update(doc.ref, update);
        }
        await batch.commit();
      }
      grandTotal += docs.length;
      console.log(`[rollover] user=${userId} rolled ${docs.length} → ${todayStr}`);
    }
    console.log(`[rollover] done — total ${grandTotal} task(s) shifted to ${todayStr}`);
    return null;
  });

// ─── Force a task into draft_status='requested' (testing helper) ───────────
// Same auth as resetDraft. Flips draft_status to 'requested' so the next
// pendingDrafts poll (within 60s) picks it up and PA can run end-to-end.
exports.forceDraftRequest = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.query.userId || req.body?.userId || '').toString();
    const taskId = (req.query.taskId || req.body?.taskId || '').toString();
    if (!userId || !taskId) {
      return res.status(400).json({ error: 'userId and taskId required' });
    }
    try {
      await db.doc(`users/${userId}/tasks/${taskId}`).update({
        draft_status: 'requested',
        draft_requested_at: admin.firestore.FieldValue.serverTimestamp(),
        draft_error: admin.firestore.FieldValue.delete(),
        draft_claimed_at: admin.firestore.FieldValue.delete(),
        draft_id: admin.firestore.FieldValue.delete(),
        draft_weblink: admin.firestore.FieldValue.delete(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ ok: true, userId, taskId, draft_status: 'requested' });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// ─── Reset a stuck draft on a task (manual recovery) ───────────────────────
// POST /resetDraft?secret=<INGEST_SECRET>&userId=pallav&taskId=<doc_id>
// Clears draft_status, draft_error, draft_claimed_at so the Flutter button
// flips back to "Create draft in Outlook" and the next tap re-requests.
exports.resetDraft = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.query.userId || req.body?.userId || '').toString();
    const taskId = (req.query.taskId || req.body?.taskId || '').toString();
    if (!userId || !taskId) {
      return res.status(400).json({ error: 'userId and taskId required' });
    }
    try {
      await db.doc(`users/${userId}/tasks/${taskId}`).update({
        draft_status: admin.firestore.FieldValue.delete(),
        draft_error: admin.firestore.FieldValue.delete(),
        draft_claimed_at: admin.firestore.FieldValue.delete(),
        draft_requested_at: admin.firestore.FieldValue.delete(),
        draft_id: admin.firestore.FieldValue.delete(),
        draft_weblink: admin.firestore.FieldValue.delete(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ ok: true, userId, taskId });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// ─── TEMP DIAGNOSTIC: peek recent inbox_emails + email tasks ────────────────
// GET /peekRecentEmails?secret=<INGEST_SECRET>
// Returns the latest 3 inbox_emails and latest 3 email_intelligence tasks
// with just the fields we care about for the 1-click draft flow. Remove
// after debugging.
exports.peekRecentEmails = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    try {
      const inboxSnap = await db
        .collection(`users/${EMAIL_USER}/inbox_emails`)
        .orderBy('ingestedAt', 'desc')
        .limit(3)
        .get();
      const inbox = inboxSnap.docs.map(d => {
        const x = d.data();
        return {
          id: d.id,
          from: x.from,
          subject: (x.subject || '').slice(0, 80),
          outlook_message_id: x.outlook_message_id,
          email_to: x.email_to,
          email_cc: x.email_cc,
          status: x.status,
          ingestedAt: x.ingestedAt && x.ingestedAt.toDate
            ? x.ingestedAt.toDate().toISOString()
            : null,
        };
      });
      const tasksSnap = await db
        .collection(`users/${EMAIL_USER}/tasks`)
        .orderBy('created_at', 'desc')
        .limit(15)
        .get();
      const tasks = tasksSnap.docs
        .filter(d => d.data().source === 'email_intelligence')
        .slice(0, 3)
        .map(d => {
        const x = d.data();
        return {
          id: d.id,
          title: (x.title || '').slice(0, 80),
          outlook_message_id: x.outlook_message_id,
          action_type: x.action_type,
          delegate_to: x.delegate_to,
          delegate_email: x.delegate_email,
          draft_status: x.draft_status,
          source_email_id: x.source_email_id,
          created_at: x.created_at && x.created_at.toDate
            ? x.created_at.toDate().toISOString()
            : null,
        };
      });
      return res.json({ inbox, tasks });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// ─── BUG TRACKER ────────────────────────────────────────────────────────────
// Pallav reports bugs via the Jarvis chat (report_bug tool → Firestore
// users/pallav/bugs). Claude Code sessions on his PC query this endpoint
// at start to pick up open bugs, fix them, then hit markBugFixed to close.
// Keeps the loop out of his Notes app and off the manual copy-paste path.

// GET /listOpenBugs?secret=<INGEST_SECRET>
// Returns bugs where status in ('new','in_progress'), newest first.
// Shape: { bugs: [{id, title, description, severity, screen, status,
//                  reported_at}] }
exports.listOpenBugs = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.query.userId || EMAIL_USER).toString();
    try {
      const snap = await db
        .collection(`users/${userId}/bugs`)
        .orderBy('reported_at', 'desc')
        .limit(50)
        .get();
      const bugs = snap.docs
        .map(d => {
          const x = d.data();
          return {
            id: d.id,
            // user_text is authoritative — Pallav's verbatim chat message.
            // title/description are Claude's paraphrase, kept only as hints.
            user_text: x.user_text || '',
            title: x.title || '',
            description: x.description || '',
            severity: x.severity || 'medium',
            screen: x.screen || '',
            status: x.status || 'new',
            reported_at: x.reported_at && x.reported_at.toDate
              ? x.reported_at.toDate().toISOString()
              : null,
            fix_notes: x.fix_notes || null,
            fixed_at: x.fixed_at && x.fixed_at.toDate
              ? x.fixed_at.toDate().toISOString()
              : null,
          };
        })
        .filter(b => b.status === 'new' || b.status === 'in_progress');
      return res.json({ bugs, count: bugs.length });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// POST /markBugFixed?secret=<INGEST_SECRET>
// Body: { userId?, bugId, fix_notes, fix_commit? }
// Flips status to 'fixed', records fix_notes + fixed_at + optional commit SHA.
// Called by scripts/bugs.ps1 once Claude Code finishes the fix.
exports.markBugFixed = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.query.userId || req.body?.userId || EMAIL_USER).toString();
    const bugId = (req.query.bugId || req.body?.bugId || '').toString();
    const fixNotes = (req.query.fix_notes || req.body?.fix_notes || '').toString();
    const fixCommit = (req.query.fix_commit || req.body?.fix_commit || '').toString();
    if (!bugId) {
      return res.status(400).json({ error: 'bugId required' });
    }
    try {
      const ref = db.doc(`users/${userId}/bugs/${bugId}`);
      const snap = await ref.get();
      if (!snap.exists) {
        return res.status(404).json({ error: 'bug not found' });
      }
      await ref.update({
        status: 'fixed',
        fix_notes: fixNotes || null,
        fix_commit: fixCommit || null,
        fixed_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ ok: true, bugId, userId });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// GET /peekChatHistory?secret=<INGEST_SECRET>&limit=20
// Returns the latest user-role chat messages. Diagnostic endpoint so Pallav
// can verify what he actually typed vs what Claude stored as a bug
// description. Remove once verbatim-capture is shipped.
exports.peekChatHistory = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.query.userId || EMAIL_USER).toString();
    const limit = parseInt(req.query.limit || '20', 10);
    try {
      const snap = await db
        .collection(`users/${userId}/chat_history`)
        .orderBy('timestamp', 'desc')
        .limit(limit * 3)  // over-fetch because we filter to user role only
        .get();
      const messages = snap.docs
        .map(d => {
          const x = d.data();
          return {
            id: d.id,
            role: x.role || '',
            content: x.content || '',
            input_type: x.input_type || '',
            timestamp: x.timestamp && x.timestamp.toDate
              ? x.timestamp.toDate().toISOString()
              : null,
          };
        })
        .filter(m => m.role === 'user')
        .slice(0, limit);
      return res.json({ messages, count: messages.length });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// POST /patchBug?secret=<INGEST_SECRET>
// Body: { bugId, user_text?, title?, severity?, screen?, userId? }
// Generic field updater — used to backfill `user_text` on bugs that
// predate the verbatim-capture fix, or to correct any misattribution.
exports.patchBug = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.body?.userId || req.query.userId || EMAIL_USER).toString();
    const bugId = (req.body?.bugId || req.query.bugId || '').toString();
    if (!bugId) {
      return res.status(400).json({ error: 'bugId required' });
    }
    const allowed = ['user_text', 'title', 'severity', 'screen', 'description'];
    const update = {};
    for (const f of allowed) {
      if (req.body?.[f] !== undefined) update[f] = req.body[f];
    }
    if (Object.keys(update).length === 0) {
      return res.status(400).json({ error: 'no patchable fields supplied' });
    }
    try {
      await db.doc(`users/${userId}/bugs/${bugId}`).update(update);
      return res.json({ ok: true, bugId, updated: Object.keys(update) });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// POST /reopenBug?secret=<INGEST_SECRET>&bugId=<id>
// Flips a bug back to 'new' — for when Pallav says "nope, still broken".
exports.reopenBug = functions
  .runWith({ invoker: 'public' })
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret || req.headers['x-ingest-secret'];
    const expected = process.env.INGEST_SECRET || '';
    if (!expected || secret !== expected) {
      return res.status(401).json({ error: 'invalid secret' });
    }
    const userId = (req.query.userId || req.body?.userId || EMAIL_USER).toString();
    const bugId = (req.query.bugId || req.body?.bugId || '').toString();
    if (!bugId) {
      return res.status(400).json({ error: 'bugId required' });
    }
    try {
      await db.doc(`users/${userId}/bugs/${bugId}`).update({
        status: 'new',
        fixed_at: admin.firestore.FieldValue.delete(),
      });
      return res.json({ ok: true, bugId, userId });
    } catch (e) {
      return res.status(500).json({ error: String(e.message || e) });
    }
  });

// ─── AI PROXY FUNCTIONS (Rakhi's web PWA only) ──────────────────────────────
//
// Why these exist: Flutter Web bundles env.json straight into the JS. If the
// web build shipped provider API keys, anyone opening devtools on Rakhi's
// PWA URL could read Claude + OpenAI keys and burn her budget. Pallav's
// Android APK keeps the same keys bundled (harder to extract, acceptable
// risk) so his app keeps calling api.anthropic.com / api.openai.com
// directly — these proxies are NEVER hit from Android.
//
// Auth: same X-Ingest-Secret header every other internal endpoint uses.
// The secret is compiled into Rakhi's web build via
// `flutter build web --dart-define-from-file=env.web.json`.
//
// CORS: the deployed PWA lives at https://<project>.web.app; browsers send
// a preflight OPTIONS before every non-simple POST. Allow-origin '*' is
// acceptable because requests must carry the secret header anyway — a
// random origin without the secret gets 401.

const _aiCorsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Ingest-Secret',
  'Access-Control-Max-Age': '3600',
};

function _applyAiCors(res) {
  for (const [k, v] of Object.entries(_aiCorsHeaders)) res.set(k, v);
}

function _checkAiSecret(req, res) {
  const secret = req.headers['x-ingest-secret'];
  const expected = process.env.INGEST_SECRET || '';
  if (!expected || secret !== expected) {
    res.status(401).json({ error: 'invalid secret' });
    return false;
  }
  return true;
}

// POST /aiChat — proxy to Anthropic Messages API.
// Body: exactly the shape claude_service would post to
// api.anthropic.com/v1/messages (model, system, tools, messages,
// max_tokens). Response is forwarded byte-for-byte so the Flutter
// client can parse it with the same ClaudeResponse.fromJson.
exports.aiChat = functions
  .runWith({ invoker: 'public', timeoutSeconds: 60, memory: '512MB' })
  .https.onRequest(async (req, res) => {
    _applyAiCors(res);
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!_checkAiSecret(req, res)) return;

    const anthropicKey = process.env.ANTHROPIC_API_KEY || '';
    if (!anthropicKey) {
      return res.status(500).json({ error: 'ANTHROPIC_API_KEY not configured' });
    }

    try {
      const upstream = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': anthropicKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify(req.body || {}),
      });
      const text = await upstream.text();
      res.status(upstream.status).type('application/json').send(text);
    } catch (e) {
      console.error('[aiChat] upstream error', e);
      res.status(502).json({ error: `upstream: ${e.message || e}` });
    }
  });

// POST /aiTranscribe — proxy to OpenAI Whisper.
// Body JSON (not multipart — easier from the browser):
//   { audioBase64: string, mimeType?: string, language?: string }
// Server rebuilds a proper multipart form and forwards to
// api.openai.com/v1/audio/transcriptions. Returns { transcript }.
exports.aiTranscribe = functions
  .runWith({ invoker: 'public', timeoutSeconds: 60, memory: '512MB' })
  .https.onRequest(async (req, res) => {
    _applyAiCors(res);
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!_checkAiSecret(req, res)) return;

    const openaiKey = process.env.OPENAI_API_KEY || '';
    if (!openaiKey) {
      return res.status(500).json({ error: 'OPENAI_API_KEY not configured' });
    }

    const { audioBase64, mimeType, language } = req.body || {};
    if (!audioBase64) {
      return res.status(400).json({ error: 'audioBase64 required' });
    }

    try {
      const bytes = Buffer.from(audioBase64, 'base64');
      const blob = new Blob([bytes], { type: mimeType || 'audio/webm' });
      const filename =
        (mimeType || '').includes('mp4') ? 'voice.m4a'
          : (mimeType || '').includes('webm') ? 'voice.webm'
          : 'voice.mp3';
      const form = new FormData();
      form.append('file', blob, filename);
      form.append('model', 'whisper-1');
      form.append('response_format', 'text');
      if (language) form.append('language', language);

      const upstream = await fetch(
        'https://api.openai.com/v1/audio/transcriptions',
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${openaiKey}` },
          body: form,
        },
      );
      const text = await upstream.text();
      if (!upstream.ok) {
        console.error('[aiTranscribe] upstream', upstream.status, text);
        return res.status(upstream.status).json({ error: text });
      }
      res.json({ transcript: text.trim() });
    } catch (e) {
      console.error('[aiTranscribe] error', e);
      res.status(502).json({ error: `upstream: ${e.message || e}` });
    }
  });

// POST /aiTTS — proxy to OpenAI /audio/speech.
// Body: { text: string, voice?: string ('echo'|'nova'|...) }
// Returns raw audio/mpeg bytes. AudioService.playFromBytes on web
// feeds these straight to audioplayers' BytesSource.
exports.aiTTS = functions
  .runWith({ invoker: 'public', timeoutSeconds: 60, memory: '512MB' })
  .https.onRequest(async (req, res) => {
    _applyAiCors(res);
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!_checkAiSecret(req, res)) return;

    const openaiKey = process.env.OPENAI_API_KEY || '';
    if (!openaiKey) {
      return res.status(500).json({ error: 'OPENAI_API_KEY not configured' });
    }

    const { text, voice } = req.body || {};
    if (!text) return res.status(400).json({ error: 'text required' });

    try {
      const upstream = await fetch('https://api.openai.com/v1/audio/speech', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${openaiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'tts-1',
          input: text,
          voice: voice || 'echo',
          response_format: 'mp3',
        }),
      });
      if (!upstream.ok) {
        const errText = await upstream.text();
        console.error('[aiTTS] upstream', upstream.status, errText);
        return res.status(upstream.status).json({ error: errText });
      }
      const buf = Buffer.from(await upstream.arrayBuffer());
      res.status(200).type('audio/mpeg').send(buf);
    } catch (e) {
      console.error('[aiTTS] error', e);
      res.status(502).json({ error: `upstream: ${e.message || e}` });
    }
  });
