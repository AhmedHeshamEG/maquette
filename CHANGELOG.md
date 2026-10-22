# Changelog

All notable changes to hmm-kit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [0.14.0] - 2026-10-19

Built with Maquette 0.24.

### Added
- **HmmDocuments**: packs, `HmmPackManifest` (`pack.json`: name, author, licence, items and the files they need), checked
  before anything is read (the app's own, no newer format, no path outside the pack). `HmmLicence` in plain words (use in
  anything, credit me, personal use only, the author's own words) with the sentence a licence file carries;
  `HmmPackOrigin` keeps who made an imported thing. An item from someone else's pack keeps its author and licence.
- **HmmDocuments**: `GalleryFolders`: a gallery's stacks as real folders beside the documents, one level deep (listing,
  moving with unique names, renaming, dissolving, the old `gallery.json` stacks moved into folders once).
  `GalleryArrangement` keeps a sort per stack and remembers that its stacks are folders.
- **HmmDesign**: `HmmStudio`, the Studio grammar (the made thing at the top, pages under it); **HmmDocuments**:
  `HmmStudioAbout`, `HmmPackForm` and `HmmLicencePicker`.

## [0.13.0] - 2026-10-19

Built with Maquette 0.23.

### Added
- **HmmVector** (new, pure Swift): `SVG.read` turns an SVG file into filled shapes (`VectorDrawing`): every path command
  with arcs, rectangles (rounded), circles, ellipses, polygons, nested groups and `<svg>`, transforms, `<use>` and
  symbols, paint that inherits, `<style>` rules by class, id and tag, and gradients as the average of their stops. Curves
  are flattened within a tolerance. Strokes, text and pictures can't become filled outlines, so they are counted in
  `skipped` for the app to name.
- **HmmMedia**: `SoundLevels` and `SoundAnalysis` (pure Swift): a sound's loudness and bass sixty times a second, its
  beats and tempo (autocorrelation of onsets, a grid locked onto each kick), a pulse on each beat; base64 in JSON.
  `SoundReader` reads any file AVFoundation opens as mono samples and measures it.

## [0.12.0] - 2026-10-19

Built with Maquette 0.22.

### Added
- **HmmMedia**: HDR video, `VideoCodecKind.hevcHDR`: 10-bit HEVC in HLG with BT.2020 colour (.mov); its buffers are RGBA
  half floats tagged with their colour, so a renderer writes HDR highlights straight in.
- **HmmMedia**: spatial video for Vision Pro, `SpatialVideoEncoder`: MV-HEVC with the left and right eye tagged, the
  cameras' baseline, field of view and the screen's depth, and the same sound track as a flat video (`isSupported`
  says whether the device encodes it).
- **HmmMedia**: `ImageWriters.spatialPhoto` (a HEIC stereo pair with each eye's camera) and `ImageWriters.panorama` (an
  equirectangular JPEG with Photo Sphere tags).
- **HmmMedia**: `SphericalVideo` marks a finished MP4 or MOV as 360° video (the Spherical Video V1 box YouTube and
  headsets read), moving the media's chunk offsets when the movie box comes first. Pure Swift.

## [0.11.0] - 2026-10-18

Built with Maquette 0.21.

