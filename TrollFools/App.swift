//
//  App.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import Combine
import Foundation

final class App: ObservableObject {
    let bid: String
    let name: String
    let latinName: String
    let type: String
    let teamID: String
    let url: URL
    let version: String?
    let isAdvertisement: Bool

    @Published var isDetached: Bool
    @Published var isAllowedToAttachOrDetach: Bool
    @Published var isInjected: Bool
    @Published var hasPersistedAssets: Bool

    /// App 图标。
    ///
    /// 不再使用 `lazy` 在主线程同步调用 `_applicationIconImage`：该调用会走
    /// IconServices / ImageIO 解码，列表一次渲染大量 cell 时会把主线程打满，
    /// 在 iOS 15 上触发 `scene-update` 看门狗（`0x8badf00d`）直接杀进程。
    /// 现在由 `AppIconLoader` 在后台装载，完成后回主线程回填。
    @Published var icon: UIImage?
    var alternateIcon: UIImage?
    private var isLoadingIcon = false

    lazy var isUser: Bool = type == "User"
    lazy var isSystem: Bool = !isUser
    lazy var isFromApple: Bool = bid.hasPrefix("com.apple.")
    lazy var isFromTroll: Bool = isSystem && !isFromApple
    lazy var isRemovable: Bool = url.path.contains("/var/containers/Bundle/Application/")

    weak var appList: AppListModel?
    private var cancellables: Set<AnyCancellable> = []
    private static let reloadSubject = PassthroughSubject<String, Never>()

    init(
        bid: String,
        name: String,
        type: String,
        teamID: String,
        url: URL,
        version: String? = nil,
        alternateIcon: UIImage? = nil,
        isAdvertisement: Bool = false
    ) {
        self.bid = bid
        self.name = name
        self.type = type
        self.teamID = teamID
        self.url = url
        self.version = version
        self.isDetached = InjectorV3.main.isMetadataDetachedInBundle(url)
        self.isAllowedToAttachOrDetach = type == "User" && InjectorV3.main.isAllowedToAttachOrDetachMetadataInBundle(url)
        self.isInjected = InjectorV3.main.checkIsInjectedAppBundle(url)
        self.hasPersistedAssets = InjectorV3.main.hasPersistedAssets(bid: bid)
        self.alternateIcon = alternateIcon
        self.isAdvertisement = isAdvertisement
        self.latinName = name
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .components(separatedBy: .whitespaces)
            .joined() ?? ""
        Self.reloadSubject
            .filter { $0 == bid }
            .sink { [weak self] _ in
                self?._reload()
            }
            .store(in: &cancellables)
    }

    func reload() {
        Self.reloadSubject.send(bid)
    }

    private func _reload() {
        reloadDetachedStatus()
        reloadInjectedStatus()
    }

    /// 幂等地请求异步装载图标；必须由主线程调用（只是派发任务，不会阻塞）。
    func loadIconIfNeeded() {
        if icon != nil || alternateIcon != nil || isLoadingIcon {
            return
        }
        isLoadingIcon = true
        AppIconLoader.shared.load(bid: bid) { [weak self] image in
            guard let self = self else {
                return
            }
            self.isLoadingIcon = false
            if let image = image {
                self.icon = image
            }
        }
    }

    private func reloadDetachedStatus() {
        self.isDetached = InjectorV3.main.isMetadataDetachedInBundle(url)
        self.isAllowedToAttachOrDetach = isUser && InjectorV3.main.isAllowedToAttachOrDetachMetadataInBundle(url)
    }

    private func reloadInjectedStatus() {
        self.isInjected = InjectorV3.main.checkIsInjectedAppBundle(url)
        self.hasPersistedAssets = InjectorV3.main.hasPersistedAssets(bid: bid)
    }
}

/// 在后台串行队列上装载 App 图标并做内存缓存。
///
/// `UIImage._applicationIconImage(forBundleIdentifier:format:scale:)` 会走
/// IconServices / ImageIO 做解码与缩放，单次几百毫秒；列表一次渲染大量
/// cell 时若在主线程同步调用，会长时间占满主线程，iOS 15 会以
/// `scene-update` 看门狗（`0x8badf00d`）杀掉整个进程。
final class AppIconLoader {
    static let shared = AppIconLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "wiki.qaq.TrollFools.icon-loader", qos: .utility)

    private init() {
        cache.countLimit = 512
    }

    func cachedIcon(for bid: String) -> UIImage? {
        return cache.object(forKey: bid as NSString)
    }

    /// 装载图标；`completion` 保证在主线程回调。
    func load(bid: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: bid as NSString) {
            completion(cached)
            return
        }
        queue.async { [weak self] in
            let image = UIImage._applicationIconImage(forBundleIdentifier: bid, format: 0, scale: 3.0)
            if let image = image {
                self?.cache.setObject(image, forKey: bid as NSString)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
