# Anchor

## Phone prototype (BUAD 112 demo)

Anchor punishes your **phone**. Inside a 50 m zone around your anchor, opening a distracting app (via iOS Shortcuts) bounces you to Anchor's gate page and makes you wait, then greys and dims the phone, shows tuition burned, demands a typed confession, and drains a deposit.

**Setup (recommended: ngrok static domain)**

1. `brew install ngrok`, make a free account at ngrok.com, claim your free static domain, then `ngrok config add-authtoken YOUR_TOKEN`.
2. `npm install && NGROK_DOMAIN=your-name.ngrok-free.app npm start`. The URL never changes, so the Home Screen app and the Shortcuts never need updating. The key also survives restarts.
3. Open http://localhost:5112 on the Mac and scan the QR code with your iPhone camera. Add the page to your Home Screen.
4. Set up the Shortcuts: [docs/shortcuts.md](docs/shortcuts.md). Without them, the phone page has a Presenter panel with "Simulate opening Instagram" and "Simulate opening Settings".

**No account? Cloudflare fallback:** `brew install cloudflared` (or download the macOS binary from https://github.com/cloudflare/cloudflared/releases to `~/.local/bin/cloudflared`), then `npm install && npm start` without `NGROK_DOMAIN`. The URL changes each run, so update "Anchor Config" before every demo.

**Phone ladder** (one step per 15 s on the phone). Effects stay on until you leave the zone.

| On phone | Step | What happens | Gate wait | Pass after |
|---|---|---|---|---|
| 0:00 | Gate | Opening an app bounces you to Anchor | 10 s | 90 s |
| 0:15 | Grayscale | The phone goes grey | 12 s | 80 s |
| 0:30 | Loud | Silent mode off, volume 100% | 15 s | 70 s |
| 0:45 | Dim | Brightness 15% | 20 s | 60 s |
| 1:00 | Receipt | Tuition burned, live on the gate | 25 s | 50 s |
| 1:15 | Huge text | Text size maxed | 30 s | 40 s |
| 1:30 | Shame wallpaper | Wallpaper shows what you burned | 40 s | 30 s |
| 1:45 | Flashlight | Blinks on every app open | 45 s | 25 s |
| 2:00 | Confession | Type the phrase to pass the gate | 50 s | 20 s |
| 2:15 | Deposit | Deposit drains (only if you put one down) | 60 s | 15 s |

Opening Settings or Shortcuts inside the zone bounces you to a locked screen. The Mac effects (sound, speech, overlay) are opt-in: `ANCHOR_MAC=1 npm start`.

---

## Mac mode (original MVP)

A study timer you can't quietly quit. BUAD112 MVP.

You drop an anchor where you study. While you're within 50 m of it, **Stop is locked**.
Every 15 seconds you spend on your phone, your Mac gets more annoying, across every app,
tab, and screen, until getting off the phone is the easiest thing to do.

## Run it

Needs a Mac, Node 20 or newer, and Apple's command line tools (`xcode-select --install`, for
the screen overlay).

```bash
cd ~/buad112-anchor
npm start
```

Open **http://localhost:5112** in Chrome or Safari and allow location when asked.
The first start compiles the screen overlay (a few seconds).

## The rubric (one step per 15 s on your phone)

| On phone | Step | What happens on the Mac |
|---|---|---|
| 0:00 | Clock | Floating timer with an "I'm off my phone" button appears over every app |
| 0:15 | Red pulse | Whole screen pulses red (slow, never faster than once per 1.2 s) |
| 0:30 | Ticking | Clock ticking that speeds up; volume is unmuted and raised to at least 35 |
| 0:45 | Blur | The whole screen blurs in waves (about 2.5 s blurred, 3 s clear); waves get longer and gaps shorter each step, never under 1.5 s clear |
| 1:00 | Shake | Every blur wave also vibrates and shudders the whole screen like a phone buzzing on a table, harder every step |
| 1:15 | Receipt | Tuition burned, counted live |
| 1:30 | Voice | The Mac talks to you every 15 s |
| 1:45 | Notifications | A banner every 10 s |
| 2:00 | Penalty | Each phone second adds 2 s to the study timer |
| 2:15 | Snitch | "Texting your study group in 10…" then a fake sent message. Nothing is sent |
| 2:30 | Siren | Siren loop, volume forced to at least 70 |
| 2:45 | Confession | A popup you make leave by typing "I am choosing my phone over my grade". Pops up once per session |
| 3:00 | Deposit | Only if you put money down. It drains, a bigger bite every minute until it's gone. The floating bar shows the balance and a red -$X each time |

