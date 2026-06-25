//
//  EngineError.swift
//  pixi
//
//  Shared error type for AI engine transports.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

enum EngineError: Error {
    case missingKey(String)
    case badStatus(String)
    case badResponse(String)
}
