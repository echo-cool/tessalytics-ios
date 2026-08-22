import Foundation

/// Strips the things that must not leave the device from text that is about to.
///
/// Used on the diagnostics export, which is the one artefact this app produces
/// that a person might paste into an issue or send to someone else. Everything
/// here is about that moment: in the app, on the owner's own phone, the same data
/// is shown in full, because a log with the coordinates taken out cannot answer
/// the question a location log exists to answer.
enum SecretRedactor {
    private static let patterns = [
        // A whole Authorization header line, before the narrower rule below has a
        // chance to stop at the first space in "Bearer <token>".
        #"(?i)authorization\s*:\s*[^\r\n]+"#,
        #"(?i)(authorization|password|token)(\s*[:=]\s*)([^\s&,]+)"#,
        // A VIN.
        #"\b[A-HJ-NPR-Z0-9]{17}\b"#,
        // A coordinate pair written inline, as a log line or a URL parameter.
        #"-?\d{1,3}\.\d{4,},\s*-?\d{1,3}\.\d{4,}"#
    ]

    /// Coordinates carried as named fields, which is how every recorded event
    /// body holds them.
    ///
    /// The inline-pair rule above misses these entirely: a pretty-printed `/state`
    /// body puts `"latitude" : 37.40621` and its longitude on separate lines, with
    /// a brace and a key between them. The export promised the coordinates were
    /// gone and shipped the owner's doorstep in full.
    ///
    /// The key is kept and only the value replaced, so the shape of the document
    /// still reads — "this reading had a position, and it is not in this file".
    private static let coordinateField =
        #"(?i)("?\b(latitude|longitude|lat|lon|lng)\b"?\s*[:=]\s*)-?\d+(\.\d+)?"#

    static func redact(_ input: String) -> String {
        var output = input
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return output.replacingOccurrences(
            of: coordinateField,
            with: "$1[REDACTED]",
            options: .regularExpression
        )
    }
}
