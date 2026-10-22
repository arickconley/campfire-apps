# Campfire installer artwork

`background.png` is the finished 1536 × 1024 artwork, tagged at 144 DPI so AppKit displays it at 768 × 512 points. It was generated with the built-in ImageGen tool using the supplied Campfire and Mtnwurx logos in `Assets/`. The exact generation prompt is saved in `background-prompt.txt`.

The background intentionally contains no app or folder icons. Finder displays the actual app and Applications shortcut over it, centered at (200, 300) and (568, 300) points, with 104-point icons. Their filename labels remain native and selectable. The root folder opens in icon view without toolbar, sidebar, path bar, or status bar.

`build-dmg.sh` packages a previously built macOS app using the saved artwork and `dmg-settings.py`. It works from any directory on macOS, requires `uvx` (provided by uv), pins dmgbuild to 1.6.7, refuses to overwrite an existing output, and verifies the resulting image checksum. The first run downloads the packaging tools.

```bash
./Packaging/build-dmg.sh \
  /path/to/Campfire.app \
  /private/tmp/Campfire-macOS.dmg
```

Run the example from the app repository root, or use the script’s absolute path from elsewhere. Keep build products outside the repository. The artwork is reused exactly; image generation is not part of the build. Timestamps and filesystem IDs can differ between builds, so output is not byte-for-byte reproducible.

This is packaging tooling only; the apps acquire no new runtime dependencies. Build and sign the intended Release app before packaging. Packaging does not perform signing, notarization, or uploading.

The current corrected artifact is `build/Campfire-macOS-polished.dmg`. It was created with a file-based HFS+ image because this agent session cannot mount disk images. Its background alias uses the image catalog metadata with the volume timestamp conversion checked against a native alias from the preceding mounted image. The preceding alias was checked using macOS bookmark resolution without UI. The first image's manually constructed alias used an incorrect volume creation timestamp and failed with “file not found.” Do not derive an alias volume date directly from the raw HFS+ header: its volume date uses local-time semantics.

The packaged app files, Applications link, icon positions, auto-open folder, and compressed-image checksums were checked without reading the screen. Actual Finder rendering has not been visually inspected. Eject the earlier Campfire images before opening the corrected artifact to avoid duplicate volume names and cached Finder settings. Future builds should use the `build-dmg.sh` script above, which obtains its alias from the mounted filesystem.

The footer artwork was raised to fit above Finder’s bottom bar. The hidden background file has an explicit icon position at (2000, 2000), outside the initial viewport, including when Show Hidden Files is enabled. The artwork revision prompt is in `background-footer-prompt.txt`.

Run `python3 Checks/check-packaging.py` to check argument handling, paths containing spaces, and overwrite protection without mounting a disk image.
