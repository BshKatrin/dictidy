# Changelog

All notable changes to Dictidy. Format: [Keep a Changelog](https://keepachangelog.com/);
versioning: [SemVer](https://semver.org/).

**Release flow:** the section for a version below is published verbatim as that version's GitHub
Release notes and shown in the app's "Update available" screen. To cut a release: move items from
**Unreleased** into a new `## [X.Y.Z] - YYYY-MM-DD` section, commit, then push tag `vX.Y.Z`.

## [Unreleased]

### Added
- **Paste Last Text from the menu bar.** Click in a text box, then choose Paste Last Text to retry
  the latest rewrite or dictation without opening History. The latest output stays available for
  the current session even when history is turned off, and respects your clipboard restore setting.
- **OpenAI rewriting alongside Anthropic.** Save either or both API keys and choose from one model menu.
  Each provider loads its available text models from its API. Keys stay in separate macOS Keychain
  entries, and existing Anthropic selections are preserved.

### Removed
- **Local rewrite models and their downloads.** Rewriting now uses the selected online model, including
  Dictate + Clean. The local rewrite engine and automatic provider fallback are removed. Whisper voice
  transcription continues to run on your Mac.

### Fixed
- **Reopen Settings from Finder.** Opening an already-running Dictidy app now shows Settings when
  all of its windows are closed.
- **Recover permissions after an app replacement.** If macOS no longer recognizes a configured app's
  Accessibility or Microphone access, Dictidy opens its permission controls on launch. The menu's
  Microphone action now requests access when macOS needs a fresh approval, instead of sending you to
  a settings list where Dictidy may not yet appear.

### Changed
- **Two focused writing defaults.** Auto Clean tidies dictated speech while keeping your voice; the new
  Rewrite instruction composes a clear, thoughtful professional message with more freedom over wording
  and flow. Untouched Formal, Friendly, and Translate to English presets are retired. Custom instructions
  and existing Rewrite prompts are preserved.
- **Shared writing rules leave the style in control.** The base instructions preserve facts, uncertainty,
  greetings, signatures, and email paragraph breaks without forcing every style into light editing or
  substantial rewriting. Ordinary hyphens and literal technical text are preserved; prose still avoids
  em and en dashes. Custom base instructions remain intact.

## [1.2.1] - 2026-09-23

### Fixed
- **Paste works in remote desktop windows.** Dictating or rewriting inside Screen Sharing, Windows App
  (Microsoft Remote Desktop), and similar remote desktop apps now pastes your text instead of a single
  letter "v". Dictidy also waits for the clipboard to sync to the remote machine before pasting and
  before restoring your previous clipboard.

## [1.2.0] - 2026-07-22

### Added
- **Cancel dictation and rewrites with Escape.** Press Escape while recording, transcribing, or
  rewriting to discard the in-flight text. The menu-bar icon briefly flashes an X to confirm the
  cancellation was registered.

## [1.1.2] - 2026-07-06

### Fixed
- **Fixed the shortcut recorder crash in signed app bundles.** Opening Settings → Instructions or
  dictation shortcut setup no longer traps in the packaged app; shortcut recording now works from the
  signed release bundle.

## [1.1.1] - 2026-07-06

### Fixed
- **Fixed a crash when setting dictation shortcuts.** Opening the shortcut recorder (Reconfigure in
  Settings, Dictation, and the per-instruction shortcut fields) crashed the app because a bundled
  resource was missing from the packaged app. The app now includes it, so recording shortcuts works.

### Changed
- **Default dictation shortcuts.** When you set up dictation, Dictate + Clean is now bound to
  Control-Space and raw Dictate to Option-Space by default. You can change both in Settings, Dictation.

## [1.1.0] - 2026-07-05

### Added
- **App icon.** Dictidy now has a proper icon (the equalizer logo) in Finder, the app switcher, and
  when you drag it to Applications, in place of the generic blank icon.

### Changed
- **Reworked onboarding.** Dictation and rewriting are now set up as equal, first-class features. Each
  has its own step (Dictation, then Rewrite), followed by a single Permissions step. Nothing is labelled
  "optional": you turn a feature on, download its model right there, and continue once it is ready.
- **Editable base instructions, style-only modes.** A new base prompt holds the shared rules that every
  rewrite follows (return only the rewritten text, never use dashes, keep the meaning and language), so
  each instruction is now just its style. Auto Clean, Formal, Friendly, and Translate to English are
  rewritten as detailed, style-only prompts, with Formal, Friendly, and Translate now as thorough as
  Auto Clean. Edit the base under Settings, Instructions. Instructions you have customized are left
  untouched; unedited built-in ones update automatically.

## [1.0.0] - 2026-07-04

Initial release.

### Added
- **Rewrite anywhere** — select text in any app, press a global hotkey, and Claude (or an on-device
  model) rewrites it in place per your chosen instruction.
- **On-device voice dictation** — local Whisper (`large-v3-turbo`): **Dictate** (raw transcript) and
  **Dictate + Clean** (transcript tidied into clean text), pasted at your cursor. Audio never leaves your Mac.
- **Local on-device rewriting** — Qwen3-4B-Instruct via llama.cpp, as an offline / no-API-key
  alternative to the Claude API, with automatic fallback when the primary provider is unavailable.
- **Unlimited custom instructions** — each with its own name, system prompt, and global shortcut; seeded
  with Auto Clean (⇧⌘R), Formal, Friendly, and Translate to English.
- **History** with a word-level before/after diff and "Rewrite again".
- **First-run onboarding wizard** that verifies each setup step live.
- **Animated Equalizer menu-bar icon** (idle / listening / working / setup / error).
- **In-app updates** — Check for Updates… downloads and installs new signed releases, showing these
  notes first.
