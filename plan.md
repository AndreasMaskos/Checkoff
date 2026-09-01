# Checkoff

Hands-free checklists for daily repetitive tasks. The app speaks a step, you say
"done", it checks it off and speaks the next one — so the routine runs the same
way every time without touching the phone.

Last updated 2026-08-31.

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
| 9 | Sign up / sign in screen — required, and the only screen when signed out | done |
| 10 | Visual design pass | done |
| 11 | Photo log — picture or clip + description per step, timestamped | done, live |
| 12 | Log keeps deleted entries until permanently deleted | done, live |
| 13 | Log search, date range and sort order, per checklist and across every log | done, live |
| 19 | Log opens on the last week, Load another month reaches further back | done, live |
| 20 | Storage bar on the Account page — bytes used against the free tier's 1 GB | done, live |
| 21 | Descriptions grow to fit; stuck uploads can be discarded from home | done, live |
| 22 | Retrospective entry — a capture, and the run around it, dated to when it happened | done, live |
| 23 | An entry is one unit with several files (`group_id`) | done, live |
| 24 | Subject on the run — animal, patient or sample, by name and by id | done, live |
| 25 | Day headings and This week / Last week / This month; a run's own log; Copy as text | done, live |
| 14 | Purge of a deleted checklist and its log | done, live |
| 15 | Export of the filtered log — standalone HTML or CSV | done, live |
| 16 | Offline upload queue, run ids, notes without a picture | done, live |
| 17 | Dictated descriptions, run history | done, live |
| 18 | Account page (email, password), editable log entries | done, live |
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
| `sw.js` | Service worker: the page is network-first, the rest stale-while-revalidate |
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

**Sync only ever redraws the home screen.** It runs on window focus and on token
refresh, so redrawing unconditionally threw you back to the index every time you
returned to the tab — out of a log, out of a half-typed edit. `show()` records
which screen is up and `sync()` respects it.

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

Evidence of what actually happened, kept per step. On any step of a run,
**Add file** opens the camera, the library or the files app and takes anything —
pictures, clips, a protocol PDF, a spreadsheet of measurements. A picture is
downscaled in the browser to 1600 px JPEG; a clip goes up as it was shot and a
document untouched, because those are bytes we have no business rewriting.
`kindOf()` decides video/image/file from the extension, and documents keep their
original name in `filename` — a picture is identified by looking at it, a PDF by
being called `Anesthesia_protocol_v3.pdf`, and the stored object is a uuid. In
the log a document is a named link that opens in a new tab. Either is shown with an
optional description before saving. **Several files can be picked at once** — one
step often needs the PSLAX, the four-chamber and the doppler trace — and they
share the one description while each becomes its own entry, so any of them can be
edited, moved to another step or deleted on its own. **Log** on the home row lists everything for
that checklist, newest first. **Files logged together are one entry with a row of
thumbnails**, because that is what they were: one action. `group_id` is what
says so — every file of one save gets the same one — and they remain separate
rows, so each is still shown, moved and deleted on its own; a file's Edit and
Delete appear when it is expanded. **The description and the timestamp belong to
the entry**, one text over the row of thumbnails, so editing either carries to
every file in it. Changing the **step** is the one edit about a single file:
that file leaves with a group of its own, which is the point of moving a picture
to the step it belongs on.

The card used to be *derived* — same run, same step, same minute, same
description — and every per-file edit re-derived it differently. Correcting the
description while adding a picture was enough to walk that file out of its own
card, and the same moment appeared twice in the log, then three times. A
timestamp rounded to the minute by the When field did it too. An id settles what
belongs together; nothing an edit does to one row can change its mind. Clicking a thumbnail expands it across the row,
clicking a picture again shrinks it, and a collapsed clip has a transparent
overlay so the first tap expands it rather than landing on the play button.

```js
log_entries: { id, group_id, list_id, owner, subject, subject_id, step, step_text, note, path, created_at, deleted_at }
```

**Entries are editable.** A dictated description comes out wrong, a picture gets
taken one step late, a better one is shot afterwards — **Edit** on your own entry
changes the description, which step it belongs to (a dropdown of the checklist's
current steps, with `step_text` re-snapshotted from the one picked), and the files
themselves: tick to delete this picture, pick any number to add. The first
addition fills the entry if it has none; the rest become their own entries sharing
the step, run, description and timestamp, so each stays separately editable.
Additions upload before the row moves and the dropped file is deleted last, so a
row never points at a file that is not there. Deleting the only picture of an
entry with no description is refused — that is deleting the entry, and there is a
button for that. Online only: an edit is a correction, not a capture, so it does
not go through the offline queue.

