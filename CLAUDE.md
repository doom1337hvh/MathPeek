# MathPeek

A Mac menu bar app built on [AppShell](https://github.com/doom1337hvh/AppShell), like the rest of
doom1337hvh's apps. AppShell's README describes the house format every app follows.

- AppShell provides the Settings window, the menu bar icon and menu, Launch at login, the "Move
  to Applications" check, and the build, release and signing scripts. Use them as they are;
  don't rebuild or restyle them here. A change every app should get goes into AppShell: push it,
  then run `swift package update AppShell` here and commit Package.resolved.
- Settings: General first, a tab per topic (`SettingsTab`, whose content is just `Section`s),
  About last. Menu: the app's own items in `MenuBar`'s `items`; AppShell adds Settings… and Quit.
- README: keep the house format's section order, list every permission in the Permissions
  table, and describe Settings tab by tab.
- Build with `scripts/build.sh` (`--install` also copies it to ~/Applications). The app's own
  build steps go in `scripts/hooks/`. Releases: `scripts/release.sh` and docs/RELEASING.md,
  always signed with "MathPeek Local Signing".
- README clips: `scripts/record-clips.sh` (AppShell's recorder) records the scenes listed in
  `scripts/clips.jsonc` from the built app. Launched with `-demo <scene>`, the app acts each one
  out with made-up problems (`DemoScene.swift`); nothing is saved meanwhile. They're filmed off
  screen, on AppShell's stage (`Demo.stage`). `scripts/clip-pages.swift` draws the worksheet
  each scene is acted out on (`docs/clips/pages/`), rehearses the scenes and writes
  clips.jsonc with each pointer's path: run it after changing a page or a scene, then record.
  The Settings clip (`settings-tabs`) is AppShell's own.
