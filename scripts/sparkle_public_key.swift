// Prints the Sparkle public key (SUPublicEDKey) for a private key read
// from standard input — to recover the public key, or to check that a
// backup of the private key is the right one, without the keychain.
//
//   swift scripts/sparkle_public_key.swift < sparkle_private_key
//   pbpaste | swift scripts/sparkle_public_key.swift
//
// Accepts what `generate_keys -x` exports: base64 of the 32-byte Ed25519
// seed, or of the older 96-byte private+public format.

import CryptoKit
import Foundation

let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
guard let secret = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    FileHandle.standardError.write(Data("error: input is not base64\n".utf8))
    exit(1)
}

switch secret.count {
case 32:
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case 96:
    print(secret.suffix(32).base64EncodedString())
default:
    FileHandle.standardError.write(Data("error: expected a 32- or 96-byte key, got \(secret.count) bytes\n".utf8))
    exit(1)
}
