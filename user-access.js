(() => {
  const bootstrapAdmin = "bryan.dy@lmsfm.com";
  const allAccess = ["dashboard", "inventory", "issued", "borrowed", "requests", "greenwaste", "alerts", "settings", "manage_users"];
  let authClient = null;
  let currentAccess = [];

  function normalizeUsername(value) {
    const username = String(value || "").trim().toLowerCase();
    return username.includes("@") ? username : `${username.replace(/[^a-z0-9._-]/g, "")}@users.lmsfm.local`;
  }

  function can(permission) {
    return currentAccess.includes(permission);
  }

  function setVisible(selector, visible) {
    document.querySelectorAll(selector).forEach(element => {
      element.hidden = !visible;
    });
  }

  function applyAccess(user) {
    const email = String(user?.email || "").toLowerCase();
    currentAccess = email === bootstrapAdmin ? allAccess : (user?.app_metadata?.access || []);
    setVisible('[data-view-button="dashboard"]', can("dashboard"));
    setVisible('[data-view-button="inventory"]', can("inventory"));
    setVisible('[data-nav-filter="permanent"]', can("issued"));
    setVisible('[data-nav-filter="borrowed"]', can("borrowed"));
    setVisible('[data-view-button="requests"]', can("requests"));
    setVisible('[data-view-button="greenwaste"]', can("greenwaste"));
    setVisible('[data-view-button="alerts"]', can("alerts"));
    setVisible('[data-view-button="settings"]', can("settings"));
    $("userManagementPanel").hidden = !can("manage_users");

    setVisible("#addItemBtn, #importBtn, #exportCsvBtn, #exportJsonBtn, #invoicePdfBtn, #invoiceApprovalsBtn", can("inventory"));
    setVisible("#addRequestBtn", can("requests"));

    const viewPermission = state.view === "inventory" && state.quickFilter === "permanent"
      ? "issued"
      : state.view === "inventory" && state.quickFilter === "borrowed"
        ? "borrowed"
        : state.view;
    if (!can(viewPermission)) {
      state.view = allAccess.find(permission => permission !== "manage_users" && can(permission)) || "dashboard";
      if (state.view === "issued" || state.view === "borrowed") {
        state.quickFilter = state.view === "issued" ? "permanent" : "borrowed";
        state.view = "inventory";
      }
    }
    render();
  }

  async function showSignedIn(user) {
    document.body.classList.remove("role-locked", "request-only", "modal-open");
    applyAccess(user);
    await loadSupabaseOnStart();
  }

  async function initializeAccess() {
    try {
      authClient = await getSupabase();
      const { data } = await authClient.auth.getSession();
      if (data.session?.user) await showSignedIn(data.session.user);
    } catch (error) {
      $("loginStatus").textContent = error.message;
    }
  }

  async function signIn(event) {
    event.preventDefault();
    $("loginStatus").textContent = "Signing in...";
    try {
      authClient ||= await getSupabase();
      const email = normalizeUsername($("loginUsername").value);
      const password = $("loginPassword").value;
      const { data, error } = await authClient.auth.signInWithPassword({ email, password });
      if (error) throw error;
      $("loginPassword").value = "";
      $("loginStatus").textContent = "";
      await showSignedIn(data.user);
    } catch (error) {
      $("loginStatus").textContent = error.message;
    }
  }

  async function signOut() {
    if (authClient) await authClient.auth.signOut();
    currentAccess = [];
    document.body.classList.remove("greenwaste-mobile", "request-only", "modal-open");
    document.body.classList.add("role-locked");
    $("loginStatus").textContent = "Signed out.";
  }

  async function createUser(event) {
    event.preventDefault();
    if (!can("manage_users")) return;
    const access = [...document.querySelectorAll('#newUserAccess input:checked')].map(input => input.value);
    if (!access.length) return $("createUserStatus").textContent = "Select at least one access checkbox.";
    $("createUserStatus").textContent = "Creating user...";
    try {
      authClient ||= await getSupabase();
      const { data, error } = await authClient.functions.invoke("manage-users", {
        body: {
          action: "create",
          username: normalizeUsername($("newUsername").value),
          password: $("newUserPassword").value,
          access
        }
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      $("createUserStatus").textContent = `Created ${data.username}.`;
      event.target.reset();
    } catch (error) {
      $("createUserStatus").textContent = error.message;
    }
  }

  addEventListener("DOMContentLoaded", () => {
    $("userLoginForm").addEventListener("submit", signIn);
    $("logoutBtn").addEventListener("click", signOut);
    $("createUserForm").addEventListener("submit", createUser);
    initializeAccess();
  });
})();
