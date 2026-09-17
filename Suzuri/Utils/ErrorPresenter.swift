import Foundation

/// 将网络、编码和图床错误转换为可直接展示的文案。
struct ErrorPresenter {
    let title: String
    let message: String
    let canRetry: Bool

    init(error: Error) {
        self.title = Self.title(for: error)
        self.message = Self.message(for: error)
        self.canRetry = Self.isRetryable(error)
    }

    static func title(for error: Error) -> String {
        if error is HostError || error is ImageCompressorError || error is ImagePipelineError || error is PhotoPickerError {
            return "图片处理失败"
        }
        if let error = error as? TelegraphError {
            switch error {
            case .contentTooLarge:
                return "内容过大"
            case .missingToken:
                return "账号不可用"
            default:
                break
            }
        }
        return "操作失败"
    }

    static func message(for error: Error) -> String {
        switch error {
        case let error as TelegraphError:
            return telegraphMessage(error)
        case let error as HostError:
            switch error {
            case .uploadFailed(let detail):
                return "图片上传失败：\(detail)"
            case .badResponse:
                return "图片上传失败：服务器响应无法解析。"
            case .transport:
                return "图片上传失败：网络连接失败，请检查网络后重试。"
            }
        case is ImageCompressorError:
            return "无法读取或压缩这张图片。"
        case is PhotoPickerError:
            return "没有读取到图片数据，请重新选择图片。"
        case is ImagePipelineError:
            return "图片缓存不可用，请稍后重试。"
        default:
            let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "操作失败，请稍后重试。" : detail
        }
    }

    static func describe(_ error: Error) -> String {
        message(for: error)
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let error = error as? TelegraphError {
            switch error {
            case .contentTooLarge, .missingToken, .api:
                return false
            case .invalidResponse:
                return true
            case .network(let detail):
                return !isClientHTTPError(detail)
            }
        }
        if error is ImageCompressorError || error is PhotoPickerError {
            return false
        }
        if error is HostError || error is ImagePipelineError {
            return true
        }
        return true
    }

    private static func isClientHTTPError(_ detail: String) -> Bool {
        guard detail.hasPrefix("HTTP "),
              let codeToken = detail.dropFirst(5).split(separator: " ").first,
              let code = Int(String(codeToken))
        else { return false }
        if code == 429 {
            return false
        }
        return (400..<500).contains(code)
    }

    private static func telegraphMessage(_ error: TelegraphError) -> String {
        switch error {
        case .api(let detail):
            "服务器返回错误：\(detail)"
        case .invalidResponse:
            "服务器响应无法解析，请稍后重试。"
        case .network(let detail):
            "网络连接失败：\(detail)"
        case .contentTooLarge(let bytes):
            "内容过大（\(bytes) bytes，限制为 64KB）。"
        case .missingToken:
            "缺少账号 token，请重试账号注册。"
        }
    }
}
