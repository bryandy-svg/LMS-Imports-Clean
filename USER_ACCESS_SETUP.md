# User Access Setup

The app uses Supabase Authentication. Passwords are handled by Supabase and are never stored in inventory or request records.

## 1. Create the first administrator

In Supabase, open **Authentication > Users > Add user** and create:

- Email / username: `bryan.dy@lmsfm.com`
- Initial password: `Landscape1`
- Auto-confirm user: enabled

Change this password after the first successful login.

The application treats this exact email as the bootstrap administrator and grants it every access checkbox.

## 2. Deploy the user-management function

Deploy `supabase/functions/manage-users` as a JWT-protected Edge Function named `manage-users`.

The function uses Supabase's built-in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` secrets. Never place the service-role key in `index.html`, `user-access.js`, GitHub, or Vercel environment variables exposed to the browser.

## 3. Create other users

Sign in as `bryan.dy@lmsfm.com`, open **Settings > User Access**, enter the new username and temporary password, check every allowed section, and select **Create User**.

Available checkboxes are Dashboard, Inventory, Issued, Borrowed, Requests, Piti Greenwaste Tickets, Alerts, Settings, and Create and Assign Users.
