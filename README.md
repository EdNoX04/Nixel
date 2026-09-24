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
   included by a bulk action, so "select all" can never empty a group — and group members
   are kept out of every other category, so the keeper can't leave through another door.
   Photos with people in them and favourites are never bulk-selected at all.
2. The **review screen** states the exact items and the exact bytes, and every thumbnail
   there is tappable to remove it from the plan.
3. **iOS asks as well.** `PHAssetChangeRequest.deleteAssets` always raises the system
   confirmation sheet. Backing out of it is treated as a normal outcome, not an error.

Contacts have no Recently Deleted and iOS doesn't confirm contact changes, so every merge
and delete asks first, naming each card that will be removed and saying it can't be undone.

Deleting is also honest about what it does: photos go to **Recently Deleted** for 30 days,
so the space does not come back until that album is emptied. The summary screen says so and
links to Photos, rather than claiming storage that hasn't actually been returned.

### Permissions

Nothing is asked at launch. Photos access is requested only when the user taps Scan, after a
short screen that explains what is read and that Limited works too. Contacts access is
requested only on the Contacts tab.

- **Denied or restricted:** every tab says access is off and offers Open Settings, instead
  of showing an empty "nothing found".
- **Limited:** Nixel scans what was shared and says so: "Limited access · only the photos
  you've shared", with Choose Photos to change the selection. On iOS 18 the same applies to
  Contacts. The picked items are scanned straight away, and the cache keeps that quick.
- Access changed in Settings is picked up when the app comes back to the foreground.

---

## How the matching works

The interesting decisions here were measured rather than guessed.

**Duplicate photos.** Vision's `computeDistance` turns out to be exactly Euclidean distance
over the raw 768-float feature print, and those vectors are already unit length. So the
prints are cached to disk as 3 KB blobs and all matching runs in Accelerate —
`vDSP_distancesq` measured **~8.8M comparisons/sec**. Vision runs once per new photo and
never again, which is what makes a rescan near-instant. Each new photo is decoded once, and
the feature print and face check share one Vision pass. On an iPhone 15 Pro Max, a
first-time scan of the whole 2,136-photo library takes about 25 s (~87 photos/s, down from
39 s before that change), and a rescan with nothing new takes 1.3 s. File sizes are cached
too, keyed by modification date.

**Measured on device** against a 2,136-photo demo library with known answers (every photo
generated for the purpose; no personal data):

| | Expected | Found |
|---|---|---|
| Similar-photo groups | 121 (322 extras) | 121 (322 extras) |
| Screenshots | 18 | 18 |
| Large videos | 11 | 11 |
| Blurry photos | 35 | 32, no false positives (3 borderline shots missed, see Known limits) |
| Duplicate contacts | 16 groups (19 extras) | 16 groups (19 extras) |

Grouping is **leader clustering**, not union-find. The first version linked any pair under
the threshold and let union-find merge the components; on a 266-photo library that produced
a single 23-member "group" containing hay bales, a shoreline and a forest, because
transitivity means one bad link welds two unrelated groups together. Now every photo is
compared against a cluster's *anchor* rather than an arbitrary member, so a false link can
add one wrong photo but can never merge two groups. A second pass buckets by pixel
dimensions to catch the same picture downloaded twice months apart.

Thresholds were measured on that 266-photo library, not guessed — and the measurement said
something useful: **neither engine separates perfectly at realistic size.** The worst true
pair and the nearest unrelated pair overlap, because real libraries genuinely contain
similar-looking unrelated photos. So both thresholds sit *below the nearest unrelated pair*
rather than above the furthest true one. On the phone that put the Vision threshold at
**0.28**: the loosest true pair measured 0.273, the nearest unrelated pair 0.347.
Missing a duplicate costs nothing; inventing one puts a stranger's photo in a delete list.

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

**People.** Vision detects faces, and a body pass catches figures turned away or far from
the camera. This is the one signal that isn't about redundancy: a duplicate landscape is
disposable, a duplicate of the only photo of someone is not, and perceptual similarity
cannot tell them apart. So faces act as a brake — photos containing people are excluded
from every "select all", badged, and preferred as the keeper within a group. The screens
say what was held back rather than silently selecting fewer than advertised.