### Added
- **HmmMedia**: `VideoEncoder.canEncode(_:)` says whether this device really writes a codec (it encodes two small frames:
  ProRes 4444 needs a media engine some iPads don't have), so an app offers only what it can make.

## [0.10.0] - 2026-10-15

Built with Maquette 0.18.

### Added
- **HmmDesign**: the colour picker (`HmmColourPicker`, Procreate's): the colour in hand and the one before it, the
  scene's palette and the colours used lately, a Disc (hue round the ring, saturation across the disc, brightness on
  its slider), Values (HSB, RGB, hex) and saved Palettes, and an app's own extra page. Its maths is pure and tested:
  `HmmColour` (sRGB with hex), `HmmHSB`, `HmmColourDisc`, `HmmColourHistory`, `HmmPalette`, `HmmColourMemory` (kept
  in `UserDefaults`). Swatches can be dragged out as their hex.

## [0.9.0] - 2026-10-13

Built with Maquette 0.15.

### Added
- **HmmDesign**: every number a slider (`HmmScrub`: a point of slow drag is a fine step, fast drags go up to twenty
  times as far, clamped to a range; `HmmNumberPill`: a 44 pt pill dragged to scrub, tapped to type on our number pad,
  the Pencil Pro clicking at the range's end). `HmmSidebarSlider` clicks at its ends too.
- **HmmDesign**: touches counted without claiming them (`HmmTouches`, installed by the gesture layer); clusters that rest
  as faint rails and wake on a touch (`HmmCornerCluster`); Procreate's colour loupe (`HmmColourLoupe`: the colour under
  the finger above, the one in the hand below).
- **HmmDesign**: `HmmSidebar(showsUndo:)` hides the undo and redo buttons; `HmmPencilHaptics.buzz(at:)`.

### Changed
- Toasts stay two seconds and leave on any touch; the guide line leaves after 2.5 seconds or a touch
  (`hmmGuideLine(_:duration:)`).

## [0.8.0] - 2026-10-12

Built with Maquette 0.13.

### Added
- **HmmDesign**: our number pad (`HmmNumberPad`, `hmmNumberPad`: a popover beside the number, never the system
  keyboard; `HmmNumberPadEntry` is its typing, pure, and `HmmArithmetic` reads plain sums); the hand shortcuts as
  switches (`HmmShortcut`: each on until Settings switches it off); the squeeze menu (`HmmQuickMenu`: up to six buttons
  in a ring at the Pencil's tip); the edit bar (`hmmEditBar`); haptics felt in the Pencil (`HmmPencilHaptics`, Apple
  Pencil Pro).
- **HmmDesign**: the universal gestures repeat redo with three fingers held, and three fingers swiped down open the
  edit bar (`HmmGestureActions.editMenu`). Each obeys its switch.
- **HmmBrush**: the Pencil's feel (`HmmPencilFeel`): a pressure curve fitted from two strokes (your lightest line, your
  heaviest), presets for a light, normal or heavy hand, stabilisation, and pressure from speed for a Pencil that has
  none. Kept on the device for every studio app.
- **HmmBoardUI**: the Pencil's double-tap (what the iPad's Pencil setting says) and squeeze (the quick menu) on the
  board; strokes go through the Pencil's feel.

### Notes
- U3's spike (`PencilSDKSpikeTests`): squeeze, the Pencil's own haptics (`UICanvasFeedbackGenerator`) and the system
  loupe (`UITextLoupeSession`) are all on the pinned SDK.

## [0.7.0] - 2026-10-11

Built with Maquette 0.12.

### Added
- **HmmHeld** (new, pure Swift): held features. An app lists its own (`HmmHeldFeature`); `HmmHeld` reads what a build
  holds back from the Info.plist key `HmmHeld` (a space-separated list the App Store configuration fills), once.
- **HmmDesign**: panels moved by hand (`HmmPanel(movable:)`, `hmmMovable`, `HmmPanelPosition`, kept inside
  `hmmPanelBounds`; double-tap the title to send one home); the undo line (`hmmUndoLine`); the guide line
  (`hmmGuideLine`); the instructions switch (`HmmInstructions`, `HmmHint`); chrome restraint (`hmmRestrainedChrome`:
  neutral glass, and only an `accent` button wears the accent); the sidebar at rest (`HmmSidebar(resting:wake:)`).

### Changed
- **HmmDesign**: a pill's label is never cut; it takes a second line. Panel titles take two lines.

## [0.6.1] - 2026-10-11

Built with Maquette 0.11.

### Fixed
- **HmmDiagnostics**: `DeviceTier.classify` puts an 8 GB iPad in Tier A even when it reports less than 7.5 GiB of
  memory (the line is 7 GiB now; no 6 GB iPad comes near it).

## [0.6.0] - 2026-10-11

Built with Maquette 0.10.1.

