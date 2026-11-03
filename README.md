# Whisky Dev

An unofficial experimental fork of [Whisky](https://github.com/Whisky-App/Whisky), based on upstream commit `fd5480a7`. This is not an official continuation or a CrossOver-equivalent product.

## Current build: 0.1.3

- Native SwiftUI bottle management with a pinned Wine 11.21 runtime and macOS DXVK 1.10.3.
- Runtime downloads verified using SHA-256, with offline archive import and replacement rollback.
- Steam installation and managed launch, browser compatibility adapters, and duplicate-launch suppression.
- Two Steam browser modes: Compatibility (default) and Responsive (experimental).

Responsive mode has been reported visible and noticeably faster after restart on one M3 Pro Mac with 18 GB memory. This is Steam UI validation, not a game-performance benchmark. ULTRAKILL and Persona 4 Golden gameplay have not yet been verified. DirectX 12 and D3DMetal are not included.

## Build and development

See [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) for build commands, runtime requirements, tests, and the code map. Current local validation: an ad hoc signed Debug build and 18 passing tests. This is not a notarized public release.

```sh
git clone https://github.com/Erdna883/whisky-dev.git
cd whisky-dev
SKIP_SWIFTLINT=YES bash scripts/build-local.sh
```

The Steam browser adapters are built from `scripts/steam-browser/adapter.c` using `scripts/build-steam-adapter.sh`. The original Valve browser executable is not included in this repository. Runtime archives are downloaded separately; Steam accounts, bottles, and games are not part of the source tree.

## License and provenance

This modified version retains Whisky's GNU GPL v3 license; see [LICENSE](LICENSE). Fork changes were made in November 2026. Original copyright notices and acknowledgments are retained. Dependencies and downloaded runtimes have their own license obligations. Upstream release publishing and funding configuration have been removed from this fork.

## Credits & Acknowledgments

Whisky is possible thanks to the magic of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [SwiftTextTable](https://github.com/scottrhoyt/SwiftyTextTable) by scottrhoyt
- [CrossOver 22.1.1](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, and Nat Brown for their support and contributions!

---

<table>
  <tr>
    <td>
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="./images/cw-dark.png">
          <img src="./images/cw-light.png" width="500">
        </picture>
    </td>
    <td>
        Whisky doesn't exist without CrossOver. Support the work of CodeWeavers using our <a href="https://www.codeweavers.com/store?ad=1010">affiliate link</a>.
    </td>
  </tr>
</table>
