# GeForce NOW iOS Wrapper

Native-style iOS WebKit wrapper for https://play.geforcenow.com/mall/.

## Features
- Full-screen WKWebView with no URL bars
- Android user-agent spoofing
- JavaScript shims to reduce iOS fingerprinting and trigger haptic feedback on button presses
- Zoom, text selection, touch callout, and magnifier suppression
- Persistent `WKWebsiteDataStore.default()` storage for cookies/local storage/session data
- GitHub Actions workflow to generate an unsigned IPA artifact

## Build locally
Open `GeForceNOWiOS.xcodeproj` in Xcode and run on an iPhone.
