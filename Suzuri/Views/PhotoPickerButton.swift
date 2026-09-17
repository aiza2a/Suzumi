import Foundation
import PhotosUI
import SwiftUI

/// 图片选择失败原因。
enum PhotoPickerError: Error, Equatable, Sendable {
    case noData
}

/// 选择图片并将 PhotosPicker 原始数据交给上层处理。
struct PhotoPickerButton: View {
    let onImageData: (Data) -> Void
    let onError: ((Error) -> Void)?
    let onLoadingChanged: ((Bool) -> Void)?

    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoading = false

    init(
        onImageData: @escaping (Data) -> Void,
        onError: ((Error) -> Void)? = nil,
        onLoadingChanged: ((Bool) -> Void)? = nil
    ) {
        self.onImageData = onImageData
        self.onError = onError
        self.onLoadingChanged = onLoadingChanged
    }

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            if isLoading {
                ProgressView()
            } else {
                Label("添加图片", systemImage: "photo")
            }
        }
        .disabled(isLoading)
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                await load(item)
            }
        }
    }

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        onLoadingChanged?(true)
        defer {
            isLoading = false
            onLoadingChanged?(false)
            selectedItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                onError?(PhotoPickerError.noData)
                return
            }
            onImageData(data)
        } catch {
            onError?(error)
        }
    }
}
