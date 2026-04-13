//
//  Design Constants.swift
//  Paicord
//
// Created by Lakhan Lothiyi on 06/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

extension Shape where Self == RoundedRectangle {
  /// Standard 10 point continuous rounding
  public static var rounded: Self {
    .rect(cornerSize: .init(10), style: .continuous)
  }
}
extension RoundedRectangle {
  public init() {
    self = .init(cornerSize: .init(10), style: .continuous)
  }
}

public enum Spacing {
  public static let tiny: CGFloat = 2
  public static let compact: CGFloat = 4
  public static let small: CGFloat = 6
  public static let standard: CGFloat = 8
  public static let medium: CGFloat = 12
  public static let large: CGFloat = 16
  public static let xLarge: CGFloat = 20
  public static let xxLarge: CGFloat = 24
}

public enum Radius {
  public static let small: CGFloat = 8
  public static let standard: CGFloat = 10
  public static let medium: CGFloat = 12
  public static let large: CGFloat = 16
}

public enum Sidebar {
  public static let guildColumnWidth: CGFloat = 65
  public static let guildScrollerInset: CGFloat = 10
  public static let headerHeight: CGFloat = 65
}

public enum InputField {
  public static let cornerRadius: CGFloat = 18
  public static let verticalPadding: CGFloat = 7
  public static let horizontalPadding: CGFloat = 12
  public static let trailingActionInset: CGFloat = 6
}

public enum MarkAllRead {
  public static let fontSize: CGFloat = 9
  public static let horizontalPadding: CGFloat = Spacing.standard
  public static let verticalPadding: CGFloat = Spacing.compact
  public static let outerVerticalPadding: CGFloat = Spacing.compact
  public static let activeForeground: Color = .primary
  public static let inactiveForeground: Color = Color.secondary.opacity(0.5)
}
