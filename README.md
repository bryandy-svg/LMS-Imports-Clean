# Mall Lot Inventory

A standalone inventory monitoring app that runs from one static `index.html` file. It tracks item details, photos, quantity, reorder points, locations, suppliers, PO numbers, source/from details, costs, expiry dates, ownership, documents, permanently issued items, borrowed items, multi-item requests, return dates, approvals, drawn signatures, request approvals, notes, stock adjustments, alerts, exports, imports, and optional Supabase sync.

## Use Locally

Open `index.html` in a browser. The app saves data to local storage until Supabase is connected.

For the mobile screen, open the same app with `?request=1` at the end of the URL. Example: `https://your-vercel-site.vercel.app/?request=1`. This shows only two options: Request Items, or Add Inventory with the password set in Settings.

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

The SQL creates two tables: `inventory_items` for the item register and `inventory_requests` for borrow/issue requests that can be approved or denied inside the app. Request records support multiple items, drawn signatures, and request photos.

Use **Pull From Supabase** only when you want to manually reload the online copy. Use **Push Local Copy** only when you have local browser data that needs to be uploaded.

The default SQL policies allow browser-side anon access for simple deployment. For production, tighten the row level security policies around authenticated users or your organization rules.

Photos are stored as compact browser data URLs inside each item's payload. Keep photos under 2 MB for smooth local storage, export, and Supabase sync.

## Files

- `index.html` - complete standalone inventory monitoring app.
- `supabase-schema.sql` - Supabase table, indexes, and starter policies.
- `vercel.json` - static deployment routing.
- `.gitignore` - common local files to leave out of Git.
# Piti Greenwaste email setup

The ticket form includes customer email and contact number fields. Individual tickets and the currently filtered ticket set can be emailed as PDF attachments.

The Billing section supports CY, TON, LB, LOAD, EACH, and FLAT pricing. The saved-ticket filters can be consolidated into a billing summary PDF or exported to CSV for Excel. Run the latest `supabase-ticket-contact-upgrade.sql` before uploading the updated site so the billing fields can sync.

The login screen also provides **Mobile Request — No Login Required**. This opens only the phone-friendly request form, reads only requestable inventory, and submits the completed request without exposing the authenticated dashboard or Greenwaste tickets.

1. In Supabase SQL Editor, run `supabase-ticket-contact-upgrade.sql`. It only adds two nullable columns and preserves all existing data.
2. Create a Resend account/API key and verify the sending domain.
3. Add Edge Function secrets:
   - `RESEND_API_KEY` = the Resend API key
   - `TICKET_EMAIL_FROM` = for example `LMS Piti Greenwaste <tickets@lmsfm.com>`
4. Deploy the `send-ticket-email` Supabase Edge Function.

Until a sending domain is verified, Resend testing may use `onboarding@resend.dev` with Resend's recipient restrictions.
