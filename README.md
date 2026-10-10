# Stick2It

Custom stickers, pins, posters, and keychains for XU students. Customers design on their phone, pick a pickup date, time, and gate, and get their order at school. Stick2It is run by students and isn't an official XU service.

First time setting it up? See **SETUP.md**.

## How it works for customers

1. **Design.** They pick what to make, then design it:
   - **Stickers:** add pictures, pick a size, and tap where each one goes. Drag a placed sticker to move it. Every sticker shows its white die-cut border.
   - **Pins:** one picture in a circle. They drag and zoom to frame it. The shaded edge shows the part that wraps around the back.
   - **Posters:** one picture on a full A4 or A3 page, tall or wide.
   - **Keychains:** a picture for the paper insert of a clear acrylic keychain. The back can be the same picture, a different one, or left clear.

   Everything goes into one order, and they can add more items before checking out.
2. **Details.** Nickname, grade and section, then a pickup date, time (Lunch 12:30 PM or After class 5:10 PM), and gate (Gate 1 or Gate 4). Pay in cash at pickup, or by GCash.
3. **Pickup pass.** They get a code like `STK-7KQ4` and a "Your pickup" summary.
4. **Pickup day.** They check **My order** until it says Ready. At the gate, they look for the seller's signal and tap **I'm here**.

## The admin page

Open `your-site/#/admin` and log in.

**Orders**, in the order they move through:

- **To review:** check each design. Approve it, or reject it with a reason the customer will see.
- **To print:** download the PDF and print at **100% / "Actual size"**. One PDF has the whole order, and the footer on every page says which item it is:
  - **Stickers:** one page per sheet. Print on sticker paper and cut along the thin grey lines.
  - **Pins:** circles packed on A4. Cut on the grey circle.
  - **Posters:** one page per copy, at A4 or A3.
  - **Keychains:** inserts packed on A4, front and back side by side. Cut on the grey lines. Orders where the customer tapped "I'll be there" are listed first.
- **Printing:** tap **Mark ready** when they're cut and bagged. Write the code and nickname on each bag.
- **Ready:** grouped by pickup date. Keep this open on your phone at the gate. When someone taps "I'm here", they jump to the top with a gold **Here now** tag and a pop-up with their name, section, and gate. It checks every 15 seconds. Then tap **Picked up and paid**, or **Didn't show up**.
- **Done / Other:** finished, rejected, cancelled, and no-show orders.

Every order has a **Delete** button (tap it twice). Deleting removes the order and its pictures for good, as if it never happened, so it no longer counts in the Business tab. Use it for test orders.

After 2 no-shows, that nickname and section can't order anymore. You can change the limit in Supabase under `shop_settings → max_noshows`.

**Business:** profit, supplies, equipment, and which posters bring in orders (see below).

**Poster QR codes:** type a name for each poster spot (like `gate-1` or `library-board`), then download the QR code. Every poster should get its own name, so the Business tab can show which spots work. Set `siteUrl` in CONFIG before making these.

**Settings** has two parts.

**Products and prices:** switch stickers, pins, posters, and keychains on or off. Anything switched off disappears from the site right away. Set the price of each size, and turn single sizes off (for example, hide A3 posters). Each product can also have **extras**, like "Inkjet print +₱30 (brighter, more vivid colors)". An extra has a name, a short reason shown in brackets, a price added per sheet or per item, and an on/off switch. Add as many as you want.

**Deals:** discounts that apply by themselves when an order qualifies. There are four kinds:
- **Class pack**, where the price per pin drops in steps as the order grows, like 10+ ₱3 off, 20+ ₱5 off, 30+ ₱8 off, 40+ ₱10 off. It's made for one class rep ordering for the whole section (up to 60 pins in one order).
- **Buy some, get some free**, like "Buy 5 pins, get 1 free". The cheapest ones are the free ones.
- **Discount when buying more**, like "3+ sheets: ₱5 off each".
- **Combo**, like "Stickers + keychain: ₱10 off" when both are in the order.