### Added
- **HmmDiagnostics**: the feel recorder. `FeelProbe` watches every touch in the app's windows for a while (a gesture
  recogniser that never recognises), the main thread's busy stretches (a run-loop observer) and every refresh (a
  display link), and Metal surfaces report their frames to it; `FeelLog` follows each touch to the refresh that shows
  its answer and splits the time into input, main thread, encode and GPU; `FeelRecording` is the JSON an app shares.
  `FeelProbe.noteLaunched` measures a cold launch from the process's start.

### Changed
- **HmmBoardUI**: the board's canvas reports its frames to the feel recorder while it records.

## [0.5.0] - 2026-10-08

Built with Maquette 0.9.

### Added
- **HmmBrush**: the brush engine's arithmetic, moved here from Maquette so every app draws with the same brushes.
  `Brush` and its settings, `BrushStroker` (Pencil samples into a stored path, a path into stamps, seeded so a stroke
  is the same in every render), the built-in tips, grains and ten brushes (all drawn by code), `BrushKey` content keys,
  `Vec2` and `SeededRandom`. A point a brush walks along says its coordinates (`BrushPoint.brushCoordinates`), so one
  renderer draws 2D and 3D strokes.
- **HmmBrushRender**: the brush engine's Metal half. `Brush.metal` stamps strokes in a 3D scene or flat; flat strokes
  can stay in their own units and be placed by the shader (`BrushBatch.Placement`), with a texturized grain fixed to
  those units and hairlines kept visible far out. `BrushStamper`, `BrushTextureCache`, and `BrushShaders` (the
  library and pipelines for stamps, flat fills, layers and pictures).
- **HmmBoard**: the Schizzo board. An endless sheet of brush strokes, pictures, notes, arrows (their ends follow what
  they point at) and frames (they carry what lies in them). `BoardCommand` with exact inverses, `BoardOperations`,
  `BoardSession` (the six tools, selection, moving and resizing, an eraser that cuts strokes where it touched, copy
  and paste between boards), `BoardViewport`, `BoardDrawList` and `BoardLayerPlan` (what a board looks like and when
  its cached picture must be redrawn), `BoardStore` (`board.json`, the history journal, pictures by content).
- **HmmBoardUI**: the board on screen. `BoardRenderer` keeps the board in one layer a little larger than the screen and
  draws only what moves over it; `BoardCanvasView` takes the Pencil (pressure, tilt, coalesced and predicted touches),
  fingers that pan and pinch, hover, the hold menu and dropped pictures; `BoardModel` journals every change and can
  hand the app a picture of a frame or a selection as a pin; `HmmBoardScreen` is the whole screen in the studio's
  layout, with the app's own brush row and colour chooser plugged in.

## [0.4.0] - 2026-10-07

Built with Maquette 0.8.

### Added
- **HmmDesign**: `HmmHoldMenu`, the hold menu's one grammar: Duplicate · Rename · Copy · Paste, one to three extras,
  Delete last in red; a row a thing can't do is dimmed, never missing. `hmmHoldMenu(_:)` puts it on any SwiftUI view,
  `uiMenu()` builds it for UIKit, and `HmmHoldMenuInteraction` opens it under a still finger on a canvas (a moving
  finger stays a drag); `hmmHoldMenu(at:)` does the same over an area SwiftUI draws as one picture.
- **HmmDesign**: `HmmPencilOrHand`: one finger makes until an Apple Pencil has touched; from then on the Pencil makes
  and fingers move the view, with one switch to let fingers make too. Remembered in `UserDefaults`.
- **HmmDesign**: `HmmColourWell`, and `HmmSidebar(accessory:)` to put it (or anything a tool needs) under the two
  sliders.

## [0.3.0] - 2026-10-05

Built with Maquette 0.2.

### Added
- **HmmDesign**: resizable panels. `HmmPanel(sizing:)` shows a grip in the bottom corner away from the edge the panel
  hangs from; dragging it resizes the panel, double-tapping it restores the original size, and the size is
  remembered per panel on the device (`HmmPanelSizing`, `HmmPanelSize`). Any view gets the same grip with
  `hmmResizable(_:size:defaultWidth:…)` (an inspector placed by `HmmFloatingPlacement` sizes itself from it).
