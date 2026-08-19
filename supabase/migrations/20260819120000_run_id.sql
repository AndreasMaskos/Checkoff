-- Which run an entry belongs to. Two surgeries on the same day used to interleave
-- in the log with nothing to tell them apart; the runner now stamps one id per
-- run and every entry from it carries the same one. Null for older entries.

alter table log_entries add column if not exists run_id uuid;