If two deals fit the same product, the customer gets the bigger one. Combos add on top. Deals are shown quietly: one small line on each product card, a soft "add 1 more to save" hint while designing and in the cart, and the class pack price ladder inside the pin designer. The server always does the math, so customers can't fake a discount.

**Promo codes:** codes customers type at checkout. Each can be % or ₱ off, with an optional minimum order, a max number of uses, and an end date. They're private, so only people you give a code to can use it. Turn a code off anytime with its switch.

**Shop details:** pickup days, pickup times, pickup places (gates), earliest pickup, how many dates to offer, dates to skip (holidays and exams), grades in the dropdown, GCash on/off with name and number, per-design limits for pins/posters/keychains, how many pictures a customer can add, no-shows before blocking, how long pictures are kept, and the pin paper-circle and keychain insert sizes in mm.

**Pickup signal:**, meaning what customers look for at the gate: "the person **holding / wearing** ___", like "holding a Stick2It sign" or "wearing a yellow lanyard". Changes show up for customers right away.

## Prints (plain paper)

Customers upload PDFs or pictures. The site counts the pages, and they pick paper size, black and white or color, one side or both sides, and copies. Price = printed pages × price per page (₱5 black and white, +₱5 for color, so ₱10).

- **Pickup any school day**, even the same day if they order at least 2 hours before the pickup time.
- **Rush fee:** same day +₱20, next school day +₱10. Change these in Settings → Shop details → Prints and rush orders.
- **Pictures:** tap **Adjust** to place a picture on the page. Choose a tall or wide page, "Whole picture" or "Fill the page", and drag or pinch to zoom. With black and white chosen, the preview shows it in grey. The page is sent to you exactly as they set it up, already in black and white, ready to print.
- **Paper sizes:** A4 is on. Turn on Short or Long, or change prices, in Settings → Products → Prints.
- **Printing them:** each prints order shows a button for every file. Open it and print from your phone or computer. These orders aren't in the PDF button.
- **Privacy:** print files are deleted 3 days after pickup (changeable).

## Big posters (like Rasterbator)

