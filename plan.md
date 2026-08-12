# Checkoff — plan

Hands-free checklists for daily repetitive tasks. Voice checks steps off, app speaks the next one.

## Status

| # | Feature | State |
|---|---------|-------|
| 1 | Checklist CRUD + localStorage | done |
| 2 | Voice control (recognize commands, speak steps) | done |
| 3 | Undo | done |
| 4 | Per-step timers | done |
| 5 | PWA (installable, offline) | done |
| 6 | Accounts + sync | done — needs your Supabase keys in `config.js` |
| 7 | Sharing (send a link, recipient gets their own copy) | done |

## Files

| File | Purpose |
|------|---------|
| `index.html` | The whole app: UI, voice, timers, undo, sync client |
| `config.js` | Supabase URL + anon key. Empty = sync off, everything else still works |
| `manifest.json` | PWA metadata (installable, standalone, portrait) |
| `sw.js` | Service worker, stale-while-revalidate app shell cache |
| `icon-192.png`, `icon-512.png`, `icon.svg` | App icons |

## Feature notes

### Per-step timers
Append `@<duration>` to a step line in the editor:

```
Brush teeth @2m
Cold rinse @30s
Stretch @1:30
Coffee @3          (bare number = minutes)
```

Countdown shows on the current step; at zero the app says "time is up". Steps
without `@` have no countdown. Actual elapsed time per step is recorded either
way and shown in the summary after the run.

### Undo
Button, or say "undo" / "rückgängig". Restores the last 20 states (check, skip,
navigation). Only within a run — closing the run drops the stack.

### Accounts + sync
Supabase magic-link email login. No passwords, no server code of ours.

**Setup (one time):**
1. Create a free project at supabase.com.
2. SQL editor → run:
   ```sql
   create table lists (
     id          uuid primary key,
     owner       uuid not null references auth.users on delete cascade,
     title       text not null,
     items       jsonb not null default '[]',
     share_token uuid,                               -- null = private
     deleted     boolean not null default false,     -- tombstone, so deletes sync
     updated_at  timestamptz not null default now()
   );
   create index on lists (share_token);
   alter table lists enable row level security;

   create policy "owner" on lists for all
     using (auth.uid() = owner) with check (auth.uid() = owner);

   -- Share links resolve through this function, never through a policy: a policy
   -- like "share_token is not null" would let any signed-in user list everyone
   -- else's shared lists. security definer + exact token match does not.
   create function shared_list(token uuid) returns setof lists
     language sql security definer stable set search_path = public as $$
       select * from lists where share_token = token and not deleted
     $$;
   ```
3. Authentication → URL Configuration → add your app's URL to redirect URLs.
4. Settings → API → copy Project URL + anon key into `config.js`.

One row per list. Sync is last-write-wins **per list**: on every save and every
window focus, newer `updated_at` wins in whichever direction. Two devices editing
*different* lists offline is fine; both editing the *same* list offline loses one
side. Per-item merge only if that turns out to happen.

### Sharing
Copy semantics, deliberately: the recipient gets their own independent list and
the two drift apart afterwards. Nobody can edit your list, and running a shared
list never touches anyone else's checkmarks — run state is device-local and
never leaves the browser.

- "Share" on a list mints a `share_token` and hands you `…/#share=<uuid>`
  (native share sheet on phones, clipboard otherwise).
- Opening that link calls `shared_list(token)` and offers to add a copy — new id,
  no token. Works without an account; the copy just lives in that browser.
- "Stop sharing" in the editor clears the token and kills every old link.
  Copies already made are unaffected.

Live shared lists (both people editing one list) are **not** built. If ever
wanted, it's one `shares (list_id, user_id, can_edit)` table plus an
`accept_invite(token)` function — additive, no rewrite.

## Running it

Voice and service workers need a secure context — `file://` won't do it:

```
python3 -m http.server 8000    # then http://localhost:8000
```

For phone use, deploy anywhere with HTTPS (GitHub Pages, Netlify, Vercel — it's
static files) and "Add to Home Screen".

Self-check for the voice command matcher: open `index.html#test`, read the console.

## Known limits / not built

- Firefox has no Web Speech API — app warns and falls back to buttons.
- iOS: mic needs one tap per session, Safari won't open it without a gesture.
- No run history/streaks, no reminders/notifications.
- No live co-editing — sharing is copy-only, by design (see above).
- Wake lock keeps the screen on during a run; not supported on iOS < 16.4.
