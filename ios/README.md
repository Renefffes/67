# StudyMate (iOS)

SwiftUI app that turns a student's notes into flashcards, a multiple-choice quiz and an AI tutor chat.

- **Notes in:** type or paste, pick photos, or scan pages with the camera (on-device OCR with Vision).
- **AI engine** (Settings): Automatic uses Apple Intelligence on supported iOS 26 devices, then Gemini if you saved a key, then the built-in offline mode. Offline mode needs no key or network.
- **Storage:** decks live on device in SwiftData. The Gemini key is kept in the Keychain.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd ios
xcodegen generate
open StudyMate.xcodeproj
```

Run tests (unit and UI):

```sh
xcodebuild -project StudyMate.xcodeproj -scheme StudyMate \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Install the Simulator build

Unzip `StudyMate-Simulator.zip`, boot a Simulator and run:

```sh
xcrun simctl install booted StudyMate.app
xcrun simctl launch booted com.renefffes.studymate
```

Or drag `StudyMate.app` onto an open Simulator window.
