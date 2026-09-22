# Nixel

An iPhone storage cleaner that finds duplicate and near-identical photos, screenshots,
large videos, blurry shots and duplicate contacts — and removes them only after you've
seen exactly what's going.

Everything runs on the device. No photo, screenshot or contact is ever uploaded.

---

## Running it

```bash
brew install xcodegen      # only if you don't have it
xcodegen generate
open Nixel.xcodeproj
```

The Xcode project is generated from `project.yml` — edit that, not the `.xcodeproj`.
Deployment target is iOS 17. Select your team under Signing & Capabilities and run.

> **Test on a real iPhone.** Two things do not work in the Simulator: Vision's neural
> matcher (see *Known limits*) and the system screenshot flag. Both are fine on device.

---

## The core loop

**Scan → Review → Clean.** The dashboard shows device storage and what each category could
free. Every category leads to a review step, and that step is the only route to a deletion.

| Category | What it finds |
|---|---|
| Similar Photos | Bursts, retakes, re-saves and resized copies, grouped with a suggested keeper |
| Screenshots | Sorted by what they *are* — safe to clear vs. worth a second look |
| Large Videos | Biggest first, with a preview you can play before deciding |
| Blurry Photos | Out-of-focus shots, judged by a content-independent focus measure |
| Duplicate Contacts | Matched on name, shared phone or shared email; merge or delete |

### Safety

Nothing is deleted without approval, and that is enforced in three places:

1. Selections are **suggestions**. In a similar-photo group the suggested keeper is never
   included by a bulk action, so "select all" can never empty a group.
2. The **review screen** states the exact items and the exact bytes, and every thumbnail
   there is tappable to remove it from the plan.
3. **iOS asks as well.** `PHAssetChangeRequest.deleteAssets` always raises the system
   confirmation sheet. Backing out of it is treated as a normal outcome, not an error.

Deleting is also honest about what it does: photos go to **Recently Deleted** for 30 days,
so the space does not come back until that album is emptied. The summary screen says so and
links to Photos, rather than claiming storage that hasn't actually been returned.

---

## How the matching works

The interesting decisions here were measured rather than guessed.

**Duplicate photos.** Vision's `computeDistance` turns out to be exactly Euclidean distance
over the raw 768-float feature print, and those vectors are already unit length. So the
prints are cached to disk as 3 KB blobs and all matching runs in Accelerate —
`vDSP_distancesq` measured **~8.8M comparisons/sec**. Vision runs once per new photo and
never again, which is what makes a rescan near-instant.

Grouping is a time-ordered sliding window (bursts and retakes sit next to each other in
time) plus a pass that buckets by pixel dimensions, which catches the same picture
downloaded twice months apart. Union-find merges the pairs into groups. Thresholds were
calibrated against a fixture library with known groups, not picked by eye.

**Blurry photos.** Variance of the Laplacian — the textbook measure — was implemented first
and rejected: it cannot tell *"this scene has little detail"* from *"this photo is out of
focus"*, and produced a bimodal distribution across the fixtures with no workable
threshold. What ships instead measures how much high-frequency energy an image loses when
blurred *further*. A crisp photo has detail to destroy; a soft one barely changes. That
cancels out scene content: sharp images scored 0.83–0.87 whether they were smooth gradients
or dense texture, blurred ones 0.42–0.47.

**Screenshots.** Primary signal is the system's own flag. A secondary signal catches
screenshots that *lost* it — AirDropped, re-saved from a messaging app, restored from
backup — by matching the device's exact native resolution, which a camera photo never hits
because sensor aspect ratios differ.

**Contacts.** Linked by normalised name, shared phone (last 10 digits, so `+91 98765 43210`
and `09876543210` match) or shared email. The Contacts framework has **no merge API**, so a
merge folds every field into the most complete record and deletes the rest in a single
atomic `CNSaveRequest` — a partial merge that deleted duplicates without saving the union
would lose data permanently.

---

## Apple Intelligence

Screenshots are read with Vision OCR and classified by the on-device foundation model
(`FoundationModels`, iOS 26+) into a typed `@Generable` verdict — category plus
`safeToDelete`. That turns a grid of 400 screenshots into a decision: *these are memes,
these three look like receipts.*

Two things make it trustworthy rather than a demo:

- **Sensitive categories are force-held.** Receipts, travel passes and verification codes
  are never marked safe to delete regardless of what the model concludes.
- **The model declines some content.** A boarding pass trips it — precisely the screenshot
  we cannot afford to get wrong. A deterministic keyword fallback covers that case, and it
  only ever votes for the cautious answer: it can mark something sensitive, never safe.

The scan summary is also model-written, but **validated before display**. An early run
produced *"695 KB safe to keep"* for a figure that is space recovered *by deleting* —
exactly inverted, on the one surface where a wrong number destroys trust. Inverted phrasing
or invented figures now fall back to a deterministic sentence.

On a device without Apple Intelligence, every screen still works; screenshots just aren't
categorised.

## The daily agent

An optional `BGProcessingTask` that wakes once a day while charging, scans what's new,
triages it and prepares a cleanup, then sends one notification.

It does **not** delete, and cannot: `deleteAssets` always requires a foreground
confirmation and no entitlement removes it. That split is the design, not a workaround —
the agent does all the work and leaves only the irreversible tap to you.

---

## Known limits

- **Vision's neural matcher cannot run in the iOS Simulator.** It fails with
  `Failed to create espresso context` on every image. A pure-CPU descriptor fallback keeps
  the app working there; vectors carry their engine so the two spaces are never compared.
  On device, the neural path is used.
- **Screenshots need a real device** for the system flag (the Simulator cannot set it).
- **Sign in with Apple needs its capability** on the provisioning profile, which a free
  Apple developer account cannot add. The button is real; without the capability it reports
  that plainly and the other routes still work.
- **Sizes below iOS 27** use a private `fileSize` key via KVC, because `PHAssetResource.dataSize`
  is public only from iOS 27. There is a public `AVAsset` fallback beneath both.
- The welcome screen is **optional by design** — the brief puts login out of scope, so
  nothing in the app is ever gated behind it.

## Layout

```
Nixel/
├── App/            entry point, root view, navigation
├── Core/
│   ├── Account/    optional local identity
│   ├── Agent/      daily background task
│   ├── Cleanup/    selection, deletion, scan coordination
│   ├── Contacts/   duplicate matching and merging
│   ├── Intelligence/  OCR + on-device model
│   ├── Permissions/   photos + contacts, incl. limited access
│   ├── Photos/     fetching, sizing, thumbnails
│   ├── Similarity/ descriptors, cache, grouping, sharpness
│   └── Storage/    device capacity
├── DesignSystem/   tokens, Liquid Glass, components
└── Features/       one folder per screen
```
