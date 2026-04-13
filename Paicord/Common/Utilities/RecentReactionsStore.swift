//
//  RecentReactionsStore.swift
//  Paicord
//

import SwiftUI

@MainActor
@Observable
final class RecentReactionsStore {
  static let shared = RecentReactionsStore()

  private let storageKey = "recentReactionEmojis"
  private let limit = 6

  private(set) var recent: [String] = []

  private init() {
    if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
      recent = saved
    }
  }

  func record(_ emoji: String) {
    var updated = recent.filter { $0 != emoji }
    updated.insert(emoji, at: 0)
    if updated.count > limit {
      updated = Array(updated.prefix(limit))
    }
    recent = updated
    UserDefaults.standard.set(updated, forKey: storageKey)
  }
}
