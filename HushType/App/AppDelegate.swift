//
//  AppDelegate.swift
//  HushType
//
//  Created by Claude on 14.02.2026.
//

import AppKit
import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
        Logger.general.info("HushType launched - dock icon hidden, menu bar active")
    }
}
