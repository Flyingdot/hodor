import AppKit
import Foundation
import HodorCore
import SwiftUI
import Testing

@testable import HodorUI

/// Renders the views offscreen with fixture data and writes PNGs to .build/ui-snapshots for a visual check.
/// The assertions only cover size; look at the PNGs to judge the layout.
@MainActor
struct RenderTests {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hodor-ui-tests-\(UUID().uuidString)/config.json")

    struct SSHError: Error {}

    nonisolated static let servers = [
        DevServer(port: 22),
        DevServer(
            port: 3780, pid: 101, process: "node", directory: "/home/dani/dev/app/.claude/worktrees/feature+login/web",
            worktreePath: "/home/dani/dev/app/.claude/worktrees/feature+login", gitCommonDir: "/home/dani/dev/app/.git",
            branch: "feature/login"),
        DevServer(
            port: 4201, pid: 102, process: "dotnet", directory: "/home/dani/dev/app/api", worktreePath: "/home/dani/dev/app",
            gitCommonDir: "/home/dani/dev/app/.git", branch: "main"),
        DevServer(port: 8000, pid: 103, process: "python3", directory: "/home/dani"),
    ]

    @Test func groupsServersByWorktree() {
        func row(showAll: Bool, hosts: [String] = ["winterfell"]) -> ProjectRow {
            ProjectRow(
                project: .constant(Project(name: "A", url: "https://localhost:4200")), hosts: hosts,
                discovery: ["winterfell": HostServers(servers: Self.servers)], showAllServers: showAll, status: .inactive,
                onToggle: { _ in }, onEdit: {}, onDelete: {})
        }
        let filtered = row(showAll: false).groups
        #expect(filtered.map(\.title) == ["app (main)", "app › feature+login"])
        #expect(filtered.map { $0.servers.map(\.port) } == [[4201], [3780]])
        #expect(row(showAll: false).worktreeLabel(Self.servers[1]) == ":3780  ·  web  ·  node")
        let dotnetApp = DevServer(
            port: 5000, pid: 1, process: "Shop.Web", directory: "/w/src/Shop.Web", worktreePath: "/w")
        #expect(row(showAll: false).worktreeLabel(dotnetApp) == ":5000  ·  src/Shop.Web")

        let all = row(showAll: true).groups
        #expect(all.map(\.title).last == "Other listeners")
        #expect(all.last?.servers.map(\.port) == [22, 8000])

        #expect(row(showAll: false, hosts: ["winterfell", "castle-black"]).groups.first?.title == "winterfell  ·  app (main)")
    }

    @Test func emptyStore() throws {
        let store = ProjectStore(fileURL: fileURL)
        let view = ContentView(
            store: store, tunnels: TunnelManager(), discovery: ["winterfell": HostServers(servers: Self.servers)],
            discover: { _ in Self.servers })
        let size = try render(view, as: "content-empty")
        #expect(size.width == 420)
    }

    @Test func oneHostUnreachable() throws {
        let store = ProjectStore(fileURL: fileURL)
        store.addHost("castle-black")
        store.projects = [
            Project(name: "App feature", url: "https://localhost:4200", host: "winterfell", remotePort: 3780),
            Project(name: "Old branch", url: "http://localhost:8080", host: "castle-black", remotePort: 8080),
        ]
        let error = "ssh: Could not resolve hostname castle-black: nodename nor servname provided, or not known"
        let view = ContentView(
            store: store, tunnels: TunnelManager(),
            discovery: [
                "winterfell": HostServers(servers: Self.servers),
                "castle-black": HostServers(error: error),
            ],
            discover: { _ in throw SSHError() })
        let size = try render(view, as: "content-host-error")
        #expect(size.width == 420)
    }

    @Test(arguments: [
        ("running", TunnelStatus.running),
        ("failed", .failed("bind [127.0.0.1]:4200: Address already in use")),
        ("inactive", .inactive),
    ])
    func projectRow(name: String, status: TunnelStatus) throws {
        let project = Project(
            name: "App feature", url: "https://localhost:4200", host: "winterfell", remotePort: 3780,
            isActive: status != .inactive)
        let row = ProjectRow(
            project: .constant(project), hosts: ["winterfell"],
            discovery: ["winterfell": HostServers(servers: Self.servers)], status: status,
            onToggle: { _ in }, onEdit: {}, onDelete: {}
        )
        let size = try render(row.padding().frame(width: 420), as: "row-\(name)")
        #expect(size.height > 0)
    }

    @Test func hostsPanel() throws {
        let store = ProjectStore(fileURL: fileURL)
        store.addHost("castle-black")
        store.projects = [
            Project(name: "App feature", url: "https://localhost:4200", host: "winterfell", remotePort: 3780)
        ]
        let view = HostsView(
            store: store,
            discovery: [
                "winterfell": HostServers(servers: Self.servers),
                "castle-black": HostServers(error: "ssh: connect to host castle-black port 22: Operation timed out"),
            ], suggestions: ["winterfell", "dragonstone"], onAdd: { _ in })
        let size = try render(view.padding().frame(width: 420), as: "hosts")
        #expect(size.height > 0)
    }

    @Test func hostsPage() throws {
        let store = ProjectStore(fileURL: fileURL)
        store.projects = [
            Project(name: "App feature", url: "https://localhost:4200", host: "winterfell", remotePort: 3780)
        ]
        let view = ContentView(
            store: store, tunnels: TunnelManager(), discovery: ["winterfell": HostServers(servers: Self.servers)],
            discover: { _ in Self.servers }, showHosts: true)
        let size = try render(view, as: "content-hosts")
        #expect(size.width == 420)
    }

    @Test func projectForm() throws {
        let form = ProjectForm(project: nil, onSave: { _ in }, onCancel: {})
        let size = try render(form.padding().frame(width: 420), as: "form-add")
        #expect(size.height > 0)
    }

    @Test func darkMode() throws {
        let store = ProjectStore(fileURL: fileURL)
        store.projects = [
            Project(name: "App feature", url: "https://localhost:4200", host: "winterfell", remotePort: 3780)
        ]
        let view = ContentView(
            store: store, tunnels: TunnelManager(), discovery: ["winterfell": HostServers(servers: Self.servers)],
            discover: { _ in Self.servers })
        let size = try render(view, as: "content-dark", appearance: .darkAqua)
        #expect(size.width == 420)
    }

    @Test func brand() throws {
        let glyphs = HStack(spacing: 16) {
            HodorMark(size: 128)
            HodorMark()
            ForEach([false, true], id: \.self) { open in
                Image(nsImage: MenuBarIcon.image(open: open))
                Image(nsImage: MenuBarIcon.image(open: open)).resizable().frame(width: 72, height: 72)
            }
        }
        let size = try render(glyphs.padding(), as: "brand")
        #expect(MenuBarIcon.image(open: true).isTemplate)
        #expect(size.height > 128)
    }

    /// Draws the view through AppKit (ImageRenderer leaves out AppKit-backed controls), in light mode by default.
    private func render(_ view: some View, as name: String, appearance: NSAppearance.Name = .aqua) throws -> NSSize {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/ui-snapshots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
        return host.bounds.size
    }
}
