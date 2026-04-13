import DiscordModels
import NIOHTTP1

extension DiscordClient {

  /// https://docs.discord.food/interactions/application-commands#search-application-commands
  @inlinable
  public func searchApplicationCommands(
    channelId: ChannelSnowflake,
    type: Int = 1,
    query: String? = nil,
    limit: Int? = 25,
    includeApplications: Bool = true,
    cursor: String? = nil
  ) async throws -> DiscordClientResponse<ApplicationCommandIndex> {
    let endpoint = UserAPIEndpoint.searchApplicationCommands(channelId: channelId)
    var queries: [(String, String?)] = [
      ("type", String(type)),
      ("include_applications", includeApplications ? "true" : "false"),
    ]
    if let query, !query.isEmpty {
      queries.append(("query", query))
    }
    if let limit {
      queries.append(("limit", String(limit)))
    }
    if let cursor {
      queries.append(("cursor", cursor))
    }
    return try await self.send(request: .init(to: endpoint, queries: queries))
  }

  /// https://docs.discord.food/interactions/receiving-and-responding#create-interaction
  @inlinable
  public func invokeSlashCommand(
    payload: SlashCommandInvocation
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.createInteraction
    return try await self.send(
      request: .init(
        to: endpoint,
        headers: [
          "X-Context-Properties":
            SuperProperties.GenerateContextPropertiesHeader(
              context: .createMessage
            )
        ]
      ),
      payload: payload
    )
  }
}
