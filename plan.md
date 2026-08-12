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
| 6 | Accounts + sync | done — live on project CheckoffLists |
| 7 | Sharing — copy link and live link | done |
| 8 | Deploy | live at https://andreasmaskos.github.io/Checkoff/ |
| 9 | Sign up / sign in screen (password + magic link) | done |
| 10 | Visual design pass | done |

Schema changes go in `supabase/migrations/` and are applied to the production
database by the GitHub integration on push to main — don't hand-edit tables in
the dashboard, or the repo stops describing reality.

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

**Setup (already done for project CheckoffLists — kept for reference / a second project):**
1. Create a free project at supabase.com.
2. Push `supabase/migrations/*.sql`, or paste the same SQL into the SQL editor:
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
Two modes, chosen per list in the editor. Either way, run state — what is
checked off right now — is device-local and never syncs, so two people running
the same list never touch each other's checkmarks.

| Mode | Link does | Recipient |
|------|-----------|-----------|
| **Send a copy** | `shared_list(token)` returns the content | Gets an independent list with a fresh id; the two drift apart. No account needed |
| **Share live** | `accept_invite(token)` inserts a `shares` row | Joins *this* list and can edit it. Needs an account |

Everyone on a live list is an equal editor — no view-only role until someone
asks for one. RLS grants members write access to the whole row, which is more
than we mean, so the `lists_member_guard` trigger is the real boundary: members
change content, only the owner transfers, deletes, or mints links.

"Stop sharing" clears the token and removes every member. Copies already made
are unaffected.

**Watch out:** policies on `lists` and `shares` must not query each other
directly — that recursed (42P17) and 500'd every read until
`20260811150000_fix_policy_recursion.sql` moved both lookups into
`security definer` helpers (`is_member`, `owns_list`).

### Accounts
Email + password sign up and sign in on a dedicated screen, magic link as the
alternative. An account is optional: with no account the app is fully usable and
purely local. Signing in merges what's on the device with what's on the server.

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
