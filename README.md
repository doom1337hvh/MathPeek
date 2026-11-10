<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="MathPeek icon">
</p>

<h1 align="center">MathPeek</h1>

<p align="center">
  Point at maths anywhere on screen, press a shortcut, and see the answer by the pointer, with the working step by step.<br>
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

MathPeek is a small menu bar app for the maths you come across on screen: in a web page, a PDF, a worksheet, a screenshot or a photo. Point at a sum like `12 × (3 + 4.5) =`, an equation like `x² − 5x + 6 = 0`, fractions like `h/6 + 2h/9`, or `d/dx x² sin x`, and press **⌃⌥=**. MathPeek reads what's around the pointer, works it out exactly with its own maths engine, and shows the answer right there in a small bubble. Click the bubble to see the working step by step, with what was done and why, a graph, and a box to change the problem and try again: a revision tool as much as a calculator. Everything happens on your Mac.

## Features

- **Works anywhere on screen:** web pages, PDFs, documents, images and screenshots. It reads what's on screen with macOS's own text recognition, so it doesn't matter which app the sum is in.
- **The answer by the pointer:** a small bubble shows the sum it read and its answer, then fades away. It stays while the pointer is on it. Click it, or press ⌘C, to copy the answer.
- **A maths engine, not just a calculator:** exact answers (7/12, 2√3, ln 5/2), with decimals when you want them. It covers:
  - arithmetic with fractions, powers, roots and percentages (`50 + 10%` is 55, `15% of 80` is 12);
  - algebra: simplifying, expanding brackets, factorising, and adding fractions with letters;
  - equations: linear, quadratic (factorising or the formula, with complex roots), cubics and above by the factor theorem, and exponential, log and trig equations;
  - simultaneous equations: linear ones by elimination, and others like `y = x²; y = x + 2` by substitution;
  - calculus: derivatives with the product, quotient and chain rules; integrals by the standard forms, substitution, by parts and partial fractions; definite integrals;
  - substitution, like `3x + 2 when x = 4`.
- **The working, step by step:** click the answer to open it. Each step says what was done and why, like "Find a common denominator: the lowest common multiple of 6 and 9 is 18". There's a graph where it helps, and you can copy the answer, the whole working, or LaTeX.
- **Explore it:** the working window has tabs along the top. **Steps** goes through each step, with why it works and the mistake to watch out for (↑ and ↓ move through them). **Breakdown** takes the problem apart: what kind it is, and each term, which you can click to learn what it is.
- **Every answer:** when there are several, like the three roots of a cubic, each gets its own pill. Click one to see it checked by putting it back in, and marked on the **Graph** tab.
- **Several problems at once:** every separate problem in the area is found and solved. The bubble lists them all, and the working window switches between them. Equations that belong together, with the same unknowns, are solved as simultaneous equations.
- **Change it and try again:** edit the problem in the working window, or choose **Type a Problem…** from the menu.
- **Checks written answers:** point at `12 × 7.5 = 91` and it tells you the answer is 90.
- **Reads maths laid out on the page:** stacked fractions, and word problems, with Apple Intelligence on your Mac. It only turns them into maths; MathPeek's engine works out the answer. See [Permissions](#permissions).
- **The right problem:** when there are several, it picks the one nearest the pointer, skips plain numbers, and copes with what text recognition gets wrong (× read as x, x² read as x2).
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
- Optional: Apple Intelligence on macOS 27 or later, for stacked fractions and word problems

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

