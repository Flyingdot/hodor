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
        DevServer(port: 3780, pid: 101, process: "node-MainThread", directory: "/home/dani/dev/app-feature"),
        DevServer(port: 4201, pid: 102, process: "node", directory: "/home/dani/dev/app-main"),
    ]

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
        let view = HostsView(
            store: store,
            discovery: [
                "winterfell": HostServers(servers: Self.servers),
                "castle-black": HostServers(error: "ssh: connect to host castle-black port 22: Operation timed out"),
            ], onAdd: { _ in })
        let size = try render(view.padding().frame(width: 420), as: "hosts")
        #expect(size.height > 0)
    }

    @Test func projectForm() throws {
        let form = ProjectForm(project: nil, onSave: { _ in }, onCancel: {})
        let size = try render(form.padding().frame(width: 420), as: "form-add")
        #expect(size.height > 0)
    }

    /// Draws the view through AppKit (ImageRenderer leaves out AppKit-backed controls) in light mode.
    private func render(_ view: some View, as name: String) throws -> NSSize {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .aqua)
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
