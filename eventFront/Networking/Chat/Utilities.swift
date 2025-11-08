//
//  UserSession.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 15/9/25.
//


import Foundation
import SwiftUI

extension Optional where Wrapped == String { var nilOrEmpty: Bool { self?.isEmpty ?? true } }
extension String { func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) } }
