//
//  LogbookSaveResult.swift
//  AmakaFlow
//
//  AMA-2426 — outcome of a logbook save. Split out of LogbookViewModel.swift,
//  which is at the SwiftLint file_length limit; the tracked-field control
//  (AMA-2462) has to live in the class itself because it mutates
//  `private(set) var draft` and calls the private `touch()`.
//

import Foundation

enum LogbookSaveResult: Equatable {
    /// Phone / after / live — verified actuals written.
    case verified(ActualsFillInSession)
    /// Companion notepad saved; draft stays pending until reconcile / timeout.
    case companionPendingPersisted
}
