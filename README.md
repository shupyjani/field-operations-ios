# Ajani Field Operations

A native iOS application for community healthcare practitioners working a daily round of
visits. It is built for the phone in a worker's pocket between calls: a clear view of the
shift ahead, the visit in front of them, and the few actions that move that visit forward.

## Current features

**Today** — a shift dashboard with a greeting, the shift window and round, and progress
through the day. An "Up next" card surfaces the visit needing attention, with its scheduled
time, location and a single action to advance it. Below that, the full schedule in
chronological order with planned, in-progress and completed states.

**Visits** — the same schedule with live search across client name, visit reference, visit
type and address, plus filtering by All, Planned, In progress and Completed. Searches that
match nothing show a considered empty state rather than a blank screen.

**Visit detail** — reference, client, visit type and status; scheduled window, planned
duration and travel time from the previous call; the address; a tappable task checklist; and
operational notes. A single primary action moves the visit through its journey:
Planned → En route → Arrived → Completed. Status transitions are validated in the domain
layer, so a stage cannot be skipped or reversed.

**More** — the practitioner's profile and round, two preferences that genuinely change the
interface (whether completed visits stay on Today, and whether completing a visit asks for
confirmation), and application version information.

The interface is built for Dynamic Type — system text styles throughout, scaled metrics for
icon and avatar dimensions, and a shift summary that reflows from a row into a stack once the
text outgrows the width. Alongside that: VoiceOver labels and values on every interactive
element, Reduced Motion honoured at both animation sites, light and dark appearance, and
comfortable touch targets. Layout is verified on iPhone at standard text sizes.

## Current scope

The application runs against generated demonstration records held in memory for the duration
of a launch. There is no backend, authentication or persistence in this checkpoint; the
records exist so the workflows above can be built and exercised end to end.

## Architecture

State lives apart from presentation. The domain layer is plain Swift with no SwiftUI import
and no clock of its own — dates and calendars are passed in, which is what makes the tests
deterministic.

```
AjaniFieldOperations/
├── App/            Entry point and the Today / Visits / More tab structure
├── DesignSystem/   Colour, spacing and radius tokens; cards, badges, controls
├── Domain/         Visit, task, worker and shift models; ordering, progress,
│                   next-visit, search and status-transition rules
├── Data/           Deterministic demonstration records
├── State/          FieldOperationsStore — the shared, observable shift state
├── Features/       Today, Visits and More screens
├── Components/     Views shared across features
└── Support/        Formatting, app metadata, accessibility identifiers
```

`FieldOperationsStore` is an `@Observable`, `@MainActor` class injected through the SwiftUI
environment. It owns the shift and validates every change; views read from it and call it,
and never hold their own copy of a visit. Because the store takes its worker, shift, visits,
reference date and calendar as initialiser parameters, tests construct exactly the shift they
need without touching the wall clock.

## Technology

- Swift and SwiftUI, using the Observation framework for shared state
- Swift Testing for unit tests, XCTest and XCUITest for UI tests
- Apple frameworks only — no third-party dependencies

## Building and testing

An iPhone application targeting iOS 18.0 and later. Requires Xcode 26.6 or later.

```bash
open AjaniFieldOperations/AjaniFieldOperations.xcodeproj
```

Select an iPhone simulator and run with ⌘R, or test with ⌘U. From the command line:

```bash
cd AjaniFieldOperations

# Build
xcodebuild -project AjaniFieldOperations.xcodeproj \
  -scheme AjaniFieldOperations \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Unit and UI tests
xcodebuild -project AjaniFieldOperations.xcodeproj \
  -scheme AjaniFieldOperations \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Planned direction

- Persistence, so a shift survives relaunch and edits made offline are kept
- A backend for schedules and visit records, with sync and conflict handling
- Authentication and per-practitioner authorisation
- Maps and routing between calls, with travel estimates from real positions
- Visit notes captured on site, including photographs and structured observations
- Assistive summarisation of a visit's history and notes, once the data model supports it
