(() => {
  const bootstrapAdmin = "bryan.dy@lmsfm.com";
  const allAccess = ["dashboard", "inventory", "issued", "borrowed", "requests", "greenwaste", "alerts", "settings", "manage_users"];
  const accessLabels = {
    dashboard: "Dashboard", inventory: "Inventory", issued: "Issued", borrowed: "Borrowed",
    requests: "Requests", greenwaste: "Piti Greenwaste Tickets", alerts: "Alerts",
    settings: "Settings", manage_users: "Create and Assign Users"
  };
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

  function applyAccess(user, storedAccess = null) {
    const email = String(user?.email || "").toLowerCase();
    currentAccess = email === bootstrapAdmin ? allAccess : (storedAccess || user?.app_metadata?.access || []);
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
    setVisible("#mobileRequestBtn", can("requests"));
    setVisible("#mobileAddInventoryBtn, #mobilePdfApprovalsBtn", can("inventory"));
    setVisible("#mobileGreenwasteBtn", can("greenwaste"));

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
    const { data: accessRow } = await authClient.from("user_access").select("access").eq("user_id", user.id).maybeSingle();
    applyAccess(user, accessRow?.access || null);
    await loadSupabaseOnStart();
    if (can("manage_users")) await loadUsers();
    if (can("greenwaste")
      && localStorage.getItem("pitiGreenwasteMobileActive.v1") === "true"
      && matchMedia("(max-width: 650px)").matches) {
      await openMobileGreenwaste();
    }
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
      await loadUsers();
    } catch (error) {
      $("createUserStatus").textContent = error.message;
    }
  }

  async function invokeUserAction(body) {
    authClient ||= await getSupabase();
    const { data, error } = await authClient.functions.invoke("manage-users", { body });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
    return data;
  }

  function userAccessCheckboxes(user) {
    return allAccess.map(permission => `
      <label><input type="checkbox" value="${permission}" ${user.access.includes(permission) ? "checked" : ""}> ${accessLabels[permission]}</label>
    `).join("");
  }

  async function loadUsers() {
    if (!can("manage_users")) return;
    $("userListStatus").textContent = "Loading users...";
    try {
      const data = await invokeUserAction({ action: "list" });
      $("userList").innerHTML = data.users.map(user => `
        <article class="user-row" data-user-id="${user.id}">
          <div class="user-row-head">
            <div><strong>${escapeHtml(user.username)}</strong><div class="muted">${user.isBootstrapAdmin ? "Primary administrator" : `Created ${new Date(user.createdAt).toLocaleDateString()}`}</div></div>
          </div>
          <div class="access-checkboxes">${userAccessCheckboxes(user)}</div>
          <div class="user-row-actions">
            <input type="password" data-user-password minlength="8" placeholder="New password (optional)">
            <button type="button" data-save-user>Save Changes</button>
            <button type="button" class="danger" data-delete-user ${user.isBootstrapAdmin ? "disabled title=\"Primary administrator cannot be deleted\"" : ""}>Delete</button>
          </div>
          <div class="muted" data-user-status></div>
        </article>
      `).join("") || `<div class="muted">No users found.</div>`;
      $("userListStatus").textContent = `${data.users.length} user${data.users.length === 1 ? "" : "s"}`;
    } catch (error) {
      $("userListStatus").textContent = error.message;
    }
  }

  async function handleUserListClick(event) {
    const row = event.target.closest("[data-user-id]");
    if (!row || !can("manage_users")) return;
    const status = row.querySelector("[data-user-status]");
    const id = row.dataset.userId;
    try {
      if (event.target.closest("[data-delete-user]")) {
        if (!confirm("Delete this user? This removes their login but does not delete inventory or tickets.")) return;
        status.textContent = "Deleting user...";
        await invokeUserAction({ action: "delete", id });
        await loadUsers();
        return;
      }
      if (event.target.closest("[data-save-user]")) {
        const access = [...row.querySelectorAll('.access-checkboxes input:checked')].map(input => input.value);
        if (!access.length) throw new Error("Select at least one access checkbox.");
        const password = row.querySelector("[data-user-password]").value;
        status.textContent = "Saving changes...";
        await invokeUserAction({ action: "update", id, access, password });
        status.textContent = "Changes saved.";
        row.querySelector("[data-user-password]").value = "";
        await loadUsers();
      }
    } catch (error) {
      status.textContent = error.message;
    }
  }

  addEventListener("DOMContentLoaded", () => {
    $("userLoginForm").addEventListener("submit", signIn);
    $("logoutBtn").addEventListener("click", signOut);
    $("createUserForm").addEventListener("submit", createUser);
    $("refreshUsersBtn").addEventListener("click", loadUsers);
    $("userList").addEventListener("click", handleUserListClick);
    initializeAccess();
  });
})();
