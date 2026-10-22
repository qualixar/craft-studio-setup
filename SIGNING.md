# SIGNING.md — raw macOS signature checks, 2026-10-22 (M5, read-only commands)

Commands (nothing was modified):

```bash
codesign -dv <each ~/tools/craft/<app>/*/<app>-cli>
spctl -a -vv <each CLI>
spctl --assess --type install -vv <each CLI>   # the correct assessment for CLI tools
```

## Summary

- `codesign -dv`: all 13 show a valid Developer ID signature, TeamIdentifier `DJ6XS33FX8` (Learning Machines LLC), Mach-O universal (x86_64 arm64), hardened `runtime` flag.
- `spctl -a -vv` (app-type assessment): all 13 say `rejected (the code is valid but does not seem to be an app)` with `origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)`. **This is expected**: `-a` assesses the binary as an app bundle, which a CLI is not.
- `spctl --assess --type install -vv`: all 13 say `accepted`, `source=Notarized Developer ID`, same origin. This matches the check in the upstream READMEs.

## Raw output

### photocraft (`photocraft-cli-0.12.0-macos-universal/photocraft-cli`)

```
Executable=~/tools/craft/photocraft/photocraft-cli-0.12.0-macos-universal/photocraft-cli
Identifier=ai.storyteller.photocraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=528937 flags=0x10000(runtime) hashes=16523+2 location=embedded
Signature size=9062
Timestamp=21 Oct 2026 at 11:41:00 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=192
.../photocraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../photocraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### vectorcraft (`vectorcraft-cli-0.14.0-macos-universal/vectorcraft-cli`)

```
Executable=~/tools/craft/vectorcraft/vectorcraft-cli-0.14.0-macos-universal/vectorcraft-cli
Identifier=vectorcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=773179 flags=0x10000(runtime) hashes=24156+2 location=embedded
Signature size=9063
Timestamp=20 Oct 2026 at 6:11:16 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../vectorcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../vectorcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### filmcraft (`filmcraft-cli-0.10.0-macos-universal/filmcraft-cli`)

```
Executable=~/tools/craft/filmcraft/filmcraft-cli-0.10.0-macos-universal/filmcraft-cli
Identifier=filmcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=477625 flags=0x10000(runtime) hashes=14920+2 location=embedded
Signature size=9063
Timestamp=20 Oct 2026 at 6:05:16 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../filmcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../filmcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### lightcraft (`lightcraft-cli-0.11.0-macos-universal/lightcraft-cli`)

```
Executable=~/tools/craft/lightcraft/lightcraft-cli-0.11.0-macos-universal/lightcraft-cli
Identifier=lightcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=878874 flags=0x10000(runtime) hashes=27454+7 location=embedded
Signature size=9063
Timestamp=21 Oct 2026 at 11:45:45 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../lightcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../lightcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### effectcraft (`effectcraft-cli-0.14.0-macos-universal/effectcraft-cli`)

```
Executable=~/tools/craft/effectcraft/effectcraft-cli-0.14.0-macos-universal/effectcraft-cli
Identifier=effectcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=564955 flags=0x10000(runtime) hashes=17649+2 location=embedded
Signature size=9063
Timestamp=22 Oct 2026 at 12:17:57 AM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../effectcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../effectcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### soundcraft (`soundcraft-cli-0.11.0-macos-universal/soundcraft-cli`)

```
Executable=~/tools/craft/soundcraft/soundcraft-cli-0.11.0-macos-universal/soundcraft-cli
Identifier=soundcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=67034 flags=0x10000(runtime) hashes=2089+2 location=embedded
Signature size=9062
Timestamp=21 Oct 2026 at 11:32:34 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../soundcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../soundcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### pdfcraft (`pdfcraft-cli-0.11.0-macos-universal/pdfcraft-cli`)

```
Executable=~/tools/craft/pdfcraft/pdfcraft-cli-0.11.0-macos-universal/pdfcraft-cli
Identifier=pdfcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=467800 flags=0x10000(runtime) hashes=14613+2 location=embedded
Signature size=9063
Timestamp=22 Oct 2026 at 1:09:44 AM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=172
.../pdfcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../pdfcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### wordcraft (`wordcraft-cli-0.9.0-macos-universal/wordcraft-cli`)

```
Executable=~/tools/craft/wordcraft/wordcraft-cli-0.9.0-macos-universal/wordcraft-cli
Identifier=wordcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=606361 flags=0x10000(runtime) hashes=18943+2 location=embedded
Signature size=9062
Timestamp=20 Oct 2026 at 11:12:07 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../wordcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../wordcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### gridcraft (`gridcraft-cli-0.10.0-macos-universal/gridcraft-cli`)

```
Executable=~/tools/craft/gridcraft/gridcraft-cli-0.10.0-macos-universal/gridcraft-cli
Identifier=gridcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=106521 flags=0x10000(runtime) hashes=3323+2 location=embedded
Signature size=9062
Timestamp=21 Oct 2026 at 11:32:37 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../gridcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../gridcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### deckcraft (`deckcraft-cli-0.9.0-macos-universal/deckcraft-cli`)

```
Executable=~/tools/craft/deckcraft/deckcraft-cli-0.9.0-macos-universal/deckcraft-cli
Identifier=deckcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=564889 flags=0x10000(runtime) hashes=17647+2 location=embedded
Signature size=9063
Timestamp=20 Oct 2026 at 6:04:37 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../deckcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../deckcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### designcraft (`designcraft-cli-0.11.0-macos-universal/designcraft-cli`)

```
Executable=~/tools/craft/designcraft/designcraft-cli-0.11.0-macos-universal/designcraft-cli
Identifier=designcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=568091 flags=0x10000(runtime) hashes=17747+2 location=embedded
Signature size=9062
Timestamp=21 Oct 2026 at 11:39:43 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=176
.../designcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../designcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### figcraft (`figcraft-cli-0.9.0-macos-universal/figcraft-cli`)

```
Executable=~/tools/craft/figcraft/figcraft-cli-0.9.0-macos-universal/figcraft-cli
Identifier=ai.storyteller.figcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=625287 flags=0x10000(runtime) hashes=19534+2 location=embedded
Signature size=9062
Timestamp=21 Oct 2026 at 11:38:49 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=188
.../figcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../figcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

### cadcraft (`cadcraft-cli-0.10.0-macos-universal/cadcraft-cli`)

```
Executable=~/tools/craft/cadcraft/cadcraft-cli-0.10.0-macos-universal/cadcraft-cli
Identifier=cadcraft-cli
Format=Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=392664 flags=0x10000(runtime) hashes=12265+2 location=embedded
Signature size=9063
Timestamp=20 Oct 2026 at 6:03:36 PM
Info.plist=not bound
TeamIdentifier=DJ6XS33FX8
Runtime Version=15.5.0
Sealed Resources=none
Internal requirements count=1 size=172
.../cadcraft-cli: rejected (the code is valid but does not seem to be an app)
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
.../cadcraft-cli: accepted
source=Notarized Developer ID
origin=Developer ID Application: Learning Machines LLC (DJ6XS33FX8)
```

