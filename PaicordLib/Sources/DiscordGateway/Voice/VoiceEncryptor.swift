import Crypto
import Foundation

/// Handles AES-256-GCM encryption for Discord voice RTP packets.
/// Supports `aead_aes256_gcm_rtpsize` mode.
public struct VoiceEncryptor: Sendable {

  private let key: SymmetricKey

  public init(secretKey: [UInt8]) {
    self.key = SymmetricKey(data: secretKey)
  }

  /// Encrypts an audio payload for transmission over RTP.
  ///
  /// For `aead_aes256_gcm_rtpsize`:
  /// - Nonce: 12 bytes. Last 4 bytes are big-endian incrementing counter, rest are 0.
  /// - AAD: The 12-byte RTP header.
  /// - The encrypted payload is: ciphertext + 16-byte GCM tag + 4-byte nonce suffix.
  public func encrypt(
    header: Data,
    audio: Data,
    nonce: UInt16,
    ssrc: UInt32
  ) throws -> Data {
    var nonceBytes = Data(repeating: 0, count: 12)
    // Use incrementing nonce in last 4 bytes (big-endian)
    let nonceValue = UInt32(nonce)
    nonceBytes[8] = UInt8((nonceValue >> 24) & 0xFF)
    nonceBytes[9] = UInt8((nonceValue >> 16) & 0xFF)
    nonceBytes[10] = UInt8((nonceValue >> 8) & 0xFF)
    nonceBytes[11] = UInt8(nonceValue & 0xFF)

    let aesNonce = try AES.GCM.Nonce(data: nonceBytes)
    let sealed = try AES.GCM.seal(
      audio,
      using: key,
      nonce: aesNonce,
      authenticating: header
    )

    var result = Data()
    result.append(sealed.ciphertext)
    result.append(contentsOf: sealed.tag)
    // Append the 4-byte nonce suffix so the receiver can reconstruct the full nonce
    result.append(nonceBytes[8..<12])
    return result
  }

  /// Decrypts an incoming RTP audio payload.
  public func decrypt(
    header: Data,
    encryptedPayload: Data
  ) throws -> Data {
    guard encryptedPayload.count > 20 else {
      throw VoiceUDPError.encryptionFailed
    }

    let tagAndNonceSize = 16 + 4
    let ciphertextEnd = encryptedPayload.count - tagAndNonceSize
    guard ciphertextEnd > 0 else {
      throw VoiceUDPError.encryptionFailed
    }

    let ciphertext = encryptedPayload[..<encryptedPayload.index(encryptedPayload.startIndex, offsetBy: ciphertextEnd)]
    let tag = encryptedPayload[
      encryptedPayload.index(encryptedPayload.startIndex, offsetBy: ciphertextEnd)
        ..<
        encryptedPayload.index(encryptedPayload.startIndex, offsetBy: ciphertextEnd + 16)
    ]
    let nonceSuffix = encryptedPayload[
      encryptedPayload.index(encryptedPayload.startIndex, offsetBy: ciphertextEnd + 16)...
    ]

    var nonceBytes = Data(repeating: 0, count: 12)
    nonceBytes.replaceSubrange(8..<12, with: nonceSuffix)

    let aesNonce = try AES.GCM.Nonce(data: nonceBytes)
    let sealedBox = try AES.GCM.SealedBox(
      nonce: aesNonce,
      ciphertext: ciphertext,
      tag: tag
    )

    return try AES.GCM.open(sealedBox, using: key, authenticating: header)
  }
}
