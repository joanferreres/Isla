import AppKit
import LidEffects
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--music-helper" {
 MusicHelper.run(CommandLine.arguments[2])
} else if CommandLine.arguments.contains("--lid-probe") {
 Task { let sensor=IslaLidSensor();let angle=await sensor.readAngle();print(angle.map{ "Sensor compatible: \($0)°" } ?? "Sensor no disponible");exit(0) };RunLoop.main.run()
} else {
 let application = NSApplication.shared
 let coordinator = AppCoordinator()
 application.delegate = coordinator
 application.setActivationPolicy(.accessory)
 application.run()
}
