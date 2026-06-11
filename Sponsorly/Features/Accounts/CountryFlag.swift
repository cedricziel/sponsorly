import Foundation

/// Maps an ISO 3166-1 alpha-2 country code to its flag emoji.
enum CountryFlag {
    static func emoji(_ countryCode: String?) -> String? {
        guard var code = countryCode?.uppercased(), code.count == 2 else { return nil }
        if code == "UK" { code = "GB" } // Amazon uses "UK"; the flag is "GB".

        let base: UInt32 = 127_397 // 0x1F1E6 ("🇦") - "A"
        var emoji = ""
        for scalar in code.unicodeScalars {
            guard (65 ... 90).contains(scalar.value),
                  let flagScalar = UnicodeScalar(base + scalar.value)
            else {
                return nil
            }
            emoji.unicodeScalars.append(flagScalar)
        }
        return emoji
    }
}
