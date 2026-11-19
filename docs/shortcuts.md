# iPhone Shortcuts setup

**Have the iCloud links?** About 3 minutes: see "How it fits together". **Building the shortcuts yourself:** about 20 minutes, once. After that, nothing changes between demos if you use the ngrok static domain (see README). With the Cloudflare fallback, only "Anchor Config" changes.

You need an iPhone on the **newest iOS**, and the Mac running `npm start`. The Anchor page on the Mac shows a QR code, the base URL and the key.

## 0. One-time iPhone setup

1. Settings, Accessibility, Display & Text Size, Color Filters: choose **Grayscale**, leave Color Filters **OFF**.
2. Open Shortcuts, add an action, search "Silent". If **Set Silent Mode** exists, great. If not, skip that action below; Set Volume still makes media loud.
3. Remove the loopholes:
   - Open **Control Center** (swipe down from the top-right corner) and **press and hold** an empty spot until the icons jiggle (or tap **+** top-left). Tap **–** on **Text Size** (AA), **Accessibility Shortcuts**, **Color Filters**, and **Dark Mode** if they're there. Tap empty space to finish. (Older iOS: Settings, Control Center.)
   - Settings, Accessibility, **Accessibility Shortcut** (near the bottom): uncheck everything, so triple-click can't undo grayscale.
5. Scan the QR with the camera, open the page, Share, **Add to Home Screen**. The key comes from `?k=` in the URL you saved it from.

## How it fits together

8 shortcuts hold all the logic. The 4 automations each have a single action: **Run Shortcut**.

| Shortcut | What it does |
|---|---|
| Anchor Config | Holds your base URL and key |
| Anchor Apply | Applies what the server says (grey, loud, dim, text, flashing) |
| Anchor Restore | Puts the phone back to normal |
| Anchor Enforcer | Re-applies everything every 15 s and reports where you are, so walking away is noticed even with the phone in a pocket |
| Anchor App Opened | Called by automation 1 |
| Anchor App Closed | Called by automation 2 |
| Anchor Guard | Called by automation 3 (Settings) |
| Anchor Leave | Called by automation 4 (leaving your study spot) |

**Got the iCloud links?** Open the Anchor page on the phone, expand "Set up this iPhone", tap each **Add** button, paste the base URL and key when Anchor Config asks. Then do section 9 (automations). That's about 3 minutes in total. Sections 1-8 are only for the person **building** the shortcuts the first time.

`[base]` and `[key]` below mean the outputs of **Run Shortcut: Anchor Config**. Every Get Contents of URL sends header `x-anchor-key: [key]`, and every POST sends a JSON body.

## 1. Anchor Config

Dictionary with Text items `base` (the https URL, no trailing slash) and `key`, then **Stop and Output** it.
For sharing: shortcut **details (i)**, **Setup**, add **Import Questions** for both Text items ("Paste the Base URL from the Anchor page", "Paste the Key"). Then whoever adds it is asked for their own.

## 2. Anchor Apply

Input: the `data` dictionary.
1. **If** `active` is false: Run Shortcut Anchor Restore, **Stop This Shortcut**.
2. **If** `grayscale`: Set Color Filters **On**, otherwise **Off**.
3. **If** `silentOff`: **Set Silent Mode** Off (skip if your iOS doesn't have it), **Set Volume** to `volumePercent` %.
4. **Set Brightness** to `brightnessPercent` %.
5. **Set Text Size**: Largest if `bigText`, otherwise Default.
7. **If** `flash`: Repeat `flashBlinks` times: **Set Classic Invert** On, Wait 1 s, Set Classic Invert Off, Wait 1 s. This flips the colours of the whole phone, in whatever app is open. Keep the Waits: never faster than one flash a second. (Search "Invert" in the action list; if Classic Invert is missing, use Set Smart Invert.)

## 3. Anchor Restore

Color Filters Off → Set Classic Invert Off → Set Brightness 60% → Set Text Size Default (Show Preview off).

## 4. Anchor Enforcer

Run Anchor Config → **Repeat 500 times**: **Get Current Location** → Get Details of Locations (Latitude, Longitude) → Get Contents of URL `[base]/api/phone/where?k=[key]`, **POST**, JSON body `lat`, `lng` (Numbers) → Get Dictionary Value `data` → **If** `active` is false: Run Anchor Restore, **Stop This Shortcut** → Run Anchor Apply with `data` → **Wait** `reapplySeconds` s. From the Flashing step on, each cycle flashes the whole phone again, so it keeps flashing in every app until you leave.
The Anchor page starts it when you drop the anchor, once you've ticked "Shortcuts are set up".

## 5. Anchor App Opened

Run Anchor Config → POST `[base]/api/phone/open`, body `app` = `app` → Get Dictionary Value `data` → Run Anchor Apply with `data` → **If** `gate` is true: **Open URLs** `[base]/phone.html?k=[key]#gate`.

## 6. Anchor App Closed

Run Anchor Config → POST `[base]/api/phone/close` → `data` → Run Anchor Apply. Effects stay on while you're in the zone; Apply only restores once the server says you're out.

## 7. Anchor Guard

Run Anchor Config → POST `[base]/api/phone/guard` → `data` → Run Anchor Apply → **If** `locked` is true: **Open URLs** `[base]/phone.html?k=[key]#locked`.

## 8. Anchor Leave

Run Anchor Config → **Get Current Location** → POST `[base]/api/phone/close` with `lat` = Latitude, `lng` = Longitude → `data` → Run Anchor Apply.

## Sharing them (builder only)

For each of the 8 shortcuts: long-press it, **Share**, **Copy iCloud Link**. Paste the links into `public/shortcuts.json` and commit. The Anchor page's setup card turns each one into an **Add** button.

## 9. The 4 automations (everyone, about 2 min)

Shortcuts, **Automation** tab, **+**. For each one: **Run Immediately** on, **Notify When Run** off, one action **Run Shortcut**.

| Trigger | Run Shortcut |
|---|---|
| App, **Is Opened**: Instagram, TikTok, YouTube, ... | Anchor App Opened |
| App, **Is Closed**: same apps | Anchor App Closed |
| App, **Is Opened**: Settings | Anchor Guard |
| **Leave**: your study spot | Anchor Leave |

## Limits (honest version)

- iOS may stop the Enforcer in the background after a while. Re-applying on every app open is the backstop.
- Control Center brightness can't be removed, but Anchor re-applies it.
- Nothing here truly locks iOS settings. We bounce you away from Settings, but iOS doesn't allow an automation on the Shortcuts app itself, so someone could open Shortcuts and switch the automations off. Only a native Screen Time app can close that gap.

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
4. Keep opening it. At 5x a step lands every 3 s: grey, **loud**, dim, tuition receipt, **huge text**, **flashing**, the confession, the deposit draining.
5. Open Settings: the locked screen says how far you have to walk.
6. Walk away or drag Simulated distance past 50 m. Effects lift, **Stop** unlocks, show the grade.
