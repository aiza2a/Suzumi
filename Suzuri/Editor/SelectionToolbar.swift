import SwiftUI

/// Minimal floating selection toolbar shell.
///
/// D3 owns the visibility and animation framework. Inline formatting actions are intentionally
/// deferred until the editor has a stable block-selection model.
struct SelectionToolbar: View {
    let isVisible: Bool
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .foregroundStyle(Color.brand600)
            Text("文本选区")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭选区工具栏")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .appGlass(cornerRadius: 16, brandTint: isVisible, allowsShadow: true)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.94, anchor: .bottom)
        .allowsHitTesting(isVisible)
        .animation(AppAnimation.pop, value: isVisible)
        .accessibilityHidden(!isVisible)
    }
}
