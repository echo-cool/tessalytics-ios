import Foundation

enum SecretRedactor {
    static func redact(_ input: String) -> String {
        var output = input
        let patterns = [
            #"(?i)authorization\s*:\s*[^\r\n]+"#,
            #"(?i)(authorization|password|token)(\s*[:=]\s*)([^\s&,]+)"#,
            #"\b[A-HJ-NPR-Z0-9]{17}\b"#,
            #"-?\d{1,3}\.\d{4,},\s*-?\d{1,3}\.\d{4,}"#
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return output
    }
}
