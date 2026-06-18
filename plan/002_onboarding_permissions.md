# Onboarding Phase: Feature Highlighting + Required Permissions

> **Status**: Draft (Planning only, no code changes)
> **Priority**: High
> **Date created**: 2026-03-01

---

## Context

SwitchFix is a menu bar utility that requires system-level permissions to function correctly:

- Accessibility
- Input Monitoring

Without both permissions, keyboard monitoring and correction do not work.
The onboarding phase must clearly explain value, showcase key features, and enforce permission completion.

---

## Problem Statement

New users need to understand:

1. What SwitchFix does and why it is useful.
2. Which features are available and how to use them.
3. That both required permissions are mandatory, not optional.
4. How to open exact Settings pages and complete setup.

If permissions are missing, the app must clearly inform the user and prevent a false "working" state.

---

## Goals

1. Deliver a short onboarding sequence that explains core value in under 2 minutes.
2. Highlight 3-5 key features with practical examples.
3. Require Accessibility + Input Monitoring before completing onboarding.
4. Re-check permissions after user returns from System Settings.
5. Block full app operation until both permissions are applied.

---

## Non-Goals (for this stage)

1. No code implementation in this phase.
2. No major redesign of existing app settings/menu.
3. No analytics implementation details beyond proposed events.

---

## Proposed Onboarding Flow

## Step 1: Welcome + Value

- Headline: "Fix wrong keyboard layout typing automatically."
- One-sentence explanation: detects wrong-layout words, corrects text, and switches layout.
- CTA: `Continue`

## Step 2: Core Features (short showcase)

Use compact cards with one-line examples:

1. Automatic correction (space/enter boundary).
2. Hotkey-only correction.
3. Selection correction via hotkey.
4. Undo/revert last correction.

Guideline:

- Keep each card to 1 primary benefit + 1 minimal example.
- Avoid long technical explanations during onboarding.

## Step 3: Required Permissions Gate (blocking)

Display two mandatory rows:

1. Accessibility: `Granted` / `Missing`
2. Input Monitoring: `Granted` / `Missing`

Actions:

- `Open Accessibility Settings`
- `Open Input Monitoring Settings`
- `Check Again`

Direct links for settings:

- Accessibility:
  - `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- Input Monitoring:
  - `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- Privacy fallback:
  - `x-apple.systempreferences:com.apple.preference.security?Privacy`

Manual fallback text:

- `System Settings -> Privacy & Security -> Accessibility`
- `System Settings -> Privacy & Security -> Input Monitoring`

Blocking rule:

- `Continue` remains disabled until both permissions are `Granted`.

## Step 4: Quick Setup

Allow optional setup before finish:

1. Correction mode: `Automatic` or `Hotkey Only`
2. Trigger hotkey
3. Revert hotkey
4. Launch at Login

Defaults should be prefilled to avoid friction.

## Step 5: Final Readiness Check

Before onboarding completion:

1. Verify Accessibility permission is still granted.
2. Verify Input Monitoring permission is still granted.
3. Verify monitoring can start successfully.

If any check fails:

- Show blocking message:
  - "SwitchFix cannot work until required permissions are enabled."
- Provide buttons to open relevant settings pages.
- Do not mark onboarding as complete.

---

## Permission Enforcement Requirements

Required checks:

1. On first launch.
2. When user taps `Check Again` in onboarding.
3. On app activation after returning from System Settings.
4. On normal app launch after onboarding is completed.

Behavior when missing:

1. Show explicit error/warning state (not silent failure).
2. Keep correction engine in non-operational state.
3. Explain exactly which permission is missing.
4. Provide direct navigation to settings.

Behavior when granted:

1. Update status rows immediately.
2. Allow onboarding completion.
3. Start monitoring only after both are granted.

---

## UX Copy (Draft)

Permission intro:

- "SwitchFix needs two macOS permissions to monitor keystrokes and correct layout mistakes."
- "Without these permissions, the app will not work."

Missing state:

- "Accessibility permission is missing."
- "Input Monitoring permission is missing."

Ready state:

- "All required permissions are enabled. SwitchFix is ready."

---

## Acceptance Criteria

1. Onboarding includes value intro, feature highlight, permission gate, quick setup, and final check.
2. Both permissions are shown with real-time statuses (`Granted`/`Missing`).
3. User cannot finish onboarding while any required permission is missing.
4. User gets direct links to both settings targets and a privacy fallback link.
5. App explicitly informs user that missing permissions prevent functionality.
6. Permission status can be re-validated without restarting onboarding.

---

## Edge Cases

1. User grants one permission but not the other.
2. User closes settings without granting permissions.
3. User revokes permission after onboarding was previously completed.
4. macOS opens only Privacy root page (fallback path still supported).
5. Dev/rebuild scenario where TCC entries reset and permissions become missing again.

---

## Suggested Implementation Notes (for next phase)

Leverage existing permission primitives and deep links already present in:

- `Sources/Utils/Permissions.swift`
- `Sources/SwitchFixApp/AppDelegate.swift`
- `Sources/Core/KeyboardMonitor.swift`

This planning document defines product behavior only. Implementation details belong to phase 003.
