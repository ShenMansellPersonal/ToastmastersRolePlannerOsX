# Toastmasters Role Planner

A native macOS app for tracking club members, meeting agenda templates, and
role assignments for individual meetings.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later

## Opening & running

```sh
open ToastmastersRolePlanner.xcodeproj
```

Then press **⌘R** to build and run. (Or build from the command line with
`xcodebuild -scheme ToastmastersRolePlanner build`.)

Data is stored locally with **SwiftData**.

## What it does

The app has three sections in the sidebar:

### Members
Add, rename, and delete club members. Each member has an **Active** checkbox —
inactive members are kept for history but hidden from the role pickers. Toggle
*Show inactive* to hide them from the list too.

### Templates
A template is a reusable, ordered agenda — the list of roles a meeting will
need. Build one with:

- **Add Role** — pick any single role (Sergeant at Arms, Toastmaster,
  Grammarian, Ah-Counter, Table Topics Master, Table Topics Evaluator,
  General Evaluator – Functionary, General Evaluator – Evaluations, Timekeeper).
- **Add Speaker** — adds a Speaker plus its **Introduction** and **Evaluation**
  as a group. Add it once per speaker; each gets its own number.

Roles can be reordered (drag) and deleted. Different meetings can use different
templates, so agendas don't have to match.

### Meetings
Create a meeting with a **date**, optional **theme**, and a **template**. The
template's roles are snapshotted onto the meeting (so later template edits won't
rewrite past meetings). Then for each role, pick the member who'll fill it (or
leave it **Unassigned**).

The **Attendance** section lets you mark members **absent** for that meeting. If
someone is assigned a role but also marked absent, a warning icon flags it.

## Project structure

```
ToastmastersRolePlanner/
├── ToastmastersRolePlannerApp.swift   App entry + SwiftData container
├── PreviewData.swift                  Sample data for Xcode previews (DEBUG only)
├── Models/
│   ├── RoleType.swift                 Enum of all agenda roles
│   ├── Member.swift
│   ├── MeetingTemplate.swift          MeetingTemplate + TemplateSlot
│   └── Meeting.swift                  Meeting + RoleAssignment
└── Views/
    ├── ContentView.swift              Sidebar navigation
    ├── MembersView.swift
    ├── TemplatesView.swift            Template list + agenda editor
    ├── MeetingsView.swift             Meeting list + new-meeting sheet
    └── MeetingDetailView.swift        Role assignment + attendance
```

The Xcode project uses a *synchronized folder group*, so any `.swift` file you
add under `ToastmastersRolePlanner/` is compiled automatically — no need to edit
the project file.
