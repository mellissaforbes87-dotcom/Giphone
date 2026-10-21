# Giphone

An iOS proof of concept for importing a user's own Garry's Mod / Source game
data. It does not include the game or an engine, and it does not claim to launch
Garry's Mod.

## Build the iOS prototype

Requirements: macOS, Xcode 15 or newer, and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open Giphone.xcodeproj
```

In Xcode, select the `Giphone` scheme, set your signing team, choose an iPhone
or iPad, and run. Xcode resolves the ZIPFoundation package dependency.

Use **Import Game Files** to select individual files, multiple items, a folder,
or ZIP archives in the iOS Files picker. Imports are copied into the app's
Application Support directory under a new unique folder for each import. The
source items are not moved, replaced, or deleted. Import another folder to
change which installation is detected; earlier imports remain stored. The app
reports storage use and checks the imported layout for the folders and key VPK
files described in GDroid's public installation guide.

## Engine and licensing status

This is an importer and content-layout detector only. A successful content
check is not evidence that the game can run. The referenced GDroid project
publishes Android APKs and documents an engine based on separate Android Source
work; its Android binaries cannot be used as an iOS engine. This workspace does
not contain Garry's Mod or Source engine source code, an iOS-compatible engine
runtime, or permission to redistribute either.

A genuine iOS port requires lawful access to the necessary game and engine
source/build components and explicit rights to build and distribute them for
iOS. It also requires substantial platform work for iOS graphics, audio,
input, filesystem, and device constraints. Imported PC game data alone cannot
provide those components. No engine launch is implemented or claimed here.
