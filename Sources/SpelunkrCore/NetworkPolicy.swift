import Foundation

public enum NetworkPolicy {
    public static let lineupRefreshInterval: TimeInterval = 300
    public static let communityRefreshInterval: TimeInterval = 300
    public static let communityMinimumFetchInterval: TimeInterval = 15
    public static let concurrentGuideLoads = 4
    public static let communityPageSize = 1000
    public static let communityMaximumPages = 2
}

actor BroadcastRequestLimiter {
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if active < NetworkPolicy.concurrentGuideLoads { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }
}
