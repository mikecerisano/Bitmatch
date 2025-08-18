//
//  BitMatchApp.swift
//  BitMatch
//
//  Created by Mike Cerisano on 8/17/25.
//

import SwiftUI

@main
struct BitMatchApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