**Deposit:** optional. Type any amount up to $10,000 before starting, or leave it empty (play money in
this MVP; nothing is charged, no card). Empty means no deposit step at all. From 3:00 on the phone it
drains exponentially: each minute takes about 1.56x the minute before, and bigger deposits burn for more
minutes: n = 3 + round(log2(amount / 5)), clamped to 1-15. It follows the phone timer, which never resets
during a session, so lost money stays lost. Examples:

| Deposit | 3:00 | 4:00 | 5:00 | 6:00 | 7:00 | 8:00 | 9:00 |
|---|---|---|---|---|---|---|---|
| $5 | 1.00 | 1.56 | 2.44 | | | | |
| $10 | 1.14 | 1.77 | 2.77 | 4.32 | | | |
| $25 | 1.69 | 2.65 | 4.13 | 6.45 | 10.08 | | |
| $50 | 2.08 | 3.25 | 5.07 | 7.92 | 12.37 | 19.31 | |
| $100 | 2.59 | 4.05 | 6.33 | 9.88 | 15.43 | 24.09 | 37.63 |

The math: ratio r = (√17 − 1) / 2 ≈ 1.5616 (it splits $5 into exactly $1, $1.56, $2.44). For a deposit
D over n minutes the first bite is D(r − 1) / (rⁿ − 1), so the bites add up to exactly D.

**Library mode** (a checkbox on the setup screen): no sound at all. No ticking, voice, or siren,
notifications stay silent, and your volume is never touched. The three sound steps are cut, so the
remaining steps come every 20 seconds: red at 0:20, blur at 0:40, shake at 1:00, and the deposit still
starts going at 3:00.

The shake moves a blurred snapshot of your whole screen, so it needs Screen Recording permission for
the app you run `npm start` from (usually Terminal). Without it, only the screen
edges rattle, and Anchor prints how to turn it on.

**Tuition:** the cover asks for your college's yearly tuition and turns it into what one minute of class
costs: tuition ÷ 450 class hours a year (15 hours a week, two 15-week semesters). $70,000 a year comes
out to $2.59 a minute.

Getting off the phone clears everything instantly and puts your volume back exactly as it was.
The phone timer and the punishment run on one clock (step = timer ÷ 15 s), and it never resets during a
session. Off the phone, it pauses; pick the phone up again and it resumes at the same step. Only a new
session starts from zero.

**Away from your anchor** (past the point where Stop unlocks), your phone is just a phone: nothing goes
off, nothing is charged, and the study timer pauses. Press Stop there, or walk back and keep studying.
Coming back while still on your phone resumes the timer and step exactly where you left them.
Closing the tab doesn't end the session; the server keeps it, and reopening the page picks it up.

## Demoing to the class

Open **Presenter** (bottom left):

- **Speed slider**: anywhere from 1x (real time) to 10x. At 6x each 15 s step takes 2.5 s.
- **Walk away slider**: pretend you're N meters from the anchor. Past 50 m, Stop unlocks.

Suggested 2-minute demo: start a 5-minute session at 1x and hit "I'm on my phone". At real speed it goes
red at 0:15, ticks at 0:30, blurs at 0:45, and shakes the whole screen at 1:00. Drag the speed to 6x to rush the rest
up to the siren, click "I'm off my phone" on the floating bar, then slide "Walk away" to 70 m and press Stop
to show the graded cover.

## Safety exits

- "I'm off my phone" is always on screen (floating bar, top center) and works from any app.
- `Ctrl+C` in the Terminal running `npm start` stops everything and restores your volume.
- If the server dies, the overlay removes itself within 5 seconds.
- Nothing ever blocks the whole screen; the confession popup covers only the middle.

## Settings

| Variable | Default | What it does |
|---|---|---|
| `PORT` | `5112` | Port for the page |
| `ANCHOR_SILENT=1` | off | No sound, speech, or volume changes |
| `ANCHOR_OVERLAY=0` | on | Skip the Mac overlay; the page draws the effects inside the tab instead |
| `ANCHOR_DATA` | `./data` | Where the session is saved |

## Tests

```bash
npm test        # unit and API tests
npm run coverage
npm run e2e     # full flow in a real browser (silent, no overlay); pass a folder to keep screenshots
```

## How it's built

- `src/engine.js`: the rules, as pure functions (timers, escalation, decay, penalty, geofence, grade).
- `src/effects.js`: decides which effects are due and what the overlay should draw.
- `src/mac.js`: runs them with built-in macOS tools (`afplay`, `say`, `osascript`).
- `native/Overlay.swift`: the full-screen overlay and floating panels, driven over stdin.
- `src/server.js`: localhost only, same-origin JSON only, live updates over server-sent events.
- `public/`: the page, designed as an exam blue book (see `DESIGN.md`).

## Fonts

Archivo and Kalam are bundled under the SIL Open Font License 1.1; see `public/fonts/OFL-Archivo.txt`
and `public/fonts/OFL-Kalam.txt`.
