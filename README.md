<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="MathPeek icon">
</p>

<h1 align="center">MathPeek</h1>

<p align="center">
  Point at a sum anywhere on screen, press a shortcut, and see the answer by the pointer.<br>
  Free, open source, and light on battery.
</p>

<!-- TODO: once there are clips (scripts/make-video.swift), put the main one here:
<p align="center">
  <img src="docs/demo.gif" width="820" alt="MathPeek in action: …">
</p>
-->

<p align="center">
  <a href="https://github.com/doom1337hvh/MathPeek/releases/latest"><b>Download</b></a> ·
  <a href="#install">Install</a> ·
  <a href="#in-action">In action</a> ·
  <a href="#settings">Settings</a>
</p>

MathPeek is a small menu bar app for the sums you come across on screen: in a web page, a PDF, a note, a spreadsheet, a screenshot or a photo. Point at one, like `12 × (3 + 4.5) =`, and press **⌃⌥=**. MathPeek reads the text around the pointer, works out the sum nearest to it, and shows the answer right there in a small bubble that fades away. Click the bubble, or press ⌘C while it shows, to copy the answer. It reads the screen only when you press the shortcut, and only on your Mac.

## Features

- **Works anywhere on screen:** web pages, PDFs, documents, images and screenshots. It reads what's on screen with macOS's own text recognition, so it doesn't matter which app the sum is in.
- **The answer by the pointer:** a small bubble shows the sum it read and its answer, then fades away. It stays while the pointer is on it. Click it, or press ⌘C, to copy the answer.
- **A careful calculator:** + − × ÷ and powers, percentages the way a calculator does them (`50 + 10%` is 55, `15% of 80` is 12), √, ² and ³, brackets, decimals and thousands separators. It copes with what text recognition gets wrong, such as × read as the letter x, and ignores a trailing `=`.
- **The right sum:** when there are several, it picks the one nearest the pointer, and skips plain numbers and the answer already written after an `=`.
- **You choose what it reads:** an area around the pointer, sized in Settings, or an area you drag out each time, like a screenshot. **Read an Area…** in the menu does that too.
- **Your own shortcut:** ⌃⌥= to start with; record any other in Settings.
- **Built for battery life:** no Dock icon and nothing running in the background that doesn't need to. See [Battery](#battery).

Everything above can be switched off or changed in Settings.

## In action

Click one to watch it.

Clips are coming.

<!-- One <details> per clip in docs/clips:
<details>
<summary><b>Scene name</b>: what it shows.</summary>
<p align="center"><img src="docs/clips/scene.gif" width="820" alt="…"></p>
</details>
-->

## Requirements

- A Mac with Apple silicon, running macOS 14 Sonoma or later

## Install

