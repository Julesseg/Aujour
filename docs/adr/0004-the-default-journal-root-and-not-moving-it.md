# 0004 — The default Journal Root is Aujour's iCloud Drive folder, and a journal never moves on its own

Date: 2026-08-13
Status: accepted

## Context

A new user must be able to write their first Entry without configuring
anything, and deleting the app must cost them nothing (ADR 0001 — the files
are the journal). That points at Aujour's own iCloud Drive folder: it is
visible in the Files app, it syncs between the user's devices, and it outlives
the app.

It is not always available. iCloud Drive can be off, the account signed out,
or the container not yet arrived on a device — and Aujour has no accounts and
no servers of its own to fall back on. The app's own `Documents` folder is
always there and, with file sharing enabled, is visible in the Files app too,
but it goes when the app goes.

So there are two folders and the app has to pick one on every launch. Picking
"whichever is available right now" is the trap: an Entry written in an
airport with iCloud Drive off lands on the device, and once iCloud comes back
the app looks at the other folder and that day is simply gone from the
journal. Nothing is deleted, and the user cannot tell the difference.

## Decision

The default Journal Root is the `Documents` folder of Aujour's iCloud
container (`iCloud.<bundle id>`), published to the Files app via
`NSUbiquitousContainers`. When iCloud Drive is unavailable on a **first**
launch, the journal starts in the app's own `Documents` folder, published via
`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`, and the app says
plainly that it is only on this device.

Which of the two a journal uses is settled once and remembered per device
(never through the synced settings seam — ADR 0003, where the folder is
already per-device by nature). Afterwards:

- a journal that started on the device stays on the device, even once iCloud
  Drive appears;
- a journal that lives in iCloud Drive is **never** re-homed to the device
  when iCloud is away — that is a presentable failure, not a fallback.

Storage failures are shown, never swallowed. In particular an unreachable
Journal Root is an error state rather than an empty listing: "you have not
written anything" and "your journal is somewhere Aujour cannot see" must
never look the same.

## Consequences

- Zero-setup holds in both worlds: the app always has somewhere real to write
  on first launch, and never blocks on an iCloud sign-in it does not need.
- A journal cannot silently split across two folders, at the price of a
  journal that started offline staying on the device until something moves
  it. Moving it is M2's business (custom folder picking, #14) — until then the
  screen tells the user where they are and what that means.
- The app needs the iCloud Documents capability and a container on the App ID;
  ad-hoc and App Store provisioning profiles have to carry it (see README).
- `NSUbiquitousContainers` is only re-read when the app's version changes, so
  changing that entry requires a version bump to take effect.
- A file iCloud has not yet brought down is a real state the store has to
  answer for: it is listed (the day *is* journaled) but reading or writing it
  is refused until the download lands, so a Parked-File-worthy divergence is
  never created by clobbering a version this device never saw.