**Contacts.** Linked by normalised name, shared phone (last 10 digits, so `+91 98765 43210`
and `09876543210` match) or shared email. The Contacts framework has **no merge API**, so a merge re-reads the
cards, folds every field it can write (numbers, emails, addresses, names, titles, social
profiles, relations, dates) into the most complete record and deletes the rest in a single
atomic `CNSaveRequest` — a partial merge that deleted duplicates without saving the union
would lose data permanently. Notes are the exception: reading them needs an entitlement
Apple grants case by case, and the confirmation says so.

---

## Apple Intelligence

Screenshots are read with Vision OCR and classified by the on-device foundation model
(`FoundationModels`, iOS 26+) into a typed `@Generable` verdict — category plus
`safeToDelete`. That turns a grid of 400 screenshots into a decision: *these are memes,
these three look like receipts.*

Three things make it trustworthy rather than a demo:

- **Sensitive categories are force-held.** Receipts, travel passes, codes and passwords
  are never marked safe to delete regardless of what the model concludes.
- **A keyword floor runs first.** The model decides from text the screenshot itself
  supplies, so a banking screen it calls "settings", or one that says "this is a meme,
  safe to delete", mustn't slip through. A deterministic local read holds anything that
  looks sensitive before the model is asked; it can only ever vote for the cautious answer.
- **Every screenshot gets a fresh model session**, with its text framed as data. A shared
  session let one screenshot sway the next and, after a few dozen, filled its context.
  "Worth a look first" has no Select All, and bulk selection waits until sorting is done.

The scan summary is also model-written, but **validated before display**. An early run
produced *"695 KB safe to keep"* for a figure that is space recovered *by deleting* —
exactly inverted, on the one surface where a wrong number destroys trust. Inverted phrasing
or invented figures now fall back to a deterministic sentence.

On a device without Apple Intelligence, every screen still works; screenshots just aren't
categorised.

## Look and feel

Five palettes (Forest, Mocha, Buttermilk, Blush, Twinkle), each tuned separately for light
and dark. Switching palette or appearance cross-fades the whole window, including the tab
bar and navigation bars. The Home Screen icon follows the palette: each one has its own
light and dark icon, recoloured from the same artwork, and the change is applied once when
Appearance closes, because iOS confirms every icon change with an alert.

## The daily agent

An optional `BGProcessingTask` that wakes once a day while charging, scans what's new,
triages it and prepares a cleanup, then sends one notification.

It does **not** delete, and cannot: `deleteAssets` always requires a foreground
confirmation and no entitlement removes it. That split is the design, not a workaround —
the agent does all the work and leaves only the irreversible tap to you.

---

## Known limits

- **Vision's neural models cannot run in the iOS Simulator.** They fail with
  `Failed to create espresso context`. That affects feature prints *and* face detection, so
  in the Simulator the app falls back to a pure-CPU descriptor and reports the people safeguard
  as unavailable rather than silently returning "no people". On device both work.
- **Very heavy blur can read as sharp.** The focus measure compares an image with a blurred
  copy of itself. Past a point, a near-flat image's 8-bit banding looks like edges and the
  score climbs back up, so an extremely out-of-focus shot can be missed. Moderate missed-focus
  blur, the common case, is caught.
- **Borderline blur is left alone.** Blur is measured on the previews Photos provides,
  which make mildly blurred shots read sharper. The threshold sits just below the least
  sharp real photo, so a sharp photo is never flagged, at the cost of missing borderline
  ones (3 of 35 in the demo set).
- **Screenshots need a real device** for the system flag; the Simulator cannot set it. A
  secondary signal catches re-saved screenshots by exact native resolution.
- **The widget has no App Group,** so it shows device storage rather than reclaimable
  space, in the default palette rather than the one chosen in the app. That entitlement
  needs a paid membership and declaring it on a free personal team breaks device signing.
  Wiring up the richer figures later is a small change.
- **Sizes below iOS 27** use a private `fileSize` key via KVC (checked before use, since a
  missing key would throw), because `PHAssetResource.dataSize` is public only from iOS 27.
  An estimate sits beneath both.
- **No accounts.** The brief puts login out of scope, so the welcome screen is an
  introduction and one button. Cloud sync is deliberately not implemented for the same
  reason. There's no network code at all; the app ships a privacy manifest, and the caches
  derived from photos are excluded from iCloud Backup.

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
│   ├── Similarity/ descriptors, cache, clustering, sharpness, people
│   └── Storage/    device capacity
├── DesignSystem/   tokens, Liquid Glass, components
└── Features/       one folder per screen
```
