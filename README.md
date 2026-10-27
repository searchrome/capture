# Capture

Capture is a macOS menu bar app for selecting an area of the screen, extracting or translating its
text, and chatting about it. The chat agent can also click, type, press keys, and scroll within the
selected area. Image-to-text can use OpenRouter or run on-device with Apple Vision.

## Requirements

- macOS 14 or later
- Xcode 16 or later, or a Swift 6 toolchain
- An OpenRouter API key for LLM-powered features

## Build and run

From the repository root, build a debug app and launch it:

```sh
scripts/run.sh
```

To build the release app at `build/Capture.app`:

```sh
scripts/build-app.sh release
```

The app lives in the menu bar. Select **Capture Area** or press ⌘⇧6, then drag over the area to
capture. The action bar offers text extraction, translation, chat, and settings.

## First-run setup

1. Grant Screen Recording access when prompted, under System Settings → Privacy & Security →
   Screen & System Audio Recording. You may need to reopen the app after granting access.
2. Open Settings from the menu bar and save an OpenRouter API key. On-device image-to-text does
   not require a key.
3. To let the chat agent control an app, grant Capture Accessibility access under System Settings →
   Privacy & Security → Accessibility when prompted.
4. The default shortcut is ⌘⇧6. macOS may reserve it for **Save picture of the Touch Bar**;
   change that shortcut under System Settings → Keyboard → Keyboard Shortcuts → Screenshots,
   or record a different capture shortcut in Capture's Settings.

Both the vision model for image-to-text and translation and the chat model default to
`qwen/qwen3.7-flash`. Change either in Settings using the model picker or by entering a model ID.
Settings also controls the target language, image-to-text engine, and agent approvals.

## Debug launch arguments

Debug builds accept these macOS user-defaults arguments after `--args` when launching the app:

- `-debugOpenSettings YES` opens Settings on launch.
- `-debugCaptureRect "x,y,width,height"` captures a rectangle on the main display without a drag;
  coordinates are global screen points with the origin at the top left.
- `-debugAction ocr`, `-debugAction translate`, or `-debugAction chat` runs that action after the
  debug capture. Use `-debugChatMessage "message"` with `chat` to send a message automatically.

For example, after building the debug app with `scripts/run.sh`, launch it with:

```sh
open build/Capture.app --args -debugCaptureRect "100,100,400,300" -debugAction chat
```

## Privacy

Captured images are sent to OpenRouter only when you use an LLM action, such as LLM image-to-text,
translation, or chat. On-device image-to-text uses Apple Vision. Your OpenRouter key is stored in
Keychain. **Ask before acting** is enabled by default, so agent actions require your approval unless
you allow all actions for the current task or turn the setting off.
