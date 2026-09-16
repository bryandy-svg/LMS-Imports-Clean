import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json"
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    if (request.method !== "POST") throw new Error("POST is required.");
    const authorization = request.headers.get("Authorization") || "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token) throw new Error("Authentication required.");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const publishableKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("TICKET_EMAIL_FROM") || "LMS Piti Greenwaste <onboarding@resend.dev>";
    if (!resendApiKey) throw new Error("RESEND_API_KEY is not configured.");

    const client = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: `Bearer ${token}` } }
    });
    const { data: userData, error: userError } = await client.auth.getUser(token);
    if (userError || !userData.user) throw new Error("Invalid login session.");
    const access = Array.isArray(userData.user.app_metadata?.access) ? userData.user.app_metadata.access : [];
    if (!access.includes("greenwaste")) {
      return new Response(JSON.stringify({ error: "Piti Greenwaste access is required." }), { status: 403, headers: corsHeaders });
    }

    const body = await request.json();
    const to = String(body.to || "").trim().toLowerCase();
    const subject = String(body.subject || "Piti Greenwaste Ticket").trim().slice(0, 200);
    const fileName = String(body.fileName || "Piti-Greenwaste-Tickets.pdf").replace(/[^a-zA-Z0-9_. -]/g, "_").slice(0, 160);
    const pdfBase64 = String(body.pdfBase64 || "");
    const ticketIds = Array.isArray(body.ticketIds) ? [...new Set(body.ticketIds.map(String))] : [];
    if (!emailPattern.test(to)) throw new Error("A valid recipient email is required.");
    if (!ticketIds.length) throw new Error("At least one ticket is required.");
    if (!pdfBase64 || pdfBase64.length > 35_000_000) throw new Error("The PDF attachment is missing or too large.");

    const { data: tickets, error: ticketError } = await client
      .from("greenwaste_tickets")
      .select("id")
      .in("id", ticketIds);
    if (ticketError) throw ticketError;
    if ((tickets || []).length !== ticketIds.length) throw new Error("One or more selected tickets are unavailable.");

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `piti-${ticketIds.join("-").slice(0, 180)}-${to}`
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject,
        html: `<p>Please find the attached Piti Greenwaste ticket${ticketIds.length === 1 ? "" : "s"}.</p><p>Landscape Management Systems, Inc.</p>`,
        attachments: [{ content: pdfBase64, filename: fileName }]
      })
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result?.message || result?.error || "The email provider rejected the message.");
    return new Response(JSON.stringify({ id: result.id, sent: true }), { headers: corsHeaders });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      status: 400,
      headers: corsHeaders
    });
  }
});
