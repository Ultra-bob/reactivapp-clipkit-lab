# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReactivChallengeKit is an iOS SwiftUI application that simulates App Clip behavior. It provides a framework for building and testing App Clip experiences without deploying to a real App Clip target. Clips are URL-invoked, ephemeral, single-task experiences constrained to deliver value in under 30 seconds.

## Build & Run

This is a native Xcode project with zero external dependencies. No SPM packages, CocoaPods, or Carthage.

```bash
# Open project
open ReactivChallengeKit/ReactivChallengeKit.xcodeproj

# Build from command line
xcodebuild -project ReactivChallengeKit/ReactivChallengeKit.xcodeproj -scheme ReactivChallengeKit -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build and run: Cmd+R in Xcode on an iPhone simulator
```

- **Xcode:** 26+ required
- **iOS Target:** 26.1 (iOS 18+)
- **Swift:** 5.0
- **No tests or linting configured**

## Architecture

All source lives under `ReactivChallengeKit/ReactivChallengeKit/`.

### Core Protocol

- **`Protocol/ClipExperience.swift`** — Protocol every clip conforms to. Defines `urlPattern`, `clipName`, `clipDescription`, `init(context:)`, and a SwiftUI `body`.
- **`Protocol/ClipContext.swift`** — Data struct passed to clips containing the invocation URL and extracted `pathParameters`/`queryParameters`.

### Simulator Framework (`Simulator/`)

- **`SimulatorShell.swift`** — Root container view and clip host. Manages the full lifecycle: landing screen, clip invocation, constraint enforcement.
- **`ClipRouter.swift`** — `@Observable` class that handles URL pattern matching, parameter extraction, and routing. All clip experiences are registered in `ClipRouter.allExperiences`. Also contains `AnyClipView` type erasure helper.
- **`LandingView.swift`** — Home screen listing registered clips with InvocationConsole.
- **`InvocationConsole.swift`** — URL input interface replacing real-world QR/NFC triggers.
- **`ConstraintBanner.swift`** — Replica of real App Clip top banner.
- **`MomentTimer.swift`** — 30-second countdown timer (green < 20s, yellow < 30s, red >= 30s).

### Entry Point

`ReactivChallengeKitApp.swift` — Creates `ClipRouter` as `@State`, passes to `SimulatorShell`.

### View Hierarchy

```
ReactivChallengeKitApp → SimulatorShell
  ├── LandingView (no active clip)
  │   ├── InvocationConsole
  │   └── ClipCard per registered clip
  └── ClipHostView (active clip)
      ├── ConstraintBanner
      ├── clip.body (the actual experience)
      └── MomentTimer
```

## How to Create a New Clip

1. Duplicate `Examples/EmptyClipExperience.swift`
2. Implement the `ClipExperience` protocol (set `urlPattern`, `clipName`, `clipDescription`, build the view)
3. Register the new type in `ClipRouter.allExperiences` array
4. Test by entering a matching URL in the InvocationConsole

Existing examples: `HelloClipExperience` (minimal), `TrailCheckInExperience` (stateful with animations).

## Key Patterns

- **URL routing:** Patterns use `:param` syntax (e.g., `"example.com/hello/:name"`). Host matching is case-insensitive and strips `www.` prefix.
- **State management:** `@Observable` on `ClipRouter`, `@Bindable` in views, standard `@State`/`@Binding` in clip implementations.
- **Type erasure:** `AnyClipView` wraps `ClipExperience` conformers so the router can store heterogeneous clips.
- **Visual style:** Dark-mode gradients, glass-morphism via `.glassEffect()` (SwiftUI 6+), monospaced fonts for URLs/technical text.
- **Haptics:** Gated with `#if !targetEnvironment(simulator)` for `UIImpactFeedbackGenerator`.

## App Clip Constraints (design rules)

See `CONSTRAINTS.md` for full details. Key constraints clips must respect:
- URL-invoked only (no app icon launch)
- Ephemeral: no persistent storage, no login, no onboarding
- Single focused task, value delivered in ≤30 seconds
- 15 MB size limit (not enforced in simulator)