**Deleting is two stages, because a log is a record.** "Delete" only sets
`deleted_at`: the entry stays in the log, struck through and dated, and its
button becomes "Delete permanently" — the only thing that removes the file and
the row. There is no restore; hiding it *was* the reversible half.

Deleting a *checklist* never buries its log either. Tombstoned lists are listed
on home under "Deleted checklists — logs kept", reachable for their log only.
Their log view carries the one button that ends it: **Delete checklist and log
permanently** removes the stored files, then the `lists` row — `log_entries` and
`shares` cascade off it, so the files are the only part done by hand.

**Who the run is about.** An animal, a patient, a sample: a **name** and an **id**,
because they are looked up by different people and are not the same thing. Set
from the runner — the eyebrow beside the step counter, blank until it is used —
and carried by the run, so every capture after it is stamped without being asked
again and the name stays on screen while you log, which is the whole reason to
ask. Both are free text and both are optional: a checklist for grinding coffee
has no subject, and being asked every run is how a field stops being filled in
honestly. They live on `log_entries` *and* on `runs`, are correctable in the
entry editor like the description, and carry to the rest of the entry the same
way. Names of people end up here, so they sit under the same RLS as everything
else and are visible to everyone on a live-shared checklist — worth knowing
before a patient name goes in one.

**Search** filters by description, step text, checklist name, subject, subject id
*and* the run — `searchable()` puts the run id in twice, bare so the tag printed
on the card (`0b03`) finds it and behind the word so `run 0b03` does too. **Show
this run's log** on the Runs screen is exactly that search, with the seven-day
window opened up first, since an old run would otherwise land on an empty log.
It is narrowed by an
optional **From**/**To** date range (native `<input type="date">`, both ends
inclusive, either end optional), all client-side over the rows already fetched.
Dates compare on the reader's local day, so a picture taken at 23:30 belongs to
that evening rather than to the next UTC one. Deleting patches those rows in
place instead of refetching, so the filters survive it.

Under a date order the log reads as a journal, so it gets a journal's **day
headings** — the full date and how many entries fall on it. Under step or
checklist order they are left out: the days are interleaved by definition there,
and a day heading would be a lie. **This week · Last week · This month · Last month** set From and To to the four
ranges actually asked for; the week starts on Monday, because a working week
does, and last month is `new Date(y, m, 0)` — day zero of this month is the last
day of the one before, the only spelling that survives January.

**Every preset closes both ends.** They used not to: "this month" ran from the
1st to whenever, which for most of a month is the same window the log already
opens on, so pressing it left the rows exactly as they were and read as a dead
button. A bounded window shows that period and nothing else, and moves both date
fields where you can see it. The pressed button is lit and a line reads
**"4 entries · Monday, 24 August 2026 to Sunday, 30 August 2026"** — a filter has
to say what it did rather than leave it to be inferred from the list moving, and
the line answers it for a typed date and Load another month too. One `ranges()`
table sets the dates and decides which button is lit, so the two cannot drift.

The log **opens on the last seven days** — the question is nearly always "what
happened today" — and **Load another month** walks *From* back one calendar month
per tap, hiding itself once nothing older exists. It is the same From filter, not
pagination: every row was fetched already, so the button costs no request, and
typing a date or hitting Clear overrides it. Revisit when a fetch of everything
stops being free, which is the same threshold that moves search into PostgREST.

A **description field grows with what is in it** — capture and correction alike
— up to 40vh, past which it scrolls. They were single-line `<input>`s, so a
dictated sentence scrolled all but its tail out of sight, which is the one place
you cannot proofread by hand. One delegated `input` listener covers the field the
entry editor builds later; setting `.value` in code fires no such event, so
dictation and both openers call `grow()` themselves. A hidden field measures
zero, so the call comes after the panel is shown, never before.

**Discard stuck uploads** appears on home when a flush rejects something for a
reason retrying will not fix. It offers only what actually failed — a queue
waiting out a dead network is never swept up with it — asks first, and says
plainly that the description goes too, not only the file. Home only: the runner
is no place for a destructive button, on the same reasoning that hides Back
there. Nothing about it is automatic except the zero-byte case, which no retry
could ever save.

**A log can be written after the fact.** Sunday's run gets entered on Monday
when Sunday ran late, so the capture panel carries a **When it happened** field
(native `datetime-local`, defaulting to now) and `created_at` is whatever it
says. The first backdated save of a run sets `run.shift`, the offset between the
chosen time and the clock: every later capture of that run opens on the same
day, and `saveRun` shifts `started_at`/`finished_at` by it too, so a run and its
pictures never land a day apart. The offset lives on the run and dies with it —
the next run starts at now again. **Edit** carries the same field, so a
timestamp is correctable like the description and the step; entries split off an
edit inherit the corrected time, not the original.

The field is only written back **when it was actually changed**. It shows whole
minutes, so saving an untouched edit would round 21:00:37 down to 21:00 and drop
that file out of the card its siblings are still in. Rows that already
diverged were repaired by the backfill in `20260901090000_entry_group.sql`,
which grouped by run, owner, step and minute — everything the old rule used
except the description, since a description pulled apart is exactly the damage.

Nothing validates the date beyond it being one. A run entered for next Tuesday
sorts to the top of the log and stays there, which is the reader's problem to
notice — a `max` on the field would have to be rewritten every minute to still
mean "now".

The signed-in **address in the masthead is the way to the account page**, from
any screen. It is a real `<button>` rather than a span with a click handler, so
it focuses and answers Enter. It is inert on the runner for the same reason Back
is hidden there — leaving that way would drop the run rather than bank it — and
inert signed out, where "offline" is a state and not a destination.

The **Account page** shows storage used as a native `<progress>` bar against the
free tier's 1 GB, red past 80%. The sum comes from `log_storage_used()`, a plain
invoker-rights function over `storage.objects.metadata->>'size'` — the existing
"log objects" policy scopes the select, so the total is filtered by the same rule
that decides what you can download, with no `security definer` to keep in step.
The quota is per project rather than per user, so on a project with more than one
person this reads as your share and not the whole bill. `QUOTA` in `index.html`
is the only thing to change on a paid plan.

**Export** writes exactly what is on screen — same filters, same order — as one
self-contained HTML file: pictures inlined as data URIs, so it opens anywhere,
prints to PDF and survives in a lab notebook. Signed URLs would be dead in an
hour, which is why nothing is linked. Clips are listed by name, not embedded: a
50 MB video base64s to 67 MB. The filter and sort live in `shownEntries()`, so
the export and the view cannot disagree about what "the filtered logs" means.

**Export CSV** is the same rows as a spreadsheet — when (local *and* ISO),
checklist, step number, step, description, photo/video, file name, deleted. Every
field is quoted so a description with a comma, a quote or a newline round-trips,
and the file starts with a BOM, which is what makes Excel read it as UTF-8
instead of mangling umlauts. Separator is a comma; German Excel may want the
import dialog for that.

**Copy as text** puts the same rows on the clipboard as plain Markdown — day
headings, one bold meta line per entry, the description, the file names. HTML is
for the notebook and CSV is for the spreadsheet; neither is what gets pasted into
a message on a Friday afternoon.

**Order** is the reader's choice: newest first (the default), oldest first, by
step — which groups every run's picture of the same step together — or by
checklist. It sticks while you move between logs; only Clear resets it.

**"Search all logs"** on home is the same screen with `showLog(null)`: no
`list_id` filter, every entry labelled with the checklist it came from. One fetch
and one signing call for the lot — fine while entries number in the hundreds; the
filter moves into PostgREST (`or(note.ilike…)`) when they run to thousands.

- `step_text` is a **snapshot**. Renaming a step later must not rewrite what the
  log says was done at the time.
- **Video is not transcoded**, only size-capped at 50 MB client-side (Supabase's
  free-tier per-object limit). Transcoding in-browser means ffmpeg.wasm, which is
  more code than the whole app. Record shorter clips instead.
- The file **extension** is what tells a clip from a picture on the way back
  down (`isClip`), rather than a mime column on the table — one regex, no
  migration, and the extension is already in the path.
- Files live in the private `logs` bucket as `<list_id>/<uuid><ext>`. Naming them
  by list is what lets access follow the list: the storage policy runs the same
  `owns_list` / `is_member` check the table does, so everyone on a live-shared
  list keeps **one** shared record instead of one private log each.
- Reads go through 1-hour signed URLs, so an image link can't be forwarded to
  someone outside the list forever.
- **Nothing uploads directly.** Every capture is written to IndexedDB first and
  uploaded second, flushed on save, on window focus, on the `online` event and at
  boot. A picture you cannot retake must not depend on the network being up at
  that second. `created_at` carries when it happened, not when it arrived.
- The queue id **becomes the row id**, so a retry after a half-finished upload
  collides on the primary key (23505, treated as success) instead of logging the
  same thing twice.
- **`run_id`** ties every entry from one run together — two surgeries on the same
  day used to interleave with nothing to tell them apart. Shown as a four-character
  tag in the log, exported in full.
- **A note needs no picture.** "Bleeding at 12:04" is a log entry; `path` stays null.

## Run history

Every run that had at least one step checked or skipped is kept: one `runs` row
keyed by the same `run_id` its log entries carry, holding each step's state and
elapsed seconds.

```js
runs: { id, list_id, owner, title, subject, subject_id, started_at, finished_at, steps: [{ text, state, secs }] }
```

Written twice — on completion and on the way out — and **upserted**, so finishing
a checklist and then exiting is one row rather than two. It rides the same
offline queue as the captures, keyed by the run id so a second save replaces the
first in the queue instead of stacking. Both timestamps carry the run's
backdate offset, so a run logged for Sunday is filed under Sunday. **Runs** on the home row shows them
newest first, with the per-step times and what got skipped.

## Accounts

Email + password sign up and sign in on a dedicated screen, magic link as the
alternative. Once in, **Account** on home changes the email address (confirmed by
a link to the new inbox; the old one keeps working until then), changes the
password, and signs out.

**Both changes require the current password.** Supabase's `updateUser` will
change the email or the password of any live session without asking for the old
one — an unlocked phone left on a bench would be enough, and moving the address
away is the worse of the two, since a password reset follows it. `proveIdentity()`
signs in with the given password first; a wrong attempt returns
`invalid_credentials` and leaves the existing session untouched (checked against
the live API, not assumed). An account is **required**: signed out, the sign-in screen is the
only screen, with no way past it.

The gate is one line in `show()`, the funnel every section change already goes
through — `if (sb && !user && id !== 'auth') id = 'auth'` — rather than a check
in each caller, so a new screen cannot forget it. Boot awaits `getSession()`
before the first render, otherwise every signed-in load flashes the sign-in
screen while the session restores.

Two deliberate exceptions. `sb && ` — with no credentials in `config.js` there is
nothing to sign in to, and the app stays a purely local checklist. And
`offlineOK()`: an access token lasts an hour and cannot be refreshed with no
signal, so a device that has signed in before (`localStorage.lastUser`) gets in
while `navigator.onLine` is false. Without that, the wall would lock you out in
exactly the basement the upload queue exists to survive. Sync and the logs stay
unavailable there; capturing does not, because the queue holds it.

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

**Dictation** reuses the same recognizer for the log's description field —
gloved hands cannot type. Command recognition stops while dictating (or "done"
in a sentence would check the step off) and resumes afterwards if it was on.
Tapping **Note** starts dictation immediately: a note is words, and that tap is
the user gesture iOS requires before opening the microphone.

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
  Allow ~40–90s: a check run straight after the push reports the old schema.
- **`grant execute … to authenticated` restricts nothing.** Supabase's default
  privileges already grant execute on new `public` functions to `anon` *and*
  `authenticated` by name, and Postgres adds its own grant to `PUBLIC`. A
  function that should not answer signed-out callers needs `revoke execute …
  from public` *and* `from anon`; revoking only `PUBLIC` leaves anon's own grant
  untouched, which is exactly what `log_storage_used()` did for two commits.
  Caught only because the live-API check above was actually run.
- **Storage stays on Supabase** (decided 2026-08-19). Backblaze B2 is ~3.5× cheaper
  per GB, but it has never heard of our users: access control would move out of the
  Postgres policies into an Edge Function we maintain, and a presigned URL bypasses
  RLS by construction. Pro includes 100 GB, so B2 saves nothing below that and about
  $5/month at 500 GB. Revisit past ~1 TB, and only for video — `log_entries` stores a
  path, so pointing clips at another bucket stays a contained change.
- **Storage objects are named by list, not by user** (`<list_id>/<uuid>.jpg`).
  Naming them by uploader would have split a shared checklist's log into private
  piles and made the policy disagree with the table's.
- **`SampleLists/` is gitignored.** The repo is public; those are lab screenshots.
- **The page is network-first in the service worker.** Stale-while-revalidate
  served the *previous* deploy on every first load, which reads as "my change is
  not there" and wastes a debugging session. The cached copy is still the offline
  fallback; only the freshness order changed.
- Icons were generated on macOS with `qlmanage -t -s 512` then `sips -z 192 192`
  — no design tool needed to regenerate them from `icon.svg`.

## Known limits / not built

- Firefox has no Web Speech API — the app says so and falls back to buttons.
- iOS needs one tap on "Start voice" per session; Safari will not open the mic
  without a gesture.
- Wake lock keeps the screen on during a run; unsupported on iOS < 16.4.
- No view-only sharing role, no member list, no way to see who joined.
- No streaks or reminders/notifications, and no export of run history — the log
  exports, the timings do not.
- Run history has no subject/animal id: a run is identified by its start time and
  a four-character tag, not by what it was performed on.
- A queued item the server permanently refuses is skipped so the rest still
  upload, but it is retried in full — blob and all — on every flush. No try
  counter and no way to drop it by hand. The badge names the first error and
  counts how many are stuck; being offline stops the flush and keeps the lot.
- A capture is read into memory at pick time, not queued as the `File`. Safari
  stores a File in IndexedDB as a reference to the camera's temp file, iOS
  reclaims it, and the queue is left holding zero bytes — which is what stranded
  eleven clips before 2026-08-28. A queued item that still reads back empty is
  dropped on the next flush and counted in the badge, since no retry can fix it.
  The cost is that a 50 MB clip is held in memory while it is being described.
- Queued captures are on **that device only** until they upload — a second phone
  cannot see them, and clearing site data drops them.
- An iPhone records `.mov`/HEVC. Safari plays it back fine; a Windows Chrome
  viewing the same shared log may not. No transcoding, so that is a real limit.
- Lists made on a device before signing in still exist locally and merge upward
  on the first sync — the sign-in wall is a gate on the UI, not a wipe.
- Log entries have no restore and no bulk purge: deleted ones accumulate until
  each is permanently deleted by hand. Fine at lab volume, revisit at thousands.
- Search matches plain substrings — no fuzzy matching.
- Export is HTML or CSV: no zip of the original files, and videos are named
  rather than included. Exporting many photos builds the whole file in memory.
- Purging a checklist from one device can be undone by another that still holds
  the tombstone: its next sync re-pushes an empty shell. The log stays gone.
- Magic-link email uses Supabase's shared SMTP on the free tier — a few per hour.
  Swap in real SMTP before this is used by anyone but us.

## Plausible next steps

Nothing here is committed to; listed so the reasoning isn't re-derived later, and
ranked by when the lack would be felt rather than by how interesting it is to
build. The readable version, with the reasoning per item, is the roadmap page:
https://claude.ai/code/artifact/a87df55d-2795-4b4b-90ae-d920b6350869

| # | Thing | Cost |
|---|-------|------|
| 1 | Log an entry without running a checklist — a note needs a run today, so writing up a past day means starting and quitting one | afternoon |
| ~~2~~ | ~~Open one run's files from the Runs screen; make the run tag a search term~~ — done | — |
| ~~3~~ | ~~Day headings, and This week / Last week / This month~~ — done | — |
| 4 | `@photo` on a step line, same grammar as `@40s`: the step will not close without a file | hour |
| 5 | A recorded audio note (`MediaRecorder`) — dictation needs a quiet room, a scrub room is not one, and the log already stores files | afternoon |
| 6 | "Log this again" on an entry: same text and step, dated today | hour |
| ~~7~~ | ~~A subject on the run, shown and exported~~ — done, with a name and an id, for animals and people | — |
| 8 | What is using the gigabyte: largest files, per checklist, with a way to pull one down and remove it. Clips are stored as shot | afternoon |
| 9 | A deviation flag on an entry — red in the log, a column in the CSV | afternoon + migration |
| 10 | Which steps keep getting skipped, across runs. The `runs` rows already hold it | afternoon |
| ~~11~~ | ~~Copy the filtered log as Markdown~~ — done | — |
| 12 | A wake word, so the mic is not listening for the whole run | afternoon |
| 13 | Realtime propagation for live lists (`postgres_changes`, ~5 lines). Only worth it once a list is really shared | hour |
| 14 | Drag to reorder steps, if editing raw lines in the textarea starts to chafe | afternoon |
| 15 | **Numbers, not sentences** — a step that captures a value and a unit, so the CSV has columns to plot. The one that changes the data model | project |
| 16 | Take everything out in one archive — lists, entries, runs, files. A record you cannot carry out is not a record | weekend |
| 17 | A read-only role, and a witness signature on a finished run | weekend |
| 18 | Annotate a picture on a canvas, saved as a second file so the original survives | weekend |
| 19 | Move search and the date range into PostgREST, when hundreds become thousands | afternoon, later |

**Deliberately not building.** A native app (the PWA installs, records, works
offline, and updates 30s after a push). Video transcoding (ffmpeg.wasm is larger
than the app — record shorter clips). Push reminders (iOS web push needs the app
installed and still under-delivers; a repeating calendar event does it today). A
formatting toolbar (descriptions are dictated with gloves on). Charts in the app
(the statistics happen elsewhere; the CSV is the interface). A build step (one
file with no bundler is why a fix is live in thirty seconds).
