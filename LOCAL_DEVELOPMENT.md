# Whisky Dev: local development

This fork starts at Whisky commit `fd5480a7` on branch `codex/local-build`.
It uses Wine 11.21 and macOS DXVK 1.10.3 (20230507 repack).
The macOS DXVK release is older than upstream DXVK; this does not imply support
for every modern DirectX 11 game. DirectX 12 is not part of this build.

## Project location

Clone the repository into a directory of your choice, for example:

```text
/path/to/whisky-dev
```

Open `Whisky.xcodeproj` in Xcode to edit the app.

## Build

```sh
cd "/path/to/whisky-dev"
SKIP_SWIFTLINT=YES bash scripts/build-local.sh
```

This explicitly skips the optional local lint step. Normal builds still require
SwiftLint. The script builds a locally ad hoc signed Debug app with Xcode and puts compiler
output in `../build-dev`; dependencies go in `../packages-dev`.

The build product is `../build-dev/Build/Products/Debug/Whisky Dev.app`.
A copy is provided in the project's `../../outputs` folder for opening in Finder.

## What controls what

- `Whisky.xcodeproj/project.pbxproj`: app name, bundle identifiers, build targets,
  and the explicit local lint-skip option.
- `WhiskyKit/Sources/WhiskyKit/Extensions/Bundle+Extensions.swift`: the shared
  `local.whisky.dev` data namespace, used by the GUI, thumbnail extension, and CLI.
- `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift`: exact runtime
  downloads and SHA-256 hashes. It validates both archives before unpacking into
  staging. It replaces the runtime only after validation; it never deletes bottles.
- `Whisky/Views/Setup/WhiskyWineDownloadView.swift`: downloads both runtime
  archives, or accepts copies of the already downloaded archives for offline setup.
- `Whisky/Views/Setup/WhiskyWineInstallView.swift`: runs installation away from the
  UI thread and shows errors with retry options.
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift`: launches `wine` and `wineserver`,
  passes the selected bottle as `WINEPREFIX`, installs graphics DLLs, and reports
  nonzero dispatcher exits. Child-process failures can still require reading logs.
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift`: graphics overrides
  and HUD settings. Wine supplies DXGI; this DXVK package supplies d3d11/d3d10core.
- `Whisky/Views/Bottle/BottleView.swift`: the Steam button locates steam.exe or
  downloads the official installer, then launches it in the selected bottle.
- `Whisky/Extensions/Bottle+Extensions.swift`: discovers shortcuts in Wine user
  folders without assuming the old engine's `crossover` username.

A bottle is a directory containing Windows-style files and registry data.
`WINEPREFIX` chooses that directory. One runtime can serve multiple bottles,
while each bottle has its own Steam installation and settings.

## Use and verify

1. Quit any earlier Whisky Dev window, then open `outputs/Whisky Dev.app` from
   the i-x20 folder. `outputs/Whisky-Dev.zip` contains the same packaged app.
2. Setup downloads Wine and DXVK if missing. Use the local archives option to
   select the `wine-devel-11.21-osx64.tar.xz` and `dxvk-macos.tar.gz` files in `work`.
3. Select the existing **Steam Test** bottle, or create a new Windows 10 bottle.
4. Click **Steam…** to install or launch Windows Steam. Complete any terms and
   sign-in yourself. The native macOS Steam app is separate.
5. Use Bottle Configuration to toggle DXVK and select an FPS HUD.
6. Use File > Open Logs when diagnosing launch failures.

The data locations are:

```text
~/Library/Application Support/local.whisky.dev/Runtime
~/Library/Containers/local.whisky.dev/Bottles
~/Library/Logs/local.whisky.dev
```

Whisky's upstream app updater, move-to-Applications prompt, and CLI installation
menu are removed. Winetricks is not currently packaged. Original engine-specific
MSync, async DXVK, and D3DMetal/DXR controls are not advertised.

## Tests

```sh
WHISKY_TEST_ARCHIVE="$PWD/../wine-devel-11.21-osx64.tar.xz" \
WHISKY_TEST_DXVK="$PWD/../dxvk-macos.tar.gz" \
swift test --package-path WhiskyKit --scratch-path ../kit-tests-dev
```

Four tests cover corrupt Wine downloads, corrupt graphics downloads, preserving
an existing runtime and bottle files, a valid combined installation, and graphics
DLL override selection. Without the archive environment variables, integration
cases are skipped.

