-- Who the run was about. An animal, a patient, a sample — a name to recognise it
-- by and the id it is filed under, which are not the same thing and are looked up
-- by different people. Free text on purpose: every lab numbers its subjects its
-- own way, and a lookup table would be a second thing to keep in step.
--
-- Both columns are optional. A checklist for grinding coffee has no subject, and
-- being asked for one every run is how a field stops being filled in honestly.

alter table log_entries add column if not exists subject    text;
alter table log_entries add column if not exists subject_id text;
alter table runs        add column if not exists subject    text;
alter table runs        add column if not exists subject_id text;
