# MemoUS art: Memo, the app icon and the tab icons

This art is © 2026 MemoUS. All rights reserved:

- **Memo, the MemoUS mascot**, and its avatar, in `AskMemoUS/Mascot.xcassets/`
- **The tab icons**, in `AskMemoUS/TabIcons.xcassets/`, drawn in the MemoUS icon
  style (one pen line, round nodes, the four-point star lit gold)
- **The app icon** (Memo on night blue), in `AskMemoUS/AppIcon.xcassets/`

It is **not** covered by the Apache License 2.0 that applies to the rest of this
repository. You may build and run this app unchanged with the art included, for
example to try it or check the results. You may not use the art, the name
"Memo" as a mascot, or the name "MemoUS" in your own app, product or marketing.

If you fork this project to make something of your own, remove these three asset
catalogs, set `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml` to your own icon or `""`, replace `MemoMascot` in `AskMemoUS/MemoMascot.swift` with your own art
or an SF Symbol, and give the tabs in `AskMemoUS/RootView.swift` your own icons
or SF Symbols (`Tab("Notes", systemImage: "square.and.pencil", ...)`).

Everything else here (code, eval cases, docs) is under the
[Apache License 2.0](LICENSE).
