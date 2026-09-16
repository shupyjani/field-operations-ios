# Ajani Field Operations

**Ajani Field Operations** is a community healthcare operations product for practitioners who
work a daily round of visits. Its iPhone application is named **Ajani Mobile** — a native
SwiftUI app targeting iOS 18 and later, built for the phone in a worker's pocket between
calls: a clear view of the shift ahead, the visit in front of them, and the few actions that
move that visit forward.

## Screens

Native iPhone captures using demonstration data.

|  |  |
|:---:|:---:|
| <img src="docs/images/ajani-mobile-today-light.png" alt="Today: Shift overview, progress and active visit" width="300"><br>**Today** — Shift overview, progress and active visit | <img src="docs/images/ajani-mobile-visits-dark.png" alt="Visits: Searchable schedule and operational statuses" width="300"><br>**Visits** — Searchable schedule and operational statuses |
| <img src="docs/images/ajani-mobile-visit-detail-light.png" alt="Visit detail: Task completion and operational notes" width="300"><br>**Visit detail** — Task completion and operational notes | <img src="docs/images/ajani-mobile-ajani-assistant-light.png" alt="Ajani Assistant: Questions answered from recorded tasks; shown using built-in guidance" width="300"><br>**Ajani Assistant** — Questions answered from recorded tasks; shown using built-in guidance |
| <img src="docs/images/ajani-mobile-visit-cancel-dark.png" alt="Cancel visit: Reason selection and an operational note" width="300"><br>**Cancel visit** — Reason selection and an operational note | <img src="docs/images/ajani-mobile-more-dark.png" alt="More: Preferences, Assistant access and application identity" width="300"><br>**More** — Preferences, Assistant access and application identity |

## What it does

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
Planned → En route → Arrived → Completed.

**More** — the practitioner's profile and round, two preferences that genuinely change the
interface, and application information.

## Engineering highlights

- **Validated state transitions.** A visit advances Planned → En route → Arrived → Completed.
  The rules live in the domain layer, so a stage cannot be skipped or reversed, and the
  interface only ever offers the action that is actually available.
- **Search and filtering.** Case- and diacritic-insensitive matching across four fields,
  combined with status filtering, resolved in one place and reused by both screens.
- **Task completion.** Checklist items are ticked off against the visit and counted back into
  the header, so progress within a call is visible at a glance.
- **Preference-driven behaviour.** Both settings change what the app does: one hides completed
  visits from Today, the other requires confirmation before a visit is closed.
- **Responsive Dynamic Type.** System text styles throughout, scaled metrics for icon and
  avatar dimensions, and layouts that reflow from a row into a stack — the shift summary and
  the visit row's time and status badge — once the text outgrows the available width.
- **Dark appearance.** A single set of adaptive design tokens drives both appearances, as the
  Visits and More screens above show.
- **Reduced Motion.** Honoured at both animation sites, so the interface stops moving for
  people who ask it to.
- **Accessibility identifiers.** A single source of truth shared by the app and the UI tests,
  alongside VoiceOver labels and values on interactive elements and comfortable touch targets.
- **Domain separation.** The domain layer is plain Swift with no SwiftUI import and no clock
  of its own — dates and calendars are passed in.
- **Automated tests.** 45 unit tests across 7 suites, plus 9 UI tests covering launch, tab
  navigation, opening a visit, the full status journey, search and the navigation chrome.

## Architecture

State lives apart from presentation. Because the domain layer takes its dates and calendars as
parameters, the tests construct exactly the shift they need without touching the wall clock.

```
AjaniFieldOperations/
├── App/            Entry point and the Today / Visits / More tab structure
├── DesignSystem/   Colour, spacing and radius tokens; cards, badges, controls
├── Domain/         Visit, task, worker and shift models; ordering, progress,
│                   next-visit, search and status-transition rules
├── Data/           Demonstration records
├── State/          FieldOperationsStore — the shared, observable shift state
├── Features/       Today, Visits and More screens
├── Components/     Views shared across features
└── Support/        Formatting, app metadata, accessibility identifiers
```

`FieldOperationsStore` is an `@Observable`, `@MainActor` class injected through the SwiftUI
environment. It owns the shift and validates every change; views read from it and call it, and
never hold their own copy of a visit.

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

## Current scope

The application runs against generated demonstration records held in memory for the duration
of a launch, so the workflows above can be built and exercised end to end.

## Planned direction

- Persistence, so a shift survives relaunch and edits made between calls are kept
- A backend for schedules and visit records, with synchronisation and conflict handling
- Authentication and per-practitioner authorisation
- Routing between calls, with travel estimates from real positions
- Visit notes captured on site, including photographs and structured observations
