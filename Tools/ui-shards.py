#!/usr/bin/env python3
"""Splits the UI tests over CI's simulator jobs and picks the ones a draft change can affect.

    ui-shards.py --shards N --shard K [--changed FILE]
    ui-shards.py --failed LOG

Prints the `-only-testing:` arguments for shard K (1-based) of N, balanced by how long each test took on CI (the
table below; a test not in it counts as two minutes). With --changed (a file listing changed paths, one a line) and a
change that touches only some areas, only those areas' tests run; anything shared (the app, the shell, the engine, the
core, the kit, the project) runs everything. The atlas runs in its own workflow and is never listed. With --failed it
prints the arguments for the tests an xcodebuild log shows failing and never passing after, for a second attempt.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "AppUITests"
DEFAULT = 120

# Seconds per test on CI (the 0.28 run on main).
TIMES = {
    "AnimateTests/testADrawnPathMovesTheCubeAndExportAsksFormatsFirst": 96,
    "BoardTests/testPlanOnTheBoardAndPinItToTheProject": 58,
    "CharacterTests/testAnEyeCreatureAndADogAreMadeRiggedAndLipSyncedInUnderThreeMinutes": 106,
    "ChromeFitTests/testTheChromeFitsInLandscapeAndPortrait": 369,
    "ChromeFitTests/testTheStageStaysTheStageWithASelectionAndTheTimeline": 28,
    "DrawTests/testALineOfAnExactLengthTypedOnTheNumberPad": 41,
    "DrawTests/testAStrokeStartsUnderTheTouchInTheAirAndOnASurface": 34,
    "DrawTests/testALineLandsUnderTheTipAtEveryAngleAndNearEveryEdge": 110,
    "DrawTests/testAThreeFrameFlipbookDrawnWithFlicks": 51,
    "GuestTests/testDevsLevelGoesToGodotInUnderThreeMinutes": 78,
    "GuestTests/testGiuliasThreadedLidGoesToTheSlicerAs3MFInUnderThreeMinutes": 74,
    "GuestTests/testSarasRoomBecomesAPlanAndAnIFCInUnderThreeMinutes": 89,
    "LayoutTests/testAllSevenShapesAreVisible": 33,
    "LayoutTests/testHomeControlsAreReachable": 25,
    "LayoutTests/testMakingControlsAreReachable": 198,
    "LayoutTests/testModelControlsAreReachable": 141,
    "LayoutTests/testMoreModelControlsAreReachable": 189,
    "LayoutTests/testPanelAndChromeControlsAreReachable": 529,
    "LayoutTests/testSelectionControlsAreReachable": 258,
    "LayoutTests/testTheHoldMenuStartsTheSameOnEveryKindOfThing": 204,
    "LayoutTests/testTheHomeBenchmarkRunsAndReports": 79,
    "LayoutTests/testTheIdleStageHoldsAtLeast85PercentOfTheScreen": 19,
    "LayoutTests/testTimelineControlsAreReachable": 46,
    "ModelingTests/testABlockWithAHoleThroughItInUnderThirtySeconds": 121,
    "ReferenceTests/testASheetLaidOnACubeFitsTheFace": 59,
    "ReferenceTests/testTheReferenceWindowMovesSizesSwitchesAndComesBack": 85,
    "RigTests/testAPersonIsRiggedAndPosedInUnderThirtySeconds": 48,
    "RigTests/testHisOwnModelBecomesTheCharacterInPlace": 70,
    "RigTests/testATailIsPinnedAndPosedInUnderTenSeconds": 48,
    "ScreenshotTests/testIPadScreenshots": 63,
    "SmokeTests/testACharacterTheTimelineAndDiagnostics": 74,
    "SmokeTests/testArabicIsRightToLeft": 21,
    "SmokeTests/testCreateBuildUndoAndReopen": 49,
    "SmokeTests/testItalianLabels": 21,
    "SmokeTests/testLookCameraDirectorViewAndExportSheet": 53,
    "SmokeTests/testNothingAppearsOnTheCanvasUnderLoad": 54,
    "SmokeTests/testTheFeelRecorder": 71,
    "SmokeTests/testTourRunsToTheEnd": 43,
    "YoursTests/testAMirroredReorderedLayoutSurvivesARelaunchAndResets": 127,
    "YoursTests/testPresentHidesEverythingAndANoteIsAnsweredInPlace": 75,
}

# A feature folder (Packages/LoweyFeatures/Sources/LoweyFeatures/<folder>) and the test classes that cover it. A
# folder not here is shared: a draft change to it runs everything.
AREAS = {
    "Animate": ["AnimateTests"],
    "Timeline": ["AnimateTests"],
    "Board": ["BoardTests"],
    "Draw": ["DrawTests"],
    "Rig": ["RigTests", "CharacterTests"],
    "Face": ["CharacterTests"],
    "Model": ["ModelingTests", "GuestTests"],
    "Present": ["YoursTests"],
    "Review": ["YoursTests"],
    "Library": ["CharacterTests"],
    "Learn": ["SmokeTests"],
    "Diagnostics": ["SmokeTests"],
    "Export": ["AnimateTests", "GuestTests"],
}
# Always run on a draft, whatever changed: the app opens, builds, undoes and reopens.
ALWAYS = ["SmokeTests/testCreateBuildUndoAndReopen"]


def all_tests():
    tests = []
    for path in sorted(TESTS.glob("*.swift")):
        cls = None
        for line in path.read_text(encoding="utf-8").splitlines():
            match = re.match(r"\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", line)
            if match:
                cls = match.group(1)
            match = re.match(r"\s*func\s+(test\w+)\s*\(", line)
            if match and cls and cls != "AtlasTests":
                tests.append(f"{cls}/{match.group(1)}")
    return tests


def affected(tests, changed):
    """The tests a set of changed paths can affect, or None for all of them."""
    classes = set()
    prefix = "Packages/LoweyFeatures/Sources/LoweyFeatures/"
    for path in changed:
        if path.endswith(".md") or path.startswith("docs/"):
            continue
        if path.startswith("AppUITests/"):
            classes.add(pathlib.Path(path).stem)
        elif path.startswith(prefix) and path[len(prefix):].split("/")[0] in AREAS:
            classes.update(AREAS[path[len(prefix):].split("/")[0]])
        elif path.startswith(("Packages/LoweyFeatures/Tests/", "Tools/", "schemas/", "skills/")):
            continue
        else:
            return None
    picked = [test for test in tests if test.split("/")[0] in classes]
    return picked + [test for test in ALWAYS if test in tests and test not in picked]


def shards(tests, count):
    """Longest first onto the lightest shard."""
    bins = [[] for _ in range(count)]
    loads = [0] * count
    for test in sorted(tests, key=lambda t: -TIMES.get(t, DEFAULT)):
        lightest = loads.index(min(loads))
        bins[lightest].append(test)
        loads[lightest] += TIMES.get(test, DEFAULT)
    return bins, loads


def failed(log):
    """The tests whose last result in an xcodebuild log is a failure (nothing when none is found: rerun them all)."""
    last = {}
    listed = []
    for line in pathlib.Path(log).read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.search(r"Test Case '-\[LoweyUITests\.(\w+) (\w+)\]' (passed|failed|exceeded)", line)
        if match:
            last[f"{match.group(1)}/{match.group(2)}"] = match.group(3)
        # xcodebuild's own list at the end ("Failing tests:"), which also names a test that hung.
        match = re.match(r"\s+(\w+)\.(test\w+)\(\)\s*$", line)
        if match:
            listed.append(f"{match.group(1)}/{match.group(2)}")
    tests = [test for test, result in last.items() if result != "passed"]
    return tests + [test for test in listed if test not in tests]


def main():
    if "--failed" in sys.argv:
        tests = failed(sys.argv[sys.argv.index("--failed") + 1])
        print(" ".join(f"-only-testing:LoweyUITests/{test}" for test in tests))
        return
    count = int(sys.argv[sys.argv.index("--shards") + 1])
    index = int(sys.argv[sys.argv.index("--shard") + 1]) - 1
    tests = all_tests()
    if "--changed" in sys.argv:
        changed = pathlib.Path(sys.argv[sys.argv.index("--changed") + 1]).read_text().split()
        tests = affected(tests, changed) or tests
    bins, loads = shards(tests, count)
    for number, (picked, load) in enumerate(zip(bins, loads), start=1):
        print(f"shard {number}: {len(picked)} tests, ~{load // 60} min", file=sys.stderr)
    print(" ".join(f"-only-testing:LoweyUITests/{test}" for test in bins[index]))


if __name__ == "__main__":
    main()