1. Download `MathPeek-<version>.dmg` (or the `.zip`) from the [latest release](https://github.com/doom1337hvh/MathPeek/releases/latest).
2. Drag **MathPeek** into your **Applications** folder. Don't run it from Downloads: macOS runs apps opened there from a temporary copy, and the permissions you give that copy don't stick.
3. Open MathPeek. macOS will say *"Apple could not verify 'MathPeek' is free of malware"*. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to *"MathPeek was blocked"*. Confirm with **Open Anyway** and your password or Touch ID.
5. Point at a sum and press **⌃⌥=**. The first time, macOS asks to let MathPeek record the screen (see [Permissions](#permissions)): click **Open System Settings**, turn on **MathPeek**, then click **Quit & Reopen** when macOS asks. Press the shortcut again.

**Why the warning?** Apple only vouches for ("notarizes") apps whose developers pay for an Apple Developer account. MathPeek is a free project and isn't notarized. The source code is all here, and you can [build it yourself](#build-from-source) instead.

**Prefer Terminal?** Instead of steps 3 and 4, run this, then open the app normally:

```bash
xattr -dr com.apple.quarantine /Applications/MathPeek.app
```

**Check your download (optional):** each release lists SHA-256 checksums in `SHA256SUMS.txt`. Compare them with:

```bash
shasum -a 256 ~/Downloads/MathPeek-*.dmg
```

## Updating

Quit MathPeek (menu bar icon → Quit), replace the app in Applications with the new one, and open it. Each new download needs **Open Anyway** once more. Your permissions carry over, because every release is signed with the same certificate. If a release ever can't be, its notes will say so, and you'll need to allow them again.

## Permissions

| Permission | Asked when | What it's for |
|---|---|---|
| **Screen Recording** | The first time you press the shortcut | Seeing the text in the area it reads. It captures only that area, only when you press the shortcut, recognises the text on your Mac and keeps nothing. |
| **Login Items** | You turn on **Launch at login** | Starting MathPeek when you log in. |

**Privacy:** MathPeek never connects to the internet. It has no analytics, no accounts and no update checks. What it reads on screen is used for the answer and then forgotten: nothing is saved or sent anywhere. Your settings stay on your Mac.

## Settings

Open Settings from the menu bar icon, or by opening MathPeek again while it's running (useful if you've hidden the menu bar icon).

**General:** launch at login, and the menu bar icon.

**MathPeek**
- **Turn on MathPeek** (on): whether the shortcut works. Also in the menu.
- **Shortcut** (⌃⌥=): click it, then press the keys you want, with ⌘, ⌥ or ⌃ (or a function key on its own). Escape cancels; Delete clears it. A warning sign means another app already has it.
- **Area** (Around the pointer):
  - **Around the pointer** reads the sum nearest the pointer within **Width** × **Height**, 700 × 200 points to start with. While you change them, an outline of the area follows the pointer.
  - **An area I drag out** dims the screen when you press the shortcut. Drag over the sum, or click to read around that point. Escape, a right-click or the shortcut again cancels.
- **Keep it on screen for** (5 seconds): how long the answer stays, unless the pointer is on it.
- **Screen Recording:** whether MathPeek may see the screen, with a button to the right page of System Settings.

The menu bar menu has **Turn On MathPeek** and **Read an Area…**, which lets you drag out an area whichever way the shortcut works.

**About:** the version, a link here, and the licences.

## Battery

MathPeek does nothing until you press the shortcut: no timers, no polling and nothing watching the screen. The shortcut is registered with macOS, which costs nothing while it waits. Each press takes one picture of the area and recognises its text once, which takes a fraction of a second.

## Troubleshooting

- **"No maths found":** point closer to the sum, make the area bigger in Settings, or use **Read an Area…** to drag over just the sum. Sums spread over several lines, such as fractions written one above the other, aren't read yet.
- **It read the wrong number:** text recognition can misread small or unusual text. The bubble shows the sum it read above the answer, so you can tell; zoom in (⌘+ in most apps) and try again.
- **Nothing happens when I press the shortcut:** check that MathPeek is on (its menu bar icon is greyed out when it's off). If Settings shows a warning sign by the shortcut, another app has it: record a different one.
- **It asks for Screen Recording again after I allowed it:** macOS only lets MathPeek see the screen once it has been reopened. Quit it from the menu bar and open it again. If it still asks, remove MathPeek from the list in **System Settings → Privacy & Security → Screen & System Audio Recording** with **−**, then press the shortcut to be asked afresh.
- **macOS asks whether MathPeek can keep seeing the screen:** macOS checks this every so often for every app with Screen Recording. Choose **Allow** to keep using MathPeek.

## Uninstall

Quit MathPeek (menu bar icon → Quit), delete it from Applications, and optionally remove its settings:

```bash
defaults delete io.github.doom1337hvh.MathPeek
```

You can also remove it from the lists in **System Settings → Privacy & Security**.

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`); Xcode itself isn't needed.

```bash
git clone https://github.com/doom1337hvh/MathPeek.git
```

```bash
cd MathPeek && scripts/build.sh
```

The app is built to `build/MathPeek.app`. `scripts/build.sh --install` also copies it to `~/Applications` and opens it there. The menu bar icon, Settings window and build scripts come from [AppShell](https://github.com/doom1337hvh/AppShell), which Swift Package Manager fetches on the first build.

Optionally, run `scripts/create-signing-cert.sh` once first. It makes a local code-signing certificate, so the permissions you grant survive rebuilds; otherwise each build is signed ad hoc and macOS treats it as a new app. To make a release, see [docs/RELEASING.md](docs/RELEASING.md).

### How it works

- **The shortcut** (`Hotkeys.swift`) is registered with Carbon's `RegisterEventHotKey`, which works in every app without a permission. While an answer shows, ⌘C is registered the same way, to copy it.
- **The area** (`MathReader.swift`, `AreaPicker.swift`) is a rectangle centred on the pointer, or one you drag out on a dimmed overlay. The overlay is a non-activating panel, so the app you're in keeps the focus.
- **Reading it** (`ScreenReader.swift`): ScreenCaptureKit takes a picture of just that area, leaving out MathPeek's own windows. Vision recognises the text on the Mac (accurate level, language correction off so it doesn't turn numbers into words). Pieces of text on the same row are joined, so a sum split in two is read whole.
- **Finding the sum** (`Maths.swift`): each line is tidied up (× read as x, a unicode minus, √ read as V, thousands separators), split at anything that can't be part of a sum and at `=`, and each piece is parsed. The sum nearest the pointer wins. Vision's second and third readings are tried too.
- **Working it out** (`Maths.swift`) is MathPeek's own small parser: it only ever computes numbers, and bad input simply isn't a sum. Answers are rounded to hide floating-point noise (0.1 + 0.2 is 0.3).
- **The answer** (`AnswerBubble.swift`) is a borderless panel by the pointer that doesn't take the focus, with SwiftUI inside.

```
Sources/MathPeek/
  main.swift, AppDelegate.swift   app lifecycle, menu bar menu, Settings tabs
  MathReader.swift                the shortcut pressed: area, reading, answer
  ScreenReader.swift              screen capture, text recognition, the nearest sum
  Maths.swift                     tidying up text, the parser, formatting answers
  AnswerBubble.swift              the bubble by the pointer
  AreaPicker.swift                dragging out an area; the outline shown while sizing it
  Hotkeys.swift                   global shortcuts and the shortcut recorder
  Permissions.swift               Screen Recording
  Preferences.swift, SettingsView.swift
scripts/                          build, release, signing certificate, icon
```

## License

MathPeek is released under the [MIT License](LICENSE).
