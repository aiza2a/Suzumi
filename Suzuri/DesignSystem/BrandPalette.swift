import SwiftUI

/// Suzuri 品牌色板（v3 设计文档固化，勿改数值）。
///
/// H≈359.5° 同色相 11 档红系。主色 `brand600` 仅用于交互焦点；
/// 大面积底色用亮端 `brand50/100` / 暗端 `brand900/950`；
/// 玻璃描边一律用 `white(0.18~0.22)`，不用灰线。
extension Color {
    static let brand50  = Color(red: 0.984, green: 0.941, blue: 0.941) // #FBF0F0
    static let brand100 = Color(red: 0.965, green: 0.875, blue: 0.875) // #F6DFDF
    static let brand200 = Color(red: 0.933, green: 0.761, blue: 0.761) // #EEC2C2
    static let brand300 = Color(red: 0.894, green: 0.631, blue: 0.635) // #E4A1A2
    static let brand400 = Color(red: 0.855, green: 0.502, blue: 0.506) // #DA8081
    static let brand500 = Color(red: 0.808, green: 0.369, blue: 0.373) // #CE5E5F
    static let brand600 = Color(red: 0.745, green: 0.251, blue: 0.255) // #BE4041 ★主色
    static let brand700 = Color(red: 0.627, green: 0.180, blue: 0.184) // #A02E2F
    static let brand800 = Color(red: 0.506, green: 0.145, blue: 0.153) // #812527
    static let brand900 = Color(red: 0.380, green: 0.110, blue: 0.114) // #611C1D
    static let brand950 = Color(red: 0.271, green: 0.075, blue: 0.078) // #451314
}