// swift-tools-version: 6.0
import PackageDescription
let package=Package(name:"IslaMediaRemoteAdapter",platforms:[.macOS(.v15)],products:[.library(name:"IslaMediaRemoteAdapter",type:.dynamic,targets:["CIMediaRemote"])],targets:[.target(name:"CIMediaRemote",publicHeadersPath:"include",cSettings:[.unsafeFlags(["-fobjc-arc"])],linkerSettings:[.linkedFramework("Foundation"),.linkedFramework("AppKit")])])