Verified so far: the app builds and opens, setup installs the runtime, a fresh
Windows 10 bottle initializes, the Windows Steam installer window appeared (user confirmed), and Steam's
bootstrap log reports its first update completed. The packaged app was opened
and its Steam button and Steam shortcut are visible. Steam completed its
win32/win64 updates, and steam.exe plus steamwebhelper.exe are running. Steam
sign-in and game launches remain to be verified. ULTRAKILL, Persona 4 Golden, frame rates, audio, and game input
have not been tested. Do not infer gameplay compatibility from the installer test.

## Small practice challenge

In `Whisky/Localizable.xcstrings`, find the English value for `steam.action`.
Type a replacement such as `Windows Steam…`, then rebuild and inspect the button.
This changes the label; `openSteam()` in BottleView.swift controls the action.

## Component sources and notices

- Whisky: https://github.com/Whisky-App/Whisky (GPLv3 or later; see LICENSE).
- Wine package: https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.21
- Wine source: https://gitlab.winehq.org/wine/wine/-/tree/wine-11.21
- macOS DXVK: https://github.com/Gcenx/DXVK-macOS/releases/tag/v1.10.3-20230507-repack
- macOS DXVK source/license: https://github.com/Gcenx/DXVK-macOS/tree/1.10.x

The app downloads the unmodified external runtime archives. It does not include
CrossOver's commercial application or Apple's proprietary D3DMetal component.
Keep the existing GPL license and contributor notices with the modified source.


## Steam black-window fix (0.1.1)

The Steam sign-in screen was initially black. Passing CEF flags to steam.exe did
not pass them to its actual browser processes. A locally compiled adapter now
launches the original steamwebhelper executable with `--disable-gpu` and
`--single-process`. The user confirmed sign-in controls became visible with this
adapter. A successful sign-in and gameplay remain separate checks.

`SteamBrowserCompatibility.prepare` in WhiskyKit is called for normal launches of
steam.exe, including pinned shortcuts and the Steam button. It preserves Valve's
file as `steamwebhelper_valve.exe`, records SHA-256 hashes, recognizes an updated
original, and refuses to overwrite an unknown small helper or use a corrupt
backup. Steam is launched with `-noverifyfiles` to prevent startup file repair
from replacing the adapter. Normal Steam update checks remain enabled; an update
may require quitting Steam and launching it again through Whisky Dev.

This is a compatibility tradeoff: CEF runs in one process rather than its normal
separate browser processes. There are no added certificate-bypass flags and no
host-wide security settings are changed. The setting is exposed in Settings as
**Steam browser compatibility**. Quit Steam before toggling it; the next launch
with it off restores the verified original helper and omits `-noverifyfiles`.

Adapter source: `scripts/steam-browser/adapter.c`. Rebuild with
`bash scripts/build-steam-adapter.sh`; set MINGW_BIN_DIR if LLVM-MinGW lives
elsewhere. The compiler downloaded for this session is the official
LLVM-MinGW 20261020 macOS universal archive, verified with SHA-256
`e9c13e4ede38e715003ffc674d4d00a1088df8235439d1f0c16188ff0704c17e`.
Compiled x86_64 and i686 executables are in `Libraries/SteamBrowserAdapters` and
are packaged as app resources. They contain our adapter code, not Valve's binary.

Ten Swift tests pass: the four previous runtime/settings tests plus six browser
adapter tests covering repeat installation, original-file restoration, Steam
updates, adapter upgrades, corrupt backups, unknown helpers, and architecture
mismatch. A real Wine subprocess test also verified quoted argument forwarding
and child exit code 37. The successful live test's backup hashes were recorded
so the app can recognize that manually installed adapter on the next launch.

Learning exercise: search for `steam.compatibility` in Xcode and change its
English label in the string catalog. That changes the settings text. The flags
in adapter.c and the prepare() call in Wine.swift control the behavior.


## Steam startup reliability (0.1.2)

A failing reopen was traced to a stale running 2.3.5 launcher. Its command omitted
`-noverifyfiles`, so Steam detected the small adapter, extracted its package again,
and restored the original browser. The repair alone took approximately ten seconds
in the observed log. Replacing an app on disk does not replace the running process;
the old launcher has now been stopped and the package updated.

GUI launches, Terminal commands, and newly exported shortcuts now use shared
preparation in `Wine.preparedProgramArguments`. Terminal commands preserve the
compatibility argument and update the adapter before command generation. Existing
shortcuts exported by older builds should be regenerated; launching steam.exe
outside this launcher can still bypass its preparation.

SteamLaunchGate suppresses repeated requests for the same executable for twelve
seconds. Different bottles remain independent, and an immediate startup failure
releases its reservation so the user can retry. The Steam button displays a short
startup state, and the toolbar identifies the running app as 0.1.2.

