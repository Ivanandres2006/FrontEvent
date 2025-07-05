//
//  POSTC.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 26/6/25.
//

import Foundation

class PostCreationViewModel: ObservableObject {
    @Published var tickets: [TicketDTO] = []
}
