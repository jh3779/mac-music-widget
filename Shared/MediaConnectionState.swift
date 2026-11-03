import Foundation

/// Describes observed evidence, never guesses whether website permission was denied.
enum MediaConnectionState: String, Codable {
    case ready, waitingForMedia, reconnectPage, extensionNotConnected, updatesDelayed
    case configurationRequired, hostUnavailable

    var message: String {
        switch self {
        case .ready: return "재생 정보 수신 중"
        case .waitingForMedia: return "Safari에서 선택한 소스의 미디어를 재생해 주세요"
        case .reconnectPage: return "Safari 재생 탭을 새로고침해 주세요"
        case .extensionNotConnected: return "Safari 확장 연결과 사이트 접근 허용을 확인해 주세요"
        case .updatesDelayed: return "최근 재생 정보를 받지 못했습니다. Safari 탭을 확인해 주세요"
        case .configurationRequired: return "앱과 Safari 확장의 App Group·서명 설정을 확인해 주세요"
        case .hostUnavailable: return "앱에 연결할 수 없습니다. 앱을 열고 다시 시도해 주세요"
        }
    }
}