The existing Steam Windows autostart value in this bottle was `steam.exe -silent`.
The launcher now synchronizes the compatibility flag into that existing registry
value without enabling autostart if the user has disabled it. Compatibility-off
mode removes the flag from that value on the next managed launch. The live bottle
value was updated and verified. Native macOS login items are unaffected.

Live process checks after two clean launches:

| Launch | Browser process started | Correct browser flags | Adapter intact | Startup repair |
|---|---:|---|---|---|
| First | 5.34 seconds | Yes | Yes | Skipped |
| Reopen | 3.21 seconds | Yes | Yes | Skipped |

These times measure the creation of a new adapted browser process, not completion
of all Steam Library rendering or game startup. A separate apparent 0.03-second
warm result was discarded because the preceding browser had not finished exiting.
The user was asked to confirm Library rendering after the final reopen.

Sixteen tests pass using the explicit native SwiftPM runner: thirteen XCTest
cases and three Swift Testing cases. Added coverage includes Terminal arguments,
Windows autostart values, concurrent duplicate requests, independent bottles,
retry after failure, and protection against an old attempt cancelling a newer one.

```sh
WHISKY_TEST_ARCHIVE="$PWD/../wine-devel-11.21-osx64.tar.xz" \
WHISKY_TEST_DXVK="$PWD/../dxvk-macos.tar.gz" \
swift test --build-system native --enable-xctest --enable-swift-testing \
  --package-path WhiskyKit --scratch-path ../kit-tests-native
```

Verification: quit any earlier launcher, open outputs/Whisky Dev.app, confirm
0.1.2 in the toolbar, select Steam Test, and press Steam once. Close Steam and
reopen it to check persistence. Do not repeatedly click while it is starting.
Inspect the newest bottle log for version 0.1.2 and the `-noverifyfiles` argument;
Steam's bootstrap log should report `Verification skipped` with no repeated
package extraction. Normal update checks remain enabled.

Small practice task: search for `steam.starting` in the string catalog and change
its English wording. The label controls feedback; SteamLaunchGate controls the
actual duplicate-start interval.


## Responsive Steam Library mode (0.1.3)

The user reported sluggish navigation even after Steam could sign in reliably.
Low Performance Mode and Low Bandwidth Mode in Steam Settings > Library were
both off. Enabling them helped slightly, but the overall interface remained slow.

Two controlled adapter changes were tried:

- Removing single-process mode while keeping `--disable-gpu` brought the black
  window back. The working adapter was restored before proceeding.
- Using `--disable-gpu --in-process-gpu`, without `--single-process`, rendered
  text and game pages correctly and the user reported noticeably faster navigation.

The second configuration is now available as **Responsive (experimental)** in
Whisky Dev Settings > Steam > Browser mode. It keeps GPU handling in the browser
process while allowing separate page renderers. It still disables hardware GPU
rendering for the browser; this is not a new game graphics backend.

The C adapter reads `WHISKY_STEAM_BROWSER_MODE`. `responsive` selects the faster
configuration; missing, unrecognized, or overlong values retain the previous
`--disable-gpu --single-process` Compatibility configuration. Swift's
SteamBrowserMode resolves the stored preference, and Wine's shared environment
builder passes it to GUI, Terminal, and bottle processes.

Responsive was saved for this user's setup. A fresh installation defaults to
Compatibility until broader testing justifies changing the default. Quit Steam
before changing the mode. If pages become blank, choose Compatibility and reopen
Steam through this launcher. The adapter-off option still restores Valve's file.

After packaging, the production adapter was installed and Steam restarted with
the saved preference. Its new browser process started in 5.37 seconds with
in-process GPU handling, no single-process flag, no startup repair, and the adapter
intact. The user confirmed the packaged 0.1.3 build remained visible and noticeably
faster after that restart. This is a subjective navigation result on one Mac;
there is no measured navigation speedup percentage or gameplay performance claim.

Eighteen Swift tests passed: fifteen XCTest cases and three Swift Testing cases.
Two new checks cover mode resolution/fallback and generated-command propagation.
The actual compiled Windows adapter was also exercised under Wine in Compatibility,
Responsive, and unknown modes, verifying flags, quoted argument preservation, and
child exit-code forwarding. The launcher UI was inspected: it shows version 0.1.3
and the saved Responsive (experimental) selection. The latest GUI launch log
contains version 0.1.3, the Responsive environment setting, and -noverifyfiles.

Verification: navigate between two games, return to the first, then restart Steam
through Whisky Dev and repeat. Keep Low Performance Mode and Low Bandwidth Mode
on. Use the browser-mode selector for fallback rather than editing Steam binaries.

Learning exercise: search for `steam.mode.responsive` in the string catalog and
change the English label. That changes the menu wording. SteamBrowserMode and
adapter.c control the actual process configuration.
