//
//  Target.swift
//  pixi
//
//  A located UI element from vision grounding. Coords normalized 0..1 from
//  the image top-left. Shared by the vision engine, overlay, and the
//  vision-click fallback tool.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

/// A located UI element. Coords normalized 0..1 from the image top-left.
struct Target: Codable {
    let label: String?
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let reason: String?
}

/// Extracts targets from model text. Handles raw JSON, ```json fences, and
/// JSON wrapped in prose by regex-extracting the first object with a
/// `targets` array.
enum TargetParser {
    static func parse(_ text: String) -> [Target] {
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["targets"] as? [[String: Any]] {
            return decode(arr)
        }
        // Fenced or wrapped: extract the first {...targets...} blob.
        if let blob = firstJSONBlob(text),
           let data = blob.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["targets"] as? [[String: Any]] {
            return decode(arr)
        }
        return []
    }

    private static func decode(_ arr: [[String: Any]]) -> [Target] {
        let data = (try? JSONSerialization.data(withJSONObject: arr)) ?? Data()
        return (try? JSONDecoder().decode([Target].self, from: data)) ?? []
    }

    private static func firstJSONBlob(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }
}
