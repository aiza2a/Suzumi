import Foundation

/// Telegraph API 通用响应信封。
///
/// 所有 Telegraph 接口返回统一的 `{ "ok": Bool, "result": T?, "error": String? }`
/// 结构。`ok == false` 时 `result` 被忽略，`error` 携带服务器错误描述。
struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let error: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        // A failed response must never expose a misleading success payload.
        if ok {
            result = try container.decodeIfPresent(T.self, forKey: .result)
        } else {
            result = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case result
        case error
    }
}
