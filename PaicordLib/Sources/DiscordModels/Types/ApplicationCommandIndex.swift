import Foundation

/// https://docs.discord.food/interactions/application-commands#search-application-commands
public struct ApplicationCommandIndex: Sendable, Codable {

  public struct PartialApplication: Sendable, Codable {
    public var id: ApplicationSnowflake
    public var name: String
    public var icon: String?
    public var description: String?
    public var bot_id: UserSnowflake?
    public var type: Int?
  }

  public struct Cursor: Sendable, Codable {
    public var next: String?
    public var previous: String?
    public var repaired: Bool?
  }

  public var application_commands: [ApplicationCommand]
  public var applications: [PartialApplication]?
  public var cursor: Cursor?
}

/// Hand-rolled payload for `POST /interactions` when invoking a slash command
/// as a user client. Separate from `Payloads.CreateInteraction` so we can
/// shape the `data` field the way the user API expects (including the
/// echoed `application_command` field).
public struct SlashCommandInvocation: Sendable, Encodable, ValidatablePayload {

  public struct DataOption: Sendable, Encodable {
    public var type: Int
    public var name: String
    public var value: StringIntDoubleBool?
    public var options: [DataOption]?

    public init(
      type: Int,
      name: String,
      value: StringIntDoubleBool? = nil,
      options: [DataOption]? = nil
    ) {
      self.type = type
      self.name = name
      self.value = value
      self.options = options
    }
  }

  public struct Data: Sendable, Encodable {
    public var version: String
    public var id: CommandSnowflake
    public var name: String
    public var type: Int
    public var options: [DataOption]?
    public var attachments: [String]?
    public var application_command: ApplicationCommand

    public init(
      version: String,
      id: CommandSnowflake,
      name: String,
      type: Int,
      options: [DataOption]? = nil,
      attachments: [String]? = nil,
      application_command: ApplicationCommand
    ) {
      self.version = version
      self.id = id
      self.name = name
      self.type = type
      self.options = options
      self.attachments = attachments
      self.application_command = application_command
    }
  }

  public var type: Int
  public var application_id: ApplicationSnowflake
  public var guild_id: GuildSnowflake?
  public var channel_id: ChannelSnowflake
  public var session_id: String
  public var data: Data
  public var nonce: String
  public var analytics_location: String?

  public init(
    application_id: ApplicationSnowflake,
    guild_id: GuildSnowflake?,
    channel_id: ChannelSnowflake,
    session_id: String,
    data: Data,
    nonce: String,
    analytics_location: String? = "slash_command"
  ) {
    self.type = 2
    self.application_id = application_id
    self.guild_id = guild_id
    self.channel_id = channel_id
    self.session_id = session_id
    self.data = data
    self.nonce = nonce
    self.analytics_location = analytics_location
  }

  public func validate() -> [ValidationFailure] {}
}
