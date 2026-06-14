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

### Roles
The catalogue of roles a meeting can use. **View, add, edit, and delete** roles
here. Each role has a name, an icon (SF Symbol), and default **green / yellow /
red** signal times. Two flags control behaviour: *can appear multiple times*
(numbers the role #1, #2…) and *indent under the previous role* (for sub-roles
such as a speaker's introduction). The built-in roles are seeded on first launch
and can be edited or removed like any other.

### Templates
A template is a reusable, ordered agenda — the list of roles a meeting will
need. **Add Role** picks any role from the catalogue; repeatable roles get the
next number automatically. Each agenda line is an editable text field, so you
can rename a slot (e.g. "Sergeant at Arms (welcome back)") or leave it blank to
show the role's default name.

Slots can be reordered (drag) and deleted. Different meetings can use different
templates, so agendas don't have to match. A starter template, **"3 speeches
(default)"**, is created on first launch.

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
│   ├── Role.swift                     Role model + built-in seeding
│   ├── RoleType.swift                 Built-in role definitions (seed data)
│   ├── RoleTiming.swift               Timing value + legacy RoleDefault
│   ├── Member.swift
│   ├── MeetingTemplate.swift          MeetingTemplate + TemplateSlot
│   └── Meeting.swift                  Meeting + RoleAssignment
└── Views/
    ├── ContentView.swift              Sidebar navigation
    ├── MembersView.swift
    ├── RolesView.swift                Role catalogue: view/add/edit/delete
    ├── TimingEditor.swift             Reusable green/yellow/red editor
    ├── TemplatesView.swift            Template list + agenda editor
    ├── MeetingsView.swift             Meeting list + new-meeting sheet
    └── MeetingDetailView.swift        Role assignment + attendance
```

The Xcode project uses a *synchronized folder group*, so any `.swift` file you
add under `ToastmastersRolePlanner/` is compiled automatically — no need to edit
the project file.
