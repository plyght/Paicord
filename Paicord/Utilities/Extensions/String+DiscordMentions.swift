import Foundation
import PaicordLib

extension String {
  func resolvingDiscordMentions(
    users: [UserSnowflake: PartialUser],
    guildStore: GuildStore?
  ) -> String {
    guard self.contains("<") else { return self }
    var out = self

    let userPattern = #"<@!?(\d+)>"#
    if let regex = try? NSRegularExpression(pattern: userPattern) {
      let ns = out as NSString
      let matches = regex.matches(
        in: out,
        range: NSRange(location: 0, length: ns.length)
      ).reversed()
      for m in matches {
        guard m.numberOfRanges >= 2 else { continue }
        let idRange = m.range(at: 1)
        let id = ns.substring(with: idRange)
        let userId = UserSnowflake(id)
        let nick = guildStore?.members[userId]?.nick
        let user = users[userId]
        let name =
          nick ?? user?.global_name ?? user?.username ?? id
        out = (out as NSString).replacingCharacters(
          in: m.range,
          with: "@\(name)"
        )
      }
    }

    let rolePattern = #"<@&(\d+)>"#
    if let regex = try? NSRegularExpression(pattern: rolePattern) {
      let ns = out as NSString
      let matches = regex.matches(
        in: out,
        range: NSRange(location: 0, length: ns.length)
      ).reversed()
      for m in matches {
        guard m.numberOfRanges >= 2 else { continue }
        let idRange = m.range(at: 1)
        let id = ns.substring(with: idRange)
        let name =
          guildStore?.roles[RoleSnowflake(id)]?.name ?? "role"
        out = (out as NSString).replacingCharacters(
          in: m.range,
          with: "@\(name)"
        )
      }
    }

    let channelPattern = #"<#(\d+)>"#
    if let regex = try? NSRegularExpression(pattern: channelPattern) {
      let ns = out as NSString
      let matches = regex.matches(
        in: out,
        range: NSRange(location: 0, length: ns.length)
      ).reversed()
      for m in matches {
        guard m.numberOfRanges >= 2 else { continue }
        let idRange = m.range(at: 1)
        let id = ns.substring(with: idRange)
        let resolved = guildStore?.channels[ChannelSnowflake(id)]?.name
        let name = (resolved ?? nil) ?? "channel"
        out = (out as NSString).replacingCharacters(
          in: m.range,
          with: "#\(name)"
        )
      }
    }

    return out
  }
}
