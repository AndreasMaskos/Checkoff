-- Documents keep their name. A picture is identified by looking at it, a PDF is
-- identified by being called "Anesthesia_protocol_v3.pdf" — the stored object is
-- a uuid, so the original name has to live on the row.

alter table log_entries add column if not exists filename text;