**Apple Intelligence** isn't a permission, but if it's on (in System Settings and in MathPeek's settings), MathPeek asks Apple's on-device model to read maths laid out over several lines and word problems. That model runs on your Mac; MathPeek never uses Apple's cloud model.

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
- **Angles** (Degrees): for sin, cos and tan. A ° or π in the problem decides for it, and calculus always uses radians.
- **Use Apple Intelligence** (on, where available): read stacked fractions and word problems with Apple's on-device model.
- **Keep it on screen for** (5 seconds): how long the answer stays, unless the pointer is on it. Click it for the working; ⌘C copies the answer.
- **Window transparency** (55 %): how much of what's behind shows through the working window. 0 % is solid.
- **Screen Recording:** whether MathPeek may see the screen, with a button to the right page of System Settings.

The menu bar menu has **Turn On MathPeek**, **Read an Area…** (drag out an area whichever way the shortcut works), and **Type a Problem…** (opens the working window to type one in).

**About:** the version, a link here, and the licences.

## Battery

MathPeek does nothing until you press the shortcut: no timers, no polling and nothing watching the screen. The shortcut is registered with macOS, which costs nothing while it waits. At launch it warms up text recognition once, so the first press is as quick as the rest. Each press takes one picture of the area and recognises its text once, in a few hundredths of a second; only stacked fractions and word problems also ask Apple Intelligence, which takes a second or two.

## Troubleshooting

- **"No maths found":** point closer to the maths, make the area bigger in Settings, or use **Read an Area…** to drag over just the problem. Fractions written one above the other and word problems need **Use Apple Intelligence**.
- **It read the wrong thing:** text recognition can misread small or unusual text. The bubble shows what it read above the answer; click it, fix the problem in the box at the bottom, and press **Work It Out**. Zooming in (⌘+ in most apps) helps too.
- **"Can't work that out yet":** MathPeek read it but its engine doesn't cover it. Try writing it another way in the working window.
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
- **Reading it** (`ScreenReader.swift`): ScreenCaptureKit takes a picture of just that area, leaving out MathPeek's own windows (the capture filters are kept between presses). Vision recognises the text on the Mac, with language correction off so it doesn't turn maths into words; it's warmed up at launch, because its first run can take many seconds.
- **Finding the problem** (`ProblemFinder.swift`) picks the maths out of each line: the whole line if it's a problem ("Solve 2x + 3 = 11"), or the runs of maths between words. It fixes common misreadings and puts fractions back together from where their parts are. The problem nearest the pointer wins.
- **Apple Intelligence** (`Tutor.swift`), when it's on, reads stacked fractions from the picture and turns word problems into equations, with Apple's on-device model (FoundationModels). It only ever writes maths; it doesn't answer.
- **The engine** (`Engine/`) works with exact fractions, falling back to decimals only when it has to:
  - `Parser.swift` reads the problem;
  - `Simplify.swift` keeps expressions in a standard form;
  - `Polynomial.swift` handles cancelling, factorising and roots;
  - `Solver.swift` does equations and simultaneous equations;
  - `Calculus.swift` does differentiation and integration;
  - `Engine.swift` handles the rest and writes the working a teacher would show;
  - `Format.swift` writes it all out as text and LaTeX.
- **Several problems** (`ScreenReader.swift`): every reading of every line is gathered, overlapping ones give way to the longest, and question numbers and wide gaps separate problems. Besides the one nearest the pointer, only clear maths is kept, so dates and page numbers aren't. Equations with the same unknowns, as many as there are unknowns, are grouped as simultaneous equations.
- **The answer** (`AnswerBubble.swift`) is a dark, semi-transparent panel by the pointer that doesn't take the focus. Clicking it opens the working (`LearnWindow.swift`): a window with a see-through backdrop (an `NSVisualEffectView` under a dark tint) and tabs along the top, where `MathView.swift` draws the maths as it's written on paper and Swift Charts draws the graph. `Engine/Insight.swift` takes the problem apart, explains why each step works, and checks each answer.

```
Sources/MathPeek/
  main.swift, AppDelegate.swift   app lifecycle, menu bar menu, Settings tabs
  MathReader.swift                the shortcut pressed: area, reading, answer
  ScreenReader.swift              screen capture, text recognition, choosing the problem
  ProblemFinder.swift             the maths in a line of text; stacked fractions
  Tutor.swift                     Apple Intelligence: pictures and word problems into maths
  Engine/                         the maths engine: parser, simplifier, solver, calculus,
                                  working, text and LaTeX
  AnswerBubble.swift              the bubble by the pointer
  LearnWindow.swift, MathView.swift   the working, step by step, and drawing maths
  AreaPicker.swift                dragging out an area; the outline shown while sizing it
  Hotkeys.swift                   global shortcuts and the shortcut recorder
  Permissions.swift               Screen Recording
  Preferences.swift, SettingsView.swift
scripts/                          build, release, signing certificate, icon
```

## License

MathPeek is released under the [MIT License](LICENSE).
