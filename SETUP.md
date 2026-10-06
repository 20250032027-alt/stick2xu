# Stick2XU setup

This gets the site live: Supabase for the database, GitHub for the code, Vercel for hosting. Plan on about 30 minutes.

The repo only needs three files:

```
stick2xu/
├── index.html    the whole website (customer pages + admin page)
├── schema.sql    the database setup, run once in Supabase
└── README.md     how to run the shop day to day
```

Keep `SETUP.md` in the repo too if you want it for reference.

---

## 1. Supabase (database and picture storage)

1. Create a free project at [supabase.com](https://supabase.com). Pick the Singapore region; it's the closest to Cagayan de Oro.
2. Open **SQL Editor → New query**, paste all of `schema.sql`, and click **Run**.
3. Go to **Authentication → Users → Add user → Create new user**. Enter the admin's email and a strong password, and tick "Auto Confirm User".
4. Back in the SQL Editor, run this with that same email:
   ```sql
   insert into public.admins (email) values ('the-admin@email.com');
   ```
   Only emails in this table can see orders. To add a second admin later, run it again with their email.
5. Go to **Authentication → Sign In / Providers** and turn **off** "Allow new users to sign up". Nobody else should be able to create an account.
6. Go to **Project Settings → API** and copy the **Project URL** and the **anon public** key.

> The anon key is meant to be public, so it's fine in the code. The database rules in `schema.sql` control what it can do. **Never** put the `service_role` key anywhere in the repo.

**Updating later:** if `schema.sql` changes, just run the whole file again. It only adds what's missing and keeps your orders.

---

## 2. Fill in CONFIG

Open `index.html`. Everything you'd want to change is in `CONFIG` near the top of the `<script>`:

```js
supabaseUrl: 'https://your-project.supabase.co',
supabaseAnonKey: 'eyJhbGciOi...',
siteUrl: '',   // fill this in at step 5
```

While you're there, check these:

| Setting | What it does |
|---|---|
| `gcash` | GCash name and number shown at checkout. Set `enabled: false` for cash only. |
| `pickupWeekdays` | Pickup days. `0` = Sunday … `6` = Saturday. Default `[2, 5]` = Tuesday and Friday. |
| `pickupTimes` | The times customers choose from. Default: Lunch (12:30 PM) and After class (5:10 PM). |
| `pickupOptions` | Pickup spots. Default: Gate 1 and Gate 4. |
| `leadDays` | Earliest pickup is this many days after ordering, so there's time to check and print. |
| `noPickupDates` | Dates to skip, like holidays or exam days: `['2026-11-02']`. |
| `grades` | Grades in the dropdown. Default 7 to 10. |
| `sheet` | Paper size and grid. Default is A4 with a 4 × 6 grid. Match it to the sticker paper. |
| `products` | Physical sizes. Pins: `faceMm` is the pin size, `cutMm` is the paper circle that wraps around it (check your pin machine). Keychains: `wMm`/`hMm` is the paper insert, so measure your acrylic cases. |

Prices, which products are available, extras (like inkjet), deals, promo codes, and the pickup signal are **not** in CONFIG. Change them from the admin page under **Settings**. Pins, posters, and keychains start switched off, so turn them on there when you're ready to sell them.

---

## 3. GitHub

```bash
cd stick2xu
git init
git add .
git commit -m "Stick2XU"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/stick2xu.git
git push -u origin main
```

A private repo works fine.

---

## 4. Vercel

1. **Add New → Project**, then import the `stick2xu` repo.
2. **Framework Preset:** Other
3. **Build Command:** leave empty
4. **Output Directory:** leave empty
5. **Root Directory:** `./` (or the folder `index.html` is in, if it's in a subfolder)
6. Click **Deploy**.

For a nicer address, go to **Project → Settings → Domains** and edit the `.vercel.app` name, for example `stick2xu.vercel.app`.

---

## 5. Point the site at its own address

1. Put the final address in `CONFIG`:
   ```js
   siteUrl: 'https://stick2xu.vercel.app/',
   ```
2. Commit and push. Vercel redeploys by itself in under a minute.
3. In Supabase, go to **Authentication → URL Configuration** and set **Site URL** to the same address.

**Do this before making any poster QR codes.** The QR codes use this address.

---

## 6. Test before the posters go up

Do this on a phone using mobile data, not just on a laptop:

1. Open the site. If it says "Not connected yet", the Supabase URL or key in CONFIG is missing or wrong.
2. Design a sheet, place an order, and screenshot the pickup pass.
3. Open `https://your-site/#/admin` on another device and log in.
4. Approve the order, download the PDF, then **Mark ready**.
5. On the phone, open **My order** and tap **I'm here**. Within 15 seconds, it should jump to the top of the admin **Ready** list with a gold "Here now" tag.
6. Print one PDF page at **100% / "Actual size"** on plain paper, and hold it over the sticker paper to check the grid lines up.
7. In admin, go to **Poster QR codes**, make one, print it, and scan it with a different phone.
8. Clean up: tap **Delete** twice on each test order in the admin page. That removes them and their pictures, so they don't show in Earnings or count as a no-show strike.

---

## Troubleshooting

| What you see | Likely cause |
|---|---|
| "Not connected yet" | `supabaseUrl` or `supabaseAnonKey` is empty or has a typo |
| "Can't connect right now" | No internet, or the Supabase library didn't load; refresh |
| "Upload failed" at checkout | The storage part of `schema.sql` didn't run; run the whole file again |
| Error placing an order after updating the site | `schema.sql` is older than `index.html`; run the latest `schema.sql` |
| "Permission denied for table orders" or "The database blocked this" | Run the latest `schema.sql` again; it includes the table permissions |
| "That promo code doesn't work" for a code you made | The code is switched off, past its end date, or was typed differently |
| "Something in your order isn't available right now" | A product, size, or extra in the order was switched off in Settings |
| Admin logs in but sees no orders | That email isn't in the `admins` table, or it's spelled differently |
| Admin can't log in | User wasn't created under Authentication → Users, or the password is wrong |
| QR code opens the wrong site | `siteUrl` wasn't set before making it; set it and make the code again |
| Site stops working after a quiet week | Free Supabase projects pause when unused; open the Supabase dashboard and restore it |
| Pushed a change but the site looks old | Hard refresh (Ctrl+Shift+R), or check the deployment finished in Vercel |
| Test orders from a Vercel preview link | Previews use the same database as the live site; delete those orders afterwards |
