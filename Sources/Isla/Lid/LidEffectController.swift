import SwiftUI
import IslandCore
import LidEffects
@MainActor final class LidEffectController:ObservableObject {
 @Published var error:String?
 @Published var angle:Double?
 @Published var enabled=false
 @Published var captureActive=false
 @Published var previewing=false
 var previewTask:Task<Void,Never>?
 let sensor=IslaLidSensor()
 private let captureCheck:(() async -> Bool)?
 private let angleRead:(() async -> Double?)?
 let visual=IslaLidVisual()
 let preferences:PreferencesStore
 var policy=LidEffectPolicy()
 var task:Task<Void,Never>?
 var observers:[NSObjectProtocol]=[]
 var wanted=false
 private var generation=0
 private var starting=false
 init(preferences:PreferencesStore,captureCheck:(() async -> Bool)?=nil,angleRead:(() async -> Double?)?=nil) {
 self.preferences=preferences;self.captureCheck=captureCheck;self.angleRead=angleRead
 observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
 Task { @MainActor in guard let self,self.wanted,!self.enabled else { return };await self.enable() }
 })
 observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.suspend() } })
 observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in guard let self,self.wanted else { return };await self.enable() } })
 }
 func enable(requestPermission:Bool=false) async {
 wanted=true;guard !enabled,!starting else { return };starting=true;let g=generation;defer { if g==generation { starting=false } }
 let sample=await readCurrentAngle();guard wanted,g==generation,!enabled else { return };angle=sample
 if requestPermission,!CGPreflightScreenCaptureAccess() { _=CGRequestScreenCaptureAccess() }
 let hasAccess:Bool
 if let captureCheck { hasAccess=await captureCheck() } else { hasAccess=await visual.prepareAccess() }
 guard wanted,g==generation,!enabled else { return }
 guard hasAccess else { error="macOS no ha autorizado esta versión de Isla. En Grabación de pantalla, desactiva y activa Isla y reinicia la app si macOS lo pide.";if let detail=visual.accessError { error! += " (\(detail))" };return }
 guard let sample else { error="Este Mac no proporciona un sensor de ángulo compatible.";return }
 visual.reset();angle=sample;error=nil;enabled=true;policy=LidEffectPolicy()
 task=Task { while !Task.isCancelled,enabled {
 if previewing { try? await Task.sleep(for:.milliseconds(100));continue }
 guard let value=await readCurrentAngle() else { error="No se pudo leer el ángulo de la tapa.";suspend();return }
 guard !Task.isCancelled else { return };if angle.map({ abs($0-value)>0.1 }) ?? true { angle=value }
 switch policy.update(angle:value,timestamp:ProcessInfo.processInfo.systemUptime) {
 case .inactive:visual.finish()
 case .prewarming:visual.prepare()
 case let .active(progress):visual.update(angle:value,progress:progress,reduceMotion:preferences.value.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,startAngle:policy.startAngle)
 }
 if captureActive != visual.isCapturing { captureActive=visual.isCapturing }
 if let failure=visual.error { error=failure;suspend();return }
 try? await Task.sleep(for:.milliseconds(Int(policy.pollInterval*1000)))
 } }
 }
 private func readCurrentAngle() async -> Double? { if let angleRead { return await angleRead() };return await sensor.readAngle() }
 func preview() {
 guard enabled,!previewing else { return }
 previewing=true;visual.reset();policy=LidEffectPolicy();let g=generation
 previewTask=Task {
 defer { if generation==g { visual.finish();captureActive=false;previewing=false } }
 for index in 0..<36 {
 guard !Task.isCancelled,enabled else { return }
 let progress=max(0,min(0.8,Double(index<22 ? index : 36-index)/20))
 visual.update(angle:110-progress*60,progress:progress,reduceMotion:preferences.value.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,startAngle:110)
 captureActive=visual.isCapturing
 if let failure=visual.error { error=failure;return }
 try? await Task.sleep(for:.milliseconds(100))
 }
 }
 }
 func disable() { wanted=false;suspend() }
 func suspend() { generation += 1;starting=false;previewTask?.cancel();previewTask=nil;previewing=false;captureActive=false;enabled=false;task?.cancel();task=nil;visual.stop();policy=LidEffectPolicy();Task { await sensor.reset() } }
}
