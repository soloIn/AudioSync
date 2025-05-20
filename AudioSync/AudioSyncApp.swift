//
//  AudioSyncApp.swift
//  AudioSync
//
//  Created by solo on 4/29/25.
//

import AppKit
import CoreAudio
import Foundation
import SwiftUI

@main
struct AudioSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
