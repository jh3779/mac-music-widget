import Foundation

/// One capability-filtered source list drives saved selections, menus and cycling.
struct MediaSourceList<Source: Equatable> {
    let available: [Source]
    private let fallback: Source

    init(all: [Source], fallback: Source, safari: Source, supportsSafari: Bool) {
        available = all.filter { supportsSafari || $0 != safari }
        precondition(available.contains(fallback))
        self.fallback = fallback
    }

    func normalized(_ candidate: Source?) -> Source {
        guard let candidate, available.contains(candidate) else { return fallback }
        return candidate
    }

    func next(after current: Source) -> Source {
        let index = available.firstIndex(of: normalized(current)) ?? 0
        return available[(index + 1) % available.count]
    }
}