- **HmmDesign**: `HmmFloatingPlacement`, where a floating panel goes beside what it's about (an inspector beside the
  selection): keeps its side while it fits, flips at the screen's edge, covers as little as it can when neither side
  fits, stays inside the bounds.
- **HmmDocuments**: `GalleryArrangement`, the Home gallery's stacks, search and sort (Recent, Name, Date created),
  saved as `gallery.json` beside the documents.

## [0.2.0] - 2026-10-04

Built with Maquette 0.1.

### Added
- **HmmDocuments**: `HistoryJournal`, the history journal of CONTEXT §5. Every committed change is one JSON line in
  a segment, group-committed within 50 ms on a serial queue; checkpoints (snapshot + undo history stored once per
  step) keep opening to the checkpoint plus a short tail; the undo stack is restored on open, older steps load
  lazily; a half-written last line is skipped, a damaged checkpoint falls back to the previous one; recorded ops
  migrate across command schemas. `HistoryVersions` keeps named and automatic versions.
- **HmmCommands**: `HistoryOp` and journaling on `CommandStack` (`recordsOps`, `takePendingOps`, `replay`,
  `restore`, `prependUndo`, `isQuiet`); `HistoryEntry` has a stable `id` and is `Codable` when its command is.
- **HmmDiagnostics**: `DeviceTier` (A/B/C from the GPU family and memory, `-device-tier` override) and `LoadMeter`
  (the hidden load meter: frame-time and scene-cost pressure with hysteresis).

## [0.1.0] - 2026-10-01

First release, created with 3D-lowey 2.0.

### Added
- **HmmDesign**: tokens (dark and light neutrals, one accent per app, semantic colours, type scale, 4-pt spacing,
  radii, touch targets, motion springs with a Reduce Motion cross-fade); Liquid Glass chrome with a Reduce
  Transparency fallback; `HmmButton`, `HmmPillButton`, `HmmSlider`, `HmmCornerCluster`, `HmmSidebar`, `HmmPanel`,
  `HmmSheet`, `HmmSectionHeader`, `HmmToast`, `HmmEmptyState`; the universal gestures (two-finger tap undo,
  three-finger tap redo, two-finger hold rapid undo, four-finger tap hides the chrome); haptics; the Design Gallery.
- **HmmCommands**: `EditCommand`, `CommandStack` (coalescing, nested groups, cancel, limits, menu titles) and the
  Undo menu commands.
- **HmmDocuments**: `DocumentPackage` with `manifest.json`, `SafeFileWriter` (atomic, `.bak` recovery),
  `SchemaCoder` (versioned JSON, migration chains), `PackageMigrator` (upgrades with a `.v<N>.bak` copy),
  `AutosaveScheduler`, `DocumentLocator` (iCloud Drive with a local fallback), coordinated access,
  `DocumentPresenter`, `ConflictResolver` and `HmmConflictSheet`.
- **HmmTranscript**: `Transcript`, editing that keeps timings, SRT / WebVTT / JSON, script alignment,
  `TranscriptionEngine` with engine selection by supported language, `SpeechAnalyzerEngine`.
- **HmmMedia**: `EncodeSettings`, `VideoEncoder` (H.264, HEVC, HEVC with alpha, ProRes 4444, AAC),
  `MediaInspector` and `ExportVerification`, PNG and GIF writers.
- **HmmBridge**: HTTP parsing and serialisation, local-network policy, `PairingAuthority` (random single-use
  6-digit code valid for 5 minutes, five tries, 32-byte tokens), `KeychainClientStore`, `BridgeRouter`,
  `BridgeServer` (Bonjour `_hmm._tcp`, WebSocket events for paired clients only), proposals and their card.
- **HmmPerception**: contact-sheet layout and drawing, set-of-marks placement and drawing, the value view,
  safe zones, `PerceptionReport`.
- **HmmDiagnostics**: `FrameStats`, `PerformanceHUD`, `BenchmarkRecorder` / `BenchmarkReport`, `RotatingLog`,
  signposts, memory footprint, `MetricsSubscriber`.
- **HmmStore**: `PurchaseVerifier` (StoreKit 2 app transaction).
