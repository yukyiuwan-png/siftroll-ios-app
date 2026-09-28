//
//  PhotoAlbum.swift
//  SiftRoll
//
//  Automatic "albums" derived from each photo's creation date. Nothing is written
//  to the photo library – these are purely in-app groupings by year and month.
//

import Foundation
import Photos

/// Year + month of a photo's `creationDate`. Photos without a date have no key
/// and only show up in the "All Photos" album.
struct DateKey: Hashable, Comparable {
    let year: Int
    let month: Int

    static func < (lhs: DateKey, rhs: DateKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// First day of the month, used for locale-aware titles ("August 2025" / "2025年8月").
    var referenceDate: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
}

/// What the deck is currently filtered to.
enum AlbumSelection: Hashable, Codable {
    case all
    case year(Int)
    case month(year: Int, month: Int)

    func contains(_ key: DateKey?) -> Bool {
        switch self {
        case .all:
            return true
        case .year(let year):
            return key?.year == year
        case .month(let year, let month):
            return key?.year == year && key?.month == month
        }
    }

    /// Display title in the given locale. `nil` for `.all`, whose title is localized separately.
    func title(locale: Locale) -> String? {
        switch self {
        case .all:
            return nil
        case .year(let year):
            return DateKey(year: year, month: 1).referenceDate
                .formatted(Date.FormatStyle(locale: locale).year())
        case .month(let year, let month):
            return DateKey(year: year, month: month).referenceDate
                .formatted(Date.FormatStyle(locale: locale).year().month(.wide))
        }
    }
}

struct MonthAlbum: Identifiable, Equatable {
    let key: DateKey
    var count: Int
    /// Newest photo in the month, used as the thumbnail.
    var cover: PHAsset?

    var id: DateKey { key }
    var selection: AlbumSelection { .month(year: key.year, month: key.month) }
}

struct YearAlbum: Identifiable, Equatable {
    let year: Int
    /// Newest month first.
    var months: [MonthAlbum]

    var id: Int { year }
    var count: Int { months.reduce(0) { $0 + $1.count } }
    var cover: PHAsset? { months.first?.cover }
    var selection: AlbumSelection { .year(year) }
}
