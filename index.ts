import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json"
};

const allowedAccess = new Set([
  "dashboard", "inventory", "issued", "borrowed", "requests",
  "greenwaste", "alerts", "settings", "manage_users"
]);
const bootstrapAdmin = "bryan.dy@lmsfm.com";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authorization = request.headers.get("Authorization") || "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token) throw new Error("Authentication required.");

    const url = Deno.env.get("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !publishableKey || !serviceRoleKey) {
      throw new Error("Required Supabase environment variables are missing.");
    }
    const callerClient = createClient(url, publishableKey);
    const { data: callerData, error: callerError } = await callerClient.auth.getUser(token);
    if (callerError || !callerData.user) throw new Error("Invalid login session.");

    const caller = callerData.user;
    const callerAccess = Array.isArray(caller.app_metadata?.access) ? caller.app_metadata.access : [];
    const isBootstrapAdmin = String(caller.email || "").toLowerCase() === bootstrapAdmin;
    if (!isBootstrapAdmin && !callerAccess.includes("manage_users")) {
      return new Response(JSON.stringify({ error: "User-management access is required." }), { status: 403, headers: corsHeaders });
    }

    const adminClient = createClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });
    const body = await request.json();

    if (body.action === "list") {
      const { data, error } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (error) throw error;
      const users = data.users.map(user => ({
        id: user.id,
        username: String(user.email || user.user_metadata?.username || ""),
        access: Array.isArray(user.app_metadata?.access) ? user.app_metadata.access : [],
        createdAt: user.created_at,
        isBootstrapAdmin: String(user.email || "").toLowerCase() === bootstrapAdmin
      })).sort((a, b) => a.username.localeCompare(b.username));
      return new Response(JSON.stringify({ users }), { headers: corsHeaders });
    }

    if (body.action === "create") {
      const username = String(body.username || "").trim().toLowerCase();
      const password = String(body.password || "");
      const access = [...new Set(Array.isArray(body.access) ? body.access : [])].filter(value => allowedAccess.has(value));
      if (!username || !username.includes("@")) throw new Error("Enter a valid username.");
      if (password.length < 8) throw new Error("Password must contain at least 8 characters.");
      if (!access.length) throw new Error("Select at least one access checkbox.");
      const { data, error } = await adminClient.auth.admin.createUser({
        email: username,
        password,
        email_confirm: true,
        app_metadata: { access, created_by: caller.id },
        user_metadata: { username }
      });
      if (error) throw error;
      const { error: accessError } = await adminClient.from("user_access").upsert({
        user_id: data.user.id, username, access, created_by: caller.id, updated_at: new Date().toISOString()
      }, { onConflict: "user_id" });
      if (accessError) throw new Error(`User was created, but access storage failed: ${accessError.message}`);
      return new Response(JSON.stringify({ id: data.user.id, username }), { headers: corsHeaders });
    }

    if (body.action === "update") {
      const id = String(body.id || "");
      const access = [...new Set(Array.isArray(body.access) ? body.access : [])].filter(value => allowedAccess.has(value));
      const password = String(body.password || "");
      if (!id) throw new Error("User ID is required.");
      if (!access.length) throw new Error("Select at least one access checkbox.");
      if (password && password.length < 8) throw new Error("Password must contain at least 8 characters.");
      const { data: existing, error: lookupError } = await adminClient.auth.admin.getUserById(id);
      if (lookupError || !existing.user) throw lookupError || new Error("User not found.");
      const attributes = {
        app_metadata: { ...(existing.user.app_metadata || {}), access },
        password: password || undefined
      };
      const { data, error } = await adminClient.auth.admin.updateUserById(id, attributes);
      if (error) throw error;
      const username = String(data.user.email || data.user.user_metadata?.username || "");
      const { error: accessError } = await adminClient.from("user_access").upsert({
        user_id: id, username, access, created_by: caller.id, updated_at: new Date().toISOString()
      }, { onConflict: "user_id" });
      if (accessError) throw accessError;
      return new Response(JSON.stringify({ id, username }), { headers: corsHeaders });
    }

    if (body.action === "delete") {
      const id = String(body.id || "");
      if (!id) throw new Error("User ID is required.");
      if (id === caller.id) throw new Error("You cannot delete your own signed-in account.");
      const { data: existing, error: lookupError } = await adminClient.auth.admin.getUserById(id);
      if (lookupError || !existing.user) throw lookupError || new Error("User not found.");
      if (String(existing.user.email || "").toLowerCase() === bootstrapAdmin) {
        throw new Error("The primary administrator cannot be deleted.");
      }
      const { error } = await adminClient.auth.admin.deleteUser(id);
      if (error) throw error;
      return new Response(JSON.stringify({ id, deleted: true }), { headers: corsHeaders });
    }

    throw new Error("Unsupported action.");
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      status: 400,
      headers: corsHeaders
    });
  }
});
