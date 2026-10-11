import HmmDesign
import LoweyCore
import SwiftUI

/// Preferences: appearance, feel, the stage, storage.
struct PreferencesForm: View {
    let app: AppModel
    @AppStorage(HmmThemeMode.storageKey) private var themeMode = HmmThemeMode.dark.rawValue
    @AppStorage(HmmHaptics.storageKey) private var haptics = true
    @AppStorage(AppSettings.sidebarOnRight) private var sidebarOnRight = false
    @AppStorage(AppSettings.alwaysShowsSidebar) private var alwaysShowsSidebar = false
    @AppStorage(AppSettings.pencilHoverPreview) private var pencilHover = false
    @AppStorage(HmmPencilOrHand.fingersAlwaysMakeKey) private var fingersMake = false
    @AppStorage(AppSettings.fullResolutionStage) private var fullResolution = false
    @AppStorage(AppSettings.inspectorDocked) private var inspectorDocked = false
    @AppStorage(AppSettings.navigationSpeed) private var navigationSpeed = 1.0
    @AppStorage(AppSettings.showsJoystick) private var showsJoystick = true
    @AppStorage(AppSettings.joystickSpeed) private var joystickSpeed = 1.0
    @AppStorage(AppSettings.storeInICloud) private var iCloud = true
    @AppStorage(AppSettings.boardEnabled) private var boardEnabled = true

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeMode) {
                ForEach(HmmThemeMode.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
            }
            Toggle("Sidebar on the right (left-handed)", isOn: $sidebarOnRight)
            Toggle("Haptics", isOn: $haptics)
        }
        Section {
            Toggle("Draw with a finger too", isOn: $fingersMake)
                .accessibilityIdentifier("settings-fingers-make")
        } header: {
            Text("Pencil or hand")
        } footer: {
            Text("One finger draws until an Apple Pencil touches the screen. Then the Pencil draws and fingers move the view, unless this is on.")
        }
        Section("Stage") {
            Toggle("Always show the sidebar", isOn: $alwaysShowsSidebar)
                .accessibilityIdentifier("settings-always-sidebar")
            Toggle("Pencil hover preview", isOn: $pencilHover)
            Toggle("Always full resolution", isOn: $fullResolution)
            LabeledSlider(title: "Moving around (orbit, pan, zoom)", value: navigationSpeed, range: AppSettings.navigationSpeedRange,
                          format: { String(format: "%.2g×", $0) }) { navigationSpeed = $0 }
            Toggle("Dock the inspector at the side", isOn: $inspectorDocked)
                .accessibilityIdentifier("settings-inspector-docked")
            Toggle("Joystick under a selection", isOn: $showsJoystick)
                .accessibilityIdentifier("settings-joystick")
            if showsJoystick {
                LabeledSlider(title: "Joystick speed", value: joystickSpeed, range: AppSettings.joystickSpeedRange,
                              format: { String(format: "%.2g×", $0) }) { joystickSpeed = $0 }
            }
        }
        Section {
            Toggle("Schizzo board", isOn: $boardEnabled)
                .accessibilityIdentifier("settings-board")
        } header: {
            Text("Board")
        } footer: {
            Text("A sheet for planning in every project. Off: it leaves Actions and pinned pictures are put away. Nothing is deleted.")
        }
        Section {
            Toggle("Keep projects in iCloud Drive", isOn: Binding(get: { iCloud }, set: { value in
                iCloud = value
                Task { await app.setStoresInICloud(value) }
            }))
        } header: {
            Text("Storage")
        } footer: {
            Text(app.storage.isICloud ? "Your projects sync between your devices and show in Files."
                : "Projects are on this iPad (in Files ▸ On My iPad). iCloud Drive needs the App Store version and an iCloud account.")
        }
    }
}

/// About, licences and acknowledgements.
struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: AppIdentity.version)
            LabeledContent("Made by", value: "studio h.")
            NavigationLink("Licences") { AcknowledgementsView() }
            Text("No account, no tracking: nothing leaves this iPad unless you share it.").font(.hmm(.footnote))
        }
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                Text("CMU Pronouncing Dictionary").font(.hmm(.headline, weight: .semibold))
                Text("Used for lip sync. Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. "
                    + "Redistribution and use in source and binary forms, with or without modification, are permitted provided that the copyright notice, "
                    + "this list of conditions and the following disclaimer are kept. THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY \"AS IS\" "
                    + "AND ANY EXPRESSED OR IMPLIED WARRANTIES ARE DISCLAIMED.")
                    .font(.hmm(.footnote))
                Text("Manifold").font(.hmm(.headline, weight: .semibold))
                Text("Booleans on solids (union, subtract, intersect). Copyright The Manifold Authors. Apache License 2.0.")
                    .font(.hmm(.footnote))
                Text("xatlas").font(.hmm(.headline, weight: .semibold))
                Text("Lays models flat so they can be painted. Copyright (c) 2018-2020 Jonathan Young; thekla_atlas copyright (c) 2013 Thekla, Inc "
                    + "and NVIDIA Corporation. MIT License: permission is granted, free of charge, to use, copy, modify and distribute it, provided "
                    + "the copyright and permission notices are kept. It is provided \"as is\", without warranty of any kind.")
                    .font(.hmm(.footnote))
                Text("The Kit").font(.hmm(.headline, weight: .semibold))
                Text("The models in the Library's Sets come from Kenney (kenney.nl: Furniture, Food, Nature, City, Car, Space, Survival and "
                    + "Mini Market kits) and Quaternius (quaternius.com: Sci-Fi Essentials, Universal Base Characters, Universal Animation "
                    + "Library). They are released under CC0 1.0 (public domain); we credit them because they deserve it.")
                    .font(.hmm(.footnote))
                Text("Everything else in \(AppIdentity.displayName) (the renderer, the glTF reader, the characters) is our own code.")
                    .font(.hmm(.footnote))
            }
            .padding(HmmSpacing.l)
        }
        .navigationTitle("Licences")
    }
}
