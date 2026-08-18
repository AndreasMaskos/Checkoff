# Checkoff

Hands-free checklists for daily repetitive tasks. The app speaks a step, you say
"done", it checks it off and speaks the next one — so the routine runs the same
way every time without touching the phone.

Last updated 2026-08-18.

## Where everything is

| Thing | Where |
|-------|-------|
| Live app | https://andreasmaskos.github.io/Checkoff/ |
| Repo | https://github.com/AndreasMaskos/Checkoff (public) |
| Database + auth | Supabase project **CheckoffLists**, `vgrrekmdpfgftuseawze` |
| Hosting | GitHub Pages, `main` branch, root — redeploys ~30s after a push |

## Status

| # | Feature | State |
|---|---------|-------|
| 1 | Checklist CRUD, localStorage | done |
| 2 | Voice control — speaks steps, hears commands | done |
| 3 | Undo | done |
| 4 | Per-step timers | done |
| 5 | PWA — installable, works offline | done |
| 6 | Accounts + sync | done, live |
| 7 | Sharing — copy link and live link | done, live |
| 8 | Deployed to GitHub Pages | done |
| 9 | Sign up / sign in screen — also the start page when signed out | done |
| 10 | Visual design pass | done |
| 11 | Photo log — a picture + description per step, timestamped | done, live |
| — | Supabase Auth → URL Configuration redirect URLs | **verify in dashboard** |

The last row is the one thing that can't be checked from code: magic links and
signup confirmations bounce to Supabase's default `localhost:3000` unless
*Authentication → URL Configuration* lists the Pages URL (and
`http://localhost:8000/` for local work).

## Files

| File | Purpose |
|------|---------|
| `index.html` | The entire app — markup, design, voice, timers, undo, sync, sharing, auth, photo log |
| `config.js` | Supabase URL + publishable key. Empty = sync off, everything else still works |
| `manifest.json` | PWA metadata (installable, standalone, portrait) |
| `sw.js` | Service worker, stale-while-revalidate app shell cache |
| `icon.svg`, `icon-192.png`, `icon-512.png` | App icons (192/512 generated from the SVG with `qlmanage` + `sips`) |
| `supabase/migrations/*.sql` | Schema, in order. Source of truth for the database |
| `supabase/config.toml` | Marks the directory for the Supabase GitHub integration |

One HTML file on purpose: no build step, no bundler, no dependency to keep
current. The only runtime import is supabase-js from esm.sh, and it is loaded
only when `config.js` has credentials.

## Running it locally

Voice and service workers need a secure context — `file://` will not do:

```
python3 -m http.server 8000     # then http://localhost:8000
```

**Tests:** open `index.html#test` and read the console. Asserts cover the voice
command matcher, the `@duration` parser, HTML escaping, the photo downscale
maths, and the sync merge in both directions. No framework, no runner — if
something goes red it prints.

## Data model

**On the device** (`localStorage.checkoff`):

```js
{ lists: [{
    id,          // uuid, stable across devices
    title,
    items,       // array of raw step lines, "Grind beans @40s"
    updatedAt,   // ms epoch, drives last-write-wins
    owner,       // uuid once synced; absent = local-only, treated as mine
    deleted,     // tombstone
    shareToken,  // uuid or absent
    shareMode,   // 'copy' | 'live'
}]}
```

Run state — which steps are checked, elapsed times, the undo stack — is
deliberately **not** in here. It lives in memory for the duration of a run and
never syncs, so two people running the same shared list never collide.

**On the server:** `lists` (one row per checklist), `shares` (one row per member
of a live list) and `log_entries` (one row per logged picture), all under RLS,
plus the private `logs` storage bucket. Full definitions live in the migrations;
don't hand-edit tables in the dashboard or the repo stops describing reality.

## Sync

Last-write-wins **per list**: on sign-in, on every save, and on window focus, the
newer `updated_at` wins in whichever direction. Both devices editing *different*
lists offline is fine. Both editing the *same* list offline loses one side —
per-item merge only if that turns out to happen for real.

`merge()` also drops local lists that are owned by someone else and no longer
returned by the server — that's how "the owner revoked my access" and "I left the
list" clean up. It never drops lists we own, so a failed push cannot eat them.

## Sharing

Two modes, picked per list in the editor.

| Mode | Link does | Recipient gets |
|------|-----------|----------------|
| **Send a copy** | `shared_list(token)` returns the content | An independent list with a fresh id; the two drift apart. No account needed |
| **Share live** | `accept_invite(token)` inserts a `shares` row | Membership of *this* list, with edit rights. Account required |

Same link shape (`…/#share=<uuid>`); the app resolves which mode it is on open.
If a live link is opened while signed out, the token is stashed in
`localStorage.pendingInvite` and redeemed right after sign-in.

Everyone on a live list is an equal editor — no view-only role until someone asks
for one. "Stop sharing" clears the token and removes every member; copies already
made are unaffected.

## Photo log

Evidence of what actually happened, kept per step. On any step of a run, **Photo**
opens the camera or library; the picture is downscaled in the browser to 1600 px
JPEG, shown with an optional description, and saved. **Log** on the home row
lists everything for that checklist, newest first.

```js
log_entries: { id, list_id, owner, step, step_text, note, path, created_at }
```

- `step_text` is a **snapshot**. Renaming a step later must not rewrite what the
  log says was done at the time.
- Images live in the private `logs` bucket as `<list_id>/<uuid>.jpg`. Naming them
  by list is what lets access follow the list: the storage policy runs the same
  `owns_list` / `is_member` check the table does, so everyone on a live-shared
  list keeps **one** shared record instead of one private log each.
