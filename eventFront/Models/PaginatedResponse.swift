// PaginatedResponse.swift

import Foundation

struct PaginatedResponse<T: Decodable>: Decodable {
    let content: [T]
    let currentPage: Int
    let pageSize: Int
    let totalItems: Int
    let totalPages: Int
    let last: Bool
}
