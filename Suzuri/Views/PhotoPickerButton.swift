import Foundation
import PhotosUI
import SwiftUI

/// 选择图片并将 PhotosPicker 原始数据交给上层处理。
struct PhotoPickerButton: View {
    let onImageData: (Data) -> Void
    let onError: ((Error) -> Void)?

    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoading = false

    init(onImageData: @escaping (Data) -> Void,
         onError: ((Error) -> Void)? = nil) {
        self.onImageData = onImageData
        self.onError = onError
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
        defer {
            isLoading = false
            selectedItem = nil
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                onImageData(data)
            }
        } catch {
            onError?(error)
        }
    }
}
