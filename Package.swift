// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "memtool",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(name: "Cutils"),
        .executableTarget(
            name: "memtool",
            dependencies: ["Cutils"]),
    ]
)

/*
Notes:
https://sourceware.org/glibc/wiki/MallocInternals
https://github.com/scwuaptx/Pwngdb
https://discord.com/channels/366022993882906624/366255222244507690/1034867401059225702
https://www.forensicfocus.com/articles/linux-memory-forensics-dissecting-the-user-space-process-heap/


Todo:
 - Implement heap iteration
 - Implement freed logic
 - Implement multiple arenas (non-main heap)
 - Implement implement support for huge allocs
*/
