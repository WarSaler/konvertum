//
//  ImageLoader.swift
//  Процент
//
//  Created by Константин  on 2.05.2025.
//

import SwiftUI
import Combine
import UIKit

/// Loads and caches images via URLCache for offline-first behavior
class ImageLoader: ObservableObject {
    @Published var image: UIImage? = nil
    private let url: URL
    private var cancellable: AnyCancellable?

    init(url: URL) {
        self.url = url
    }

    func load() {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
        // Try cache first
        if let cached = URLCache.shared.cachedResponse(for: request)?.data,
           let ui = UIImage(data: cached) {
            DispatchQueue.main.async { self.image = ui }
            return
        }
        // Otherwise fetch from network
        cancellable = URLSession.shared.dataTaskPublisher(for: request)
            .map { data, response -> UIImage? in
                if let http = response as? HTTPURLResponse,
                   200...299 ~= http.statusCode {
                    let cachedResp = CachedURLResponse(response: http, data: data)
                    URLCache.shared.storeCachedResponse(cachedResp, for: request)
                    return UIImage(data: data)
                }
                return nil
            }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .assign(to: \.image, on: self)
    }
}
