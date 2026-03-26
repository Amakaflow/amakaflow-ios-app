//
//  XPData.swift
//  AmakaFlow
//
//  Model for XP + Level data from the gamification API.
//  AMA-1285
//

import Foundation

struct XPData: Codable {
    let xpTotal: Int
    let currentLevel: Int
    let levelName: String
    let xpToNextLevel: Int
    let xpToday: Int
    let dailyCap: Int
}
