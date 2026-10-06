# Stick2XU

Custom stickers, pins, posters, and keychains for XU students. Customers design on their phone, pick a pickup date, time, and gate, and get their order at school. Stick2XU is run by students and isn't an official XU service.

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

Every order has a **Delete** button (tap it twice). Deleting removes the order and its pictures for good, as if it never happened, so it no longer counts in Earnings. Use it for test orders.

After 2 no-shows, that nickname and section can't order anymore. You can change the limit in Supabase under `shop_settings → max_noshows`.

**Earnings:** total earned, the last 7 days, money still to collect, and which posters bring in orders.

**Poster QR codes:** type a name for each poster spot (like `gate-1` or `library-board`), then download the QR code. Every poster should get its own name, so Earnings can show which spots work. Set `siteUrl` in CONFIG before making these.

**Settings** has two parts.

**Products and prices:** switch stickers, pins, posters, and keychains on or off. Anything switched off disappears from the site right away. Set the price of each size, and turn single sizes off (for example, hide A3 posters). Each product can also have **extras**, like "Inkjet print +₱30 (brighter, more vivid colors)". An extra has a name, a short reason shown in brackets, a price added per sheet or per item, and an on/off switch. Add as many as you want.

**Deals:** discounts that apply by themselves when an order qualifies. There are three kinds:
- **Buy some, get some free**, like "Buy 5 pins, get 1 free". The cheapest ones are the free ones.
- **Discount when buying more**, like "3+ sheets: ₱5 off each".
- **Combo**, like "Stickers + keychain: ₱10 off" when both are in the order.

If two deals fit the same product, the customer gets the bigger one. Combos add on top. Live deals show as a gold strip on the home page, ribbons on the product cards, and "add 1 more to save" hints while designing and in the cart. The server always does the math, so customers can't fake a discount.

**Promo codes:** codes customers type at checkout. Each can be % or ₱ off, with an optional minimum order, a max number of uses, and an end date. They're private, so only people you give a code to can use it. Turn a code off anytime with its switch.

**Pickup signal:**, meaning what customers look for at the gate: "the person **holding / wearing** ___", like "holding a Stick2XU sign" or "wearing a yellow lanyard". Changes show up for customers right away.

## Changing things

| To change | Where |
|---|---|
| Which products are available, prices, extras | Admin page → Settings |
| Deals and promo codes | Admin page → Settings |
| Max sticker sheets per order, no-show limit | Supabase → Table Editor → `shop_settings` |
| Pickup signal | Admin page → Settings |
| Pickup days, times, gates, grades, GCash details, holidays | `CONFIG` at the top of `index.html`, then push |
| Pin sizes (pin size and paper circle size), keychain insert size, poster sizes | `CONFIG.products` in `index.html`, then push |
| Colors | The `--xu-...` values at the top of the `<style>` in `index.html` |

## Keeping it running

- Pictures are deleted automatically 30 days after an order is finished. The cleanup runs when the admin page opens. Order records stay, so earnings history is kept.
- Free Supabase projects pause after about a week with no activity. Over breaks, open the Supabase dashboard once a week, or restore the project when you come back.
- After updating `index.html`, also run the latest `schema.sql` in Supabase if it changed. It's safe to run again.
