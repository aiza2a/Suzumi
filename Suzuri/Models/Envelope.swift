import Foundation

/// Telegraph API 通用响应信封。
///
/// 所有 Telegraph 接口返回统一的 `{ "ok": Bool, "result": T?, "error": String? }`
/// 结构。`ok == false` 时 `result` 为 nil，`error` 携带服务器错误描述。
struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let error: String?
    // CodingKeys 与字段名原样对应（ok/result/error），无需自定义。
}