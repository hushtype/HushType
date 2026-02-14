//
//  HushTypeApp.swift
//  HushType
//
//  Created by Harun Güngörer on 13.02.2026.
//

import SwiftUI

@main
struct HushTypeApp: App {
    var body: some Scene {
        MenuBarExtra("HushType", systemImage: "mic.fill") {
            Text("HushType Menu Bar App")
        }
        .menuBarExtraStyle(.window)
    }
}
