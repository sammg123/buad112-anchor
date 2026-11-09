# iPhone Shortcuts setup

About 20 minutes, once. After that, nothing changes between demos if you use the ngrok static domain (see README). With the Cloudflare fallback, only "Anchor Config" changes.

You need an iPhone on the **newest iOS**, and the Mac running `npm start`. The Anchor page on the Mac shows a QR code, the base URL and the key.

## 0. One-time iPhone setup

1. Settings, Accessibility, Display & Text Size, Color Filters: choose **Grayscale**, leave Color Filters **OFF**.
2. Open Shortcuts, add an action, search "Silent". If **Set Silent Mode** exists, great. If not, skip that action below; Set Volume still makes media loud.
3. Remove the loopholes: Settings, Control Center, remove **Text Size** and **Color Filters** / Accessibility Shortcut tiles. Settings, Accessibility, Accessibility Shortcut: turn everything **off** (triple-click).
4. Save a normal wallpaper you like to your Photos, so "Anchor Restore" can put it back.
5. Scan the QR with the camera, open the page, Share, **Add to Home Screen**. The key comes from `?k=` in the URL you saved it from.

## 1. Shortcut "Anchor Config"

Dictionary with Text items `base` (the https URL, no trailing slash) and `key` (the key on the Mac page). Then **Stop and Output** the Dictionary.

Everything below starts with **Run Shortcut: Anchor Config** and reads `base` and `key` from its output. Called `[base]` and `[key]` here.

## 2. Shortcut "Anchor Apply"

Accepts Shortcut Input: the `data` dictionary from the server. Actions:

1. Run Shortcut Anchor Config.
2. **If** `grayscale` is true: Set Color Filters **On**. Otherwise: Off.
3. **If** `silentOff` is true: **Set Silent Mode** Off (skip if missing), then **Set Volume** to `volumePercent` %.
4. **Set Brightness** to `brightnessPercent` %.
5. **Set Text Size**: Largest if `bigText` is true, otherwise Default.
6. **If** `shame` is true: Get Contents of URL `[base]/api/wallpaper.png`, header `x-anchor-key: [key]` → **Set Wallpaper** (Lock Screen and Home Screen, **Show Preview off**).
7. **If** `flash` is true: Repeat `flashBlinks` times: Set Flashlight On, Wait 1 s, Set Flashlight Off, Wait 1 s.
8. **If** `active` is false: Run Shortcut **Anchor Restore**.

## 3. Shortcut "Anchor Restore"

Color Filters Off, Set Brightness 60%, Set Text Size Default, Set Wallpaper to your saved photo (Show Preview off). Run when the session ends or you leave the zone.

## 4. Automation "App Opened" (Instagram, TikTok, etc.)

Automation tab, **+**, App, Is Opened, pick the distracting apps, **Run Immediately**, Notify off.

1. Run Shortcut Anchor Config.
2. Get Contents of URL `[base]/api/phone/open`: POST, header `x-anchor-key: [key]`, JSON body `app` = `Instagram`.
3. Get Dictionary Value `data`.
4. Run Shortcut **Anchor Apply** with `data` as input.
5. **If** `gate` is true: Open URLs `[base]/phone.html?k=[key]#gate`.

## 5. Automation "App Closed" (same apps)

Same as above with `/api/phone/close`, then Run Anchor Apply. Do **not** restore: effects stay on while you are in the zone.

## 6. Automation "Guard" (Settings and Shortcuts)

App Is Opened: **Settings** and **Shortcuts**, Run Immediately. POST `[base]/api/phone/guard` (same header, `app` = `Settings`) → Get `data` → Run Anchor Apply → **If** `locked` is true: Open URLs `[base]/phone.html?k=[key]#locked`.

## 7. Shortcut "Anchor Enforcer"

Re-applies everything every 15 s while you are at your anchor.

1. Run Shortcut Anchor Config.
2. **Repeat 500 times:**
   - Get Contents of URL GET `[base]/api/phone/now`, header `x-anchor-key: [key]`.
   - Get Dictionary Value `data`.
   - **If** `active` is false: Run Shortcut Anchor Restore, then **Stop This Shortcut**.
   - Set `flashBlinks` to 0 in a copy of `data` (or just don't blink here), then Run Anchor Apply.
   - **Wait** `reapplySeconds` seconds.

The Anchor page starts it for you (it opens `shortcuts://run-shortcut?name=Anchor%20Enforcer` when you start, and has a "Start the Enforcer" button).

## 8. Automation "Leave" (optional)

Arrive/Leave, Leave, your study spot, Run Immediately. Get Current Location → POST `[base]/api/phone/close` with `lat` and `lng` → Run Anchor Apply (it runs Anchor Restore once the server says the zone is left).

## Limits (honest version)

- iOS may stop the Enforcer in the background after a while. Re-applying on every app open is the backstop.
- Control Center brightness can't be removed, but Anchor re-applies it.
- Nothing here truly locks iOS settings. We bounce you away from Settings and Shortcuts.

## Troubleshooting

- **No URL printed:** install cloudflared (`brew install cloudflared`) or use ngrok; see the README.
- **403:** wrong key. Retype it, no spaces.
- **Automation asks to run:** turn on **Run Immediately**.
- **Stuck grey, dim or huge:** run "Anchor Restore", or undo in Settings.
- **No Shortcuts yet:** open the phone page and use Presenter, "Simulate opening Instagram" / "Settings".

## Demo script (2 minutes, 5x speed)

1. Projector shows the Mac page with the QR. Scan it; the phone page opens (or launch the Home Screen app).
2. Set 5 minutes, tuition, a play-money deposit. **Drop anchor & start**. Presenter: speed **5x**.
3. Open Instagram: bounced to the gate. Wait.
4. Keep opening it. At 5x a step lands every 3 s: grey, **loud**, dim, tuition receipt, **huge text**, **shame wallpaper**, **flashlight**, the confession, the deposit draining.
5. Open Settings: the locked screen says how far you have to walk.
6. Walk away or drag Simulated distance past 50 m. Effects lift, **Stop** unlocks, show the grade.
