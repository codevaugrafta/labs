import Foundation

enum PDFBookPreparationStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case preparing
    case ready
    case failed

    var label: String {
        switch self {
        case .idle: "Book View not prepared"
        case .preparing: "Preparing Book View"
        case .ready: "Book View ready"
        case .failed: "Book View unavailable"
        }
    }
}

enum PDFReadingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case originalPDF
    case bookView

    var id: String { rawValue }

    var label: String {
        switch self {
        case .originalPDF: "Original PDF"
        case .bookView: "Book View"
        }
    }
}

enum PDFPageLayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case singlePage
    case continuous
    case twoUp
    case twoUpContinuous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePage: "Single Page"
        case .continuous: "Continuous"
        case .twoUp: "Two-Up"
        case .twoUpContinuous: "Two-Up Continuous"
        }
    }
}

enum PDFScrollAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }
}

enum PDFPageFitPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case fitPage
    case fitWidth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fitPage: "Fit Page"
        case .fitWidth: "Fit Width"
        }
    }
}