- Reads go through 1-hour signed URLs, so an image link can't be forwarded to
  someone outside the list forever.
- Uploads are direct, with no offline queue — the one part of the app that needs
  a signal. Photos taken with no account or no network are not kept.

## Accounts

Email + password sign up and sign in on a dedicated screen, magic link as the
alternative. Signed-out visitors **start** on that screen rather than on an empty
home: `sync()` runs on Supabase's `INITIAL_SESSION` event, so the no-user branch
there is the single place that decides it — and it covers signing out too.

An account is **optional** — "← Back to my checklists" leaves the screen and the
app is fully usable and purely local, minus sync, sharing and the photo log.
Signing in later merges the device into the account rather than replacing it.

## Voice

Say any of these while the mic is on. Both English and German are matched, and
the recognizer's language follows the browser locale.

| Command | Words |
|---------|-------|
| check it off | done, check, chek, yes, ok, complete, erledigt, fertig, ja, passt |
| skip | skip, no, überspringen, nein |
| next / back | next, weiter · back, previous, zurück |
| repeat | repeat, again, nochmal, wiederhol |
| undo | undo, rückgängig |
| stop listening | stop, pause, exit, halt, ende |

Two mechanics that matter: the mic is muted while the app speaks (otherwise it
hears itself and checks off the step it just read), and recognition is restarted
on every `onend` because browsers end it after each phrase of silence.

Matching is substring-on-word-start, so mis-hearings are cheap to absorb: `chek`
is in the list purely because the recognizer produces it.

## Timers and undo

Append `@<duration>` to a step line: `@2m`, `@30s`, `@1:30`, or `@3` for bare
minutes. The countdown sits on the current step, turns red past zero, and the app
says "time is up". Steps without `@` have no countdown, but elapsed time is
recorded for every step and totalled in the completion summary.

Undo is a 20-deep snapshot stack covering checks, skips and navigation, by button
or by voice. It is per run — leaving the runner drops it.

## Design direction

Anchored on the **aviation preflight checklist**, because that is literally the
interaction: challenge, response, next item.

- The runner is a teleprompter, not a checkbox list. Done steps collapse into a
  dense monospace log, the current step fills the viewport for across-the-room
  legibility, upcoming steps sit dimmed below. The premise is that you are *not*
  looking at the phone up close.
- Colour is state, never decoration: green confirms, amber counts down, red is
  overdue. Nothing else is coloured.
- Sans/mono contrast carries the personality instead of a webfont — an
  offline-first PWA should not be fetching fonts.
- `01 / 07` numbering earns its place because a checklist genuinely is a sequence
  and the number is how you find your place again.

## Decisions and gotchas worth remembering

- **RLS policies on `lists` and `shares` must not query each other.** They did,
  and Postgres recursed (42P17) — every read returned 500. Fixed by moving both
  lookups into `security definer` helpers (`is_member`, `owns_list`) in
  `20260811150000_fix_policy_recursion.sql`.
- **Share links resolve through a function, never a policy.** A policy like
  `share_token is not null` would let any signed-in user enumerate everyone's
  shared lists. `security definer` + exact token match cannot leak more than the
  one list whose token the caller already holds.
- **RLS gives a live member write access to the whole row**, which is more than
  "can edit the steps". The `lists_member_guard` trigger is the actual boundary:
  members change content; only the owner transfers, deletes, or mints links.
- **List text is HTML-escaped on render.** Cosmetic until lists could arrive from
  other people; a security boundary from that moment on.
- **The publishable key in `config.js` is public by design** — it identifies the
  project, RLS guards the data. `service_role` must never appear in this repo.
- **Migrations deploy on push to main** via the Supabase GitHub integration.
  Verified working. Always confirm against the live API afterwards
  (`curl $URL/rest/v1/lists?select=id -H "apikey: …"`) rather than trusting it.
- **Storage objects are named by list, not by user** (`<list_id>/<uuid>.jpg`).
  Naming them by uploader would have split a shared checklist's log into private
  piles and made the policy disagree with the table's.
- **`SampleLists/` is gitignored.** The repo is public; those are lab screenshots.
- Icons were generated on macOS with `qlmanage -t -s 512` then `sips -z 192 192`
  — no design tool needed to regenerate them from `icon.svg`.

## Known limits / not built

- Firefox has no Web Speech API — the app says so and falls back to buttons.
- iOS needs one tap on "Start voice" per session; Safari will not open the mic
  without a gesture.
- Wake lock keeps the screen on during a run; unsupported on iOS < 16.4.
- No view-only sharing role, no member list, no way to see who joined.
- No run history, streaks, or reminders/notifications.
- Photo log needs an account and a signal: no offline upload queue, no video, no
  way to log a note without a picture.
- Magic-link email uses Supabase's shared SMTP on the free tier — a few per hour.
  Swap in real SMTP before this is used by anyone but us.

## Plausible next steps

Nothing here is committed to; listed so the reasoning isn't re-derived later.

1. Run history — every completed run with its per-step times; the data is already
   collected, and `log_entries` is now the obvious table to hang it off.
2. Realtime propagation for live lists (`postgres_changes`, ~5 lines) so a shared
   list updates without a focus/sync.
3. Reorder steps by drag, if editing raw lines in the textarea starts to chafe.
4. A "wake word" so the mic can stay off until called, instead of listening for
   the whole run.
5. Offline queue for photo uploads (IndexedDB + flush on focus), if logging in a
   basement without signal turns out to be real rather than hypothetical.
