// Sends a lab invitation by email, and records it.
//
// Checkoff has no server. This is the one exception, and it exists for one
// reason: sending mail needs a provider's API key, and an API key in a browser
// is a key anyone can read. Everything else stays where it was.
//
// It holds no Supabase service key. The caller's own JWT is forwarded to
// PostgREST, so row level security decides whether this person may invite anyone
// to this lab — the same rule the app obeys, checked by the database rather than
// re-implemented here. A stolen function URL is worth nothing without a lead's
// session behind it.
//
// Deploy:  supabase functions deploy invite
// Secrets: supabase secrets set RESEND_API_KEY=re_...
//          supabase secrets set INVITE_FROM='Checkoff <invites@your-domain>'
//          supabase secrets set APP_URL=https://andreasmaskos.github.io/Checkoff/
// Without RESEND_API_KEY the invite is still recorded and the reply says so, so
// the app falls back to "Email them" rather than breaking.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const esc = (s: string) =>
  s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const auth = req.headers.get("Authorization");
  if (!auth) return json(401, { error: "Sign in first." });

  let labId = "", email = "";
  try {
    ({ labId, email } = await req.json());
  } catch {
    return json(400, { error: "Expected JSON with labId and email." });
  }
  email = (email ?? "").trim().toLowerCase();
  if (!labId || !email.includes("@")) return json(400, { error: "A lab and an email address are needed." });

  // The caller's own client: every query below is filtered by the same policies
  // the app runs under, so this function cannot reach past what the lead can.
  const asCaller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );

  const { data: { user } } = await asCaller.auth.getUser();
  if (!user) return json(401, { error: "That session is not valid." });

  const { data: lab } = await asCaller.from("labs").select("id, name, lead").eq("id", labId).maybeSingle();
  if (!lab) return json(404, { error: "No such lab." });
  if (lab.lead !== user.id) return json(403, { error: "Only the lab's lead can invite people." });

  // Recorded first. The invitation is the row; the email is only how they hear
  // about it, and a send that fails must not lose the invitation with it.
  const { error } = await asCaller.from("lab_invites").insert({ lab_id: labId, email });
  if (error && error.code !== "23505") return json(400, { error: error.message });

  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return json(200, { sent: false, reason: "No mailer is configured for this project." });

  const app = Deno.env.get("APP_URL") ?? "https://andreasmaskos.github.io/Checkoff/";
  const from = Deno.env.get("INVITE_FROM") ?? "Checkoff <onboarding@resend.dev>";
  const lead = user.email ?? "the lab lead";
  const body = `
    <div style="font:16px/1.6 system-ui,-apple-system,'Segoe UI',sans-serif;color:#14181D;max-width:34rem">
      <p>${esc(lead)} has added you to <b>${esc(lab.name)}</b> on Checkoff.</p>
      <p>Checkoff runs a checklist out loud and keeps a log of what was actually done —
         pictures, clips and notes, against the step they belong to.</p>
      <p><a href="${esc(app)}" style="display:inline-block;background:#25874E;color:#fff;
         text-decoration:none;padding:.7rem 1.1rem;border-radius:5px;font-weight:600">Open Checkoff</a></p>
      <p>Sign in with <b>${esc(email)}</b> — create the account there if you have not got one.
         You are in the lab the moment you do; there is nothing to accept.</p>
      <p style="color:#69707A;font-size:.875rem">What you log stays yours. ${esc(lead)}, as lead,
         can see what is logged against the lab's checklists.</p>
    </div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [email], subject: `Join ${lab.name} on Checkoff`, html: body }),
  });
  if (!res.ok) {
    // The invitation stands. Say why the message did not go, rather than
    // reporting success and leaving someone waiting for an email forever.
    return json(200, { sent: false, reason: (await res.text()).slice(0, 200) });
  }
  return json(200, { sent: true });
});