Customers pick:
- **Each sheet:** tall or wide paper.
- **How many sheets:** a number, **across** or **down**. The other side comes from the picture's shape.
- **Fit:**
  - **Whole picture** (default, Rasterbator's way): nothing gets cut off. If the picture doesn't fill the last row or column of sheets, that sheet is partly blank and you trim off the blank part. A 2:1 picture at 4 across on tall sheets is 4 × 2 = 8 sheets, the same as Rasterbator.
  - **Fill the sheets:** every sheet is used edge to edge, and a little of the picture's edges may be cut off. The customer drags the picture to choose what stays.

**Joining the sheets (overlap and glue):** sheets overlap by 10 mm. Each sheet repeats a 10 mm strip of picture along its right and bottom edges, where the next sheet goes on top. To put one together:
1. Cut every sheet at its cut marks.
2. Glue the strip between the gold tick marks.
3. Lay the next sheet on top so the picture lines up, left to right, then each new row on top of the row above.

The joins are firm, not just taped edges, and almost invisible. You can change the overlap, or set it to 0 for edge-to-edge taping, in Settings → Shop details → Big posters.

If a picture would spill only a thin strip onto another row or column of sheets, the poster shrinks slightly instead of using a row of nearly empty sheets.

The designer shows the poster size in cm, how many sheets it uses, and the price. For posters with more than one sheet, customers can switch between **Finished** (the taped-together poster) and **As printed** (each sheet with its white edge and dashed cut lines), so they know you trim the edges and tape the sheets. Most a poster can be: 24 sheets.

Price = poster price + ₱30 for each extra sheet. In Settings → Shop details → Big posters you can also change:
- **White border on each sheet:** default 5 mm. Raise it to 10 mm, like Rasterbator, if your printer leaves a wider blank edge.
- **Glue overlap between sheets:** default 10 mm. Set it to 0 to tape the edges from behind instead.

The PDF puts one piece on each sheet, with cut marks, gold tick marks for the glue strips, and a short note on each sheet ("Row 1, column 2. Cut on all four marks. Glue the right 10 mm strip; the next sheet goes on top."). One-sheet posters also get cut marks: cut the extra paper off around the picture.

### Posters from a PDF

Customers can upload a PDF in the poster designer:
- **A one-page PDF** (a design saved as a PDF) becomes the poster picture and works like any other picture.
- **A PDF with several pages** (like a Rasterbator download) is printed **exactly as it is**, one sheet per page, up to 24 pages. The customer sets how many pages go across, only so the preview shows the finished layout. Price = poster price + ₱30 for each extra page.

In admin, these orders show a download button for the PDF instead of a print PDF. Print every page, then cut and join them along the PDF's own cut marks.

## Pickup capacity (busy days)

So one person never has to be at two gates at once, and a day never gets more orders than you can print:
- **People at pickup at the same time** (default 1): with 1, each pickup time uses **one gate**. The first order for, say, Friday lunch picks the gate. After that, customers choosing Friday lunch see the other gates greyed out with "At this time we'll be at Gate 1". They pick that gate or another time. Set 2 if two of you can cover two gates at once.
- **Most orders per pickup time** (default 8) and **per pickup day** (default 15): when one fills up, checkout shows "Full" and customers pick another time or day. 0 means no limit.

The server enforces these rules, so two people ordering at the same moment can't both take the last spot. Customers moving their pickup follow the same rules. Change all three in Settings → Shop details → Pickup rules. The Orders tab has an **Upcoming pickups** box with the next pickup days, each time slot, its gate, and how many orders, so you can plan who goes where and how much to print the night before.

## Product order

Customers see products in this order: Stickers, Pins, Keychains, Posters, Prints. Change it in Settings → Products with the ▲ ▼ buttons, then Save. On phones, products show two to a row so customers see them all at a glance. An odd one out at the end (like Prints) gets a full row.

## New name: Stick2It

The site, PDFs, Telegram messages, calendar, and app icon name all say Stick2It now. The pickup signal changes to "a Stick2It sign" when you run schema.sql (unless you had already changed it). To change the web address too, see SETUP.md.

## Business tab (admin)

A dashboard of the money side. On a computer it fits in about two screens. Everything saves by itself (the green "All changes saved" at the top).
- **Profit:** this week and so far, and a chart of the last 8 weeks. Profit = sales minus the supplies each picked-up order used.
- **Paying back what you put in:** each partner's name and how much they **put in** (₱700 each, ₱2,100 total). It shows how much is left, the profit a week you need to finish in your chosen number of weeks, roughly how many sticker sheets or pins that is, and how much each person has gotten back so far. Fully paid back gets a little celebration.
- **Supplies:** pack price, how much is in a pack, cost per piece, stock, and when to warn you. Stock goes down by itself when you tap **Mark ready**, and you get a Telegram alert when something runs low. Tap **Restock** after buying a pack: it adds to stock and logs the purchase. Rows that need restocking (or a stock count) are highlighted. **Do a real inventory count** and type the actual stock and prices in.
- **Money in and out:** the plain cash view, everything earned minus everything spent, with a list of purchases you can edit.
- **Equipment:** a record of things bought once, like the pin maker.
- **What each item costs to make** (folded, tap to open): which supplies one item uses. The header shows each item's profit at a glance. Hidden products are folded inside too. **Ink "pages per bottle set" (600) is a guess**: once you know how many pages your ink really lasts, change it.
- **Which posters bring orders** (folded): orders by poster QR code.

## Seller's routine: from order to pickup

1. **New order** (Telegram: "Order placed"). Open admin → **To review**. Check the design: nothing inappropriate, and pictures clear enough to print (the blur warnings help). Tap **Approve**, or **Reject** with a reason so the customer knows what to fix.
2. **Wait for the customer to confirm** (Telegram: "Confirmed"). They tap "I'll be there" by the day before pickup. Unconfirmed orders are released by themselves, so nothing is printed for no-shows.
3. **The night before pickup.** Check **Upcoming pickups** in the Orders tab to see which days, times, and gates have orders. In **To print**, tap **Download PDF** for each confirmed order (prints and PDF posters: use the file buttons). Print, cut, and assemble (big posters: cut at the marks, glue the strips). Tap **Mark ready**: supplies come off stock automatically, and you get a Telegram alert if something runs low. Put each order in a bag with its **code and full name** written on it.
4. **Pickup.** Bring the bags, change, and the signal ("a Stick2It sign"). At the gate, open the **Ready** list and tap **Start pickup mode**. When someone taps "I'm here" (Telegram: "Arrived"), match their **code**, **full name**, and **school ID**. Take payment (GCash: check it arrived in your own GCash app), hand over the bag, and tap **Picked up and paid**.
5. **Didn't show up?** Tap **Didn't show up**: the order moves to the next pickup day. If they miss that too, tap **Didn't show up again** to forfeit it (it counts as a strike).
6. **After.** Check the **Business** tab for profit and restocking. Send back any GCash refunds it lists, and tap **Mark refunded**.

## Customer names

Checkout asks for the customer's **full name, as on their school ID**, and tells them to bring their ID. That's how you match orders at pickup. To look up their order, the order code plus their first name is enough. Names are only seen by the sellers (admin page and Telegram), and are deleted with the pictures after the cleanup period.

After ordering, customers see a big **Save your code** box with **Save as picture** (a pickup pass image for their Photos) and **Copy code**. If they try to leave without saving, it asks once.

## Pickup and handoff rules

- **Confirm before printing.** Customers tap **"I'll be there"** in My order by the day before pickup (change this in Settings → Shop details → Pickup rules). Only print orders tagged **Confirmed**; the button on unconfirmed ones says "Print anyway" and needs two taps. Unconfirmed orders are released automatically after their confirm-by day (they show as "Not confirmed in time"), with no strike and nothing to pay.
- **Hold, then forfeit.** The first time someone doesn't show, tap **Didn't show up**: the order is held for the next pickup day and the customer sees "You missed your pickup" in My order. If they miss that too, tap **Didn't show up again**: it's forfeited and counts as a missed pickup.
- **Customers can move their pickup** to another open day from My order, up to 2 times (Settings → Shop details).
- **Class suspended or pickup cancelled?** Settings → **Notice to customers** shows a message on every customer page. Under it, **Move a pickup day** moves everyone from one day to another in one tap and fills in a notice for you.
- **Pickup mode.** On the Ready list, tap **Start pickup mode** at the gate: the screen stays awake, and the phone chimes and buzzes when someone taps "I'm here". The page has to stay open for this; Telegram alerts work even when it's closed.
- **GCash refunds.** If a GCash order was marked paid and then gets cancelled or rejected, it's tagged **Refund needed**. Send the money back, then tap **Mark refunded**.
- **At the gate:** check GCash payments in your own GCash app (never trust a screenshot), keep the bag until you're paid, and bring change.

## Telegram alerts

Get a Telegram message for new orders, customers at the gate, confirmations, moved pickups, and cancellations. The database sends them, so they arrive even when the admin page is closed. Set it up in admin → Settings → **Telegram alerts** (steps are shown there), and see SETUP.md step 7.

## Changing things

| To change | Where |
|---|---|
| Which products are available, prices, extras | Admin page → Settings |
| Deals and promo codes | Admin page → Settings |
| Pickup days, times, gates, dates to skip, grades, GCash, limits, pin and keychain sizes, website address | Admin page → Settings → Shop details |
| Product names and descriptions | Admin page → Settings → Products |
| Supplies, costs, partners, equipment, purchases | Admin page → Business |
| Sticker sheet grid, poster paper sizes | `CONFIG` in `index.html`, then push |
| Max sticker sheets per order | Admin page → Settings → Products (Stickers) |
| Pickup signal | Admin page → Settings |
| Colors | The `--xu-...` values at the top of the `<style>` in `index.html` |

## Keeping it running

- Pictures are deleted automatically 30 days after an order is finished. The cleanup runs when the admin page opens. Order records stay, so earnings history is kept.
- Free Supabase projects pause after about a week with no activity. Over breaks, open the Supabase dashboard once a week, or restore the project when you come back.
- After updating `index.html`, also run the latest `schema.sql` in Supabase if it changed. It's safe to run again.
