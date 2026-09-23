# Development

Requires macOS 14 or later and the full Xcode app (tested with Xcode 26.6). SwiftMath is vendored at a pinned revision with its library and font licenses, so building and rendering do not fetch remote packages. The generated Xcode project is committed; XcodeGen is only needed when editing `project.yml`.

```sh
./build.sh       # build/随记.app, ad-hoc signed, explicit macOS 14 deployment target
./test.sh        # isolated temporary storage
./scripts/package.sh  # dist/ZIP plus SHA-256 checksum
```

`ARCH=arm64 ./build.sh` or `ARCH=x86_64 ./build.sh` selects a compiler target. The public release is arm64 and has been tested on Apple Silicon; Intel and older operating-system versions have not been tested on hardware.

Source layout:

- `Source/App.swift`: native window, commands, quick entry, save lifecycle.
- `Source/Editor.swift`: TextKit editor, Markdown input, selection tools, tables and timestamps, plus formula RTFD round trips, undo/redo, invalid input, preview confirmation/cancellation and narrow-window sizing.
- `Source/MathFormula.swift` and `Source/FormulaEditor.swift`: offline rendering, embedded LaTeX source, live preview and re-editing.
- `Source/Model.swift`: RTFD/JSON storage and paragraph timestamp reconciliation.
- `Tools/Icon.swift`: procedural application icon artwork.
- `docs/`: static GitHub Pages site, real screenshots with fictional content; no analytics, external fonts, or third-party scripts.

For manual testing use `LOCALNOTES_DATA_DIR=/path/to/disposable/store build/随记.app/Contents/MacOS/LocalNotes`. Never run tests against personal notes. Tests cover headings, fast typing/caret placement, Return/backspace behavior, marked-text composition, inline formatting and undo regression cases, tables, image continuation and persistence, and timestamps, plus formula RTFD round trips, undo/redo, invalid input, preview confirmation/cancellation and narrow-window sizing. Some independent manual checks (actual IME, window appearance) are not automated CI assertions.

The app uses `io.github.flaricy.SwiftNote` as its public bundle identifier. The data directory retains `LocalNotes` for compatibility. There is no telemetry, update server, or cloud service.

Startup is designed to restore the last note directly. Measurements in a small local fixture were sub-second, but are not a cold-start or all-hardware guarantee. Test larger documents before making performance claims.

Release checklist: run tests and build; inspect default, selected text, slash menu, narrow states and the fixed light appearance under both system themes; check that assets contain only fictional notes; package on the documented architecture; publish the ZIP and checksum. Apple notarization is not currently configured.
