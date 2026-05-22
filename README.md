# Inventory Monitor

A standalone inventory monitoring app that runs from one static `index.html` file. It tracks item details, photos, quantity, reorder points, locations, suppliers, PO numbers, source/from details, costs, expiry dates, ownership, documents, permanently issued items, borrowed items, return dates, approvals, request approvals, notes, stock adjustments, alerts, exports, imports, and optional Supabase sync.

## Use Locally

Open `index.html` in a browser. The app saves data to local storage until Supabase is connected.

## Deploy To Vercel

1. Push this folder to GitHub.
2. In Vercel, import the GitHub repository.
3. Use the default static deployment settings.

## Connect Supabase

1. Create a Supabase project.
2. Open the SQL editor.
3. Run `supabase-schema.sql`.
4. Open the app settings screen.
5. Add the Supabase URL, anon key, table name `inventory_items`, and request table name `inventory_requests`.
6. Set Sync Mode to **Supabase enabled**.
7. The app will load from Supabase and save changes automatically.

The SQL creates two tables: `inventory_items` for the item register and `inventory_requests` for borrow/issue requests that can be approved or denied inside the app.

Use **Pull From Supabase** only when you want to manually reload the online copy. Use **Push Local Copy** only when you have local browser data that needs to be uploaded.

The default SQL policies allow browser-side anon access for simple deployment. For production, tighten the row level security policies around authenticated users or your organization rules.

Photos are stored as compact browser data URLs inside each item's payload. Keep photos under 2 MB for smooth local storage, export, and Supabase sync.

## Files

- `index.html` - complete standalone inventory monitoring app.
- `supabase-schema.sql` - Supabase table, indexes, and starter policies.
- `vercel.json` - static deployment routing.
- `.gitignore` - common local files to leave out of Git.
