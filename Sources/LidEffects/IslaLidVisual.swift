import AppKit
import QuartzCore
import IslandCore
extension NSScreen {
 var displayID:CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
 static var builtIn:NSScreen? { screens.first{screen in screen.displayID.map{CGDisplayIsBuiltin($0) != 0} ?? false} }
}
/// Sensor is retained exclusively on its actor; IOHID reads never block the UI.
public actor IslaLidSensor {
 private var sensor:LidAngleSensor?
 public init() {}
 public func readAngle() -> Double? { if sensor == nil { sensor=LidAngleSensor() };return sensor?.angle() }
 public func reset() { sensor=nil }
}
@MainActor public final class IslaLidVisual:NSObject {
 private let overlay=DepthOverlay()
 private let stream=ScreenStreamer()
 private let snapshotter=ScreenSnapshotter()
 private var seedTask:Task<Void,Never>?
 private var seedGeneration=0
 private var angleSpring=CriticallyDampedSpring()
 private var progressSpring=CriticallyDampedSpring()
 private var lastFrameTime=0.0
 private var needsImage=true
 private var displayedScreenID:CGDirectDisplayID?
 private var link:CADisplayLink?
 private var targetAngle=100.0
 private var currentAngle=100.0
 private var targetProgress=0.0
 private var progress=0.0
 private var tuning=DepthTuning()
 private var showing=false
 private var finishing=false
 private var health=CaptureHealth()
 private var prewarmedFrame:CapturedFrame?
 public var isCapturing:Bool { stream.isStarted || seedTask != nil }
 public var error:String? { health.error }
 public var accessError:String? { stream.accessError }
 public override init() { super.init() }
 public func prepareAccess() async -> Bool {
 // Validate with the same ScreenCaptureKit API as Mac Duo. Legacy preflight
 // is advisory: the actual capture API decides whether this build is allowed.
 stream.invalidateFilter();await stream.warmFilter()
 return stream.hasFilter
 }
 public func prepare() {
 guard health.error == nil,stream.hasFilter,NSScreen.builtIn != nil else { return }
 if let failure=stream.error { health.fail(failure);stop();return }
 if !showing {
 let frame=stream.newFrame()
 if let frame { prewarmedFrame=frame }
 health.observePrewarm(hasFrame:frame != nil || snapshotter.latestImage != nil,at:CACurrentMediaTime())
 }
 guard health.error == nil else { stop();return }
 guard overlay.warmUp() else { health.fail("Metal no está disponible para el efecto.");return }
 if !stream.isStarted {
 health.begin(at:CACurrentMediaTime());stream.start()
 // Upstream seeds its live overlay with one screenshot while SCStream starts.
 let token=seedGeneration
 seedTask=Task { [weak self] in
 guard let self else { return }
 await self.snapshotter.captureOnce()
 guard !Task.isCancelled,token==self.seedGeneration else { return }
 self.seedTask=nil
 }
 }
 }
 static func appearance(reduceMotion:Bool) -> DepthTuning {
 var value=DepthTuning()
 value.viewingDistance=6
 value.recession=0
 value.blurEvenness=0
 value.dimReach=0.5
 // Keep the full display covered; only the top-to-bottom blur front moves.
 value.maxBlurRadius=135
 value.maxDim=0.08
 return value
 }
 public func update(angle:Double,progress:Double,reduceMotion:Bool,startAngle:Double=100) {
 prepare();guard health.error == nil,let screen=NSScreen.builtIn else { return }
 finishing=false
 targetAngle=angle;targetProgress=progress
 tuning=Self.appearance(reduceMotion:reduceMotion)
 if !showing {
 currentAngle=startAngle;self.progress=0
 angleSpring.reset(to:startAngle);progressSpring.reset(to:0)
 guard overlay.showLive(on:screen,startAngle:startAngle,tuning:tuning,fadeIn:0.07) else { health.fail("No se pudo iniciar el efecto.");stop();return }
 displayedScreenID=screen.displayID;showing=true;lastFrameTime=CACurrentMediaTime()
 absorbInitialImage()
 // Start the link immediately: a screenshot or frame arriving between polls
 // must reveal the overlay even if the next lid reading is delayed.
 link=overlay.hostWindow?.displayLink(target:self,selector:#selector(renderFrame));link?.preferredFrameRateRange=CAFrameRateRange(minimum:30,maximum:30,preferred:30);link?.add(to:.main,forMode:.common)
 }
 }
 private func absorbInitialImage() {
 if let frame=prewarmedFrame ?? stream.newFrame() {
 prewarmedFrame=nil;overlay.absorb(frame);needsImage=false;health.receivedFrame(at:CACurrentMediaTime())
 } else if needsImage,let image=snapshotter.latestImage,snapshotter.latestScreen?.displayID==displayedScreenID {
 overlay.seed(image:image)
 if overlay.isPictureReady { needsImage=false;health.receivedFrame(at:CACurrentMediaTime()) }
 }

 }
 @objc private func renderFrame() {
 guard NSScreen.builtIn?.displayID == displayedScreenID else { stop();return }
 if let failure=stream.error { health.fail(failure);stop();return }
 absorbInitialImage()
 if !finishing { health.check(at:CACurrentMediaTime()) }
 guard health.error == nil else { stop();return }
 let now=CACurrentMediaTime();let dt=min(max(now-lastFrameTime,1.0/240),1.0/20);lastFrameTime=now
 angleSpring.advance(to:targetAngle,dt:dt);progressSpring.advance(to:targetProgress,dt:dt)
 currentAngle=angleSpring.value;progress=progressSpring.value
 overlay.update(progress:progress,currentAngle:currentAngle,tuning:tuning)
 if finishing,abs(progress)<0.001,abs(progressSpring.velocity)<0.01 { stop() }
 }
 /// Stop acquiring frames immediately, then reverse the last image to clear.
 /// Repeated idle sensor polls must not reset the spring or extend the animation.
 public func finish() {
 guard showing else { stop();return }
 guard !finishing else { return }
 finishing=true;targetProgress=0;targetAngle=currentAngle
 seedGeneration += 1;seedTask?.cancel();seedTask=nil;snapshotter.stop();stream.stop();health.stop()
 }
 public func reset() { stop();health.reset();stream.resetFailure() }
 public func stop() { seedGeneration += 1;seedTask?.cancel();seedTask=nil;snapshotter.stop();link?.invalidate();link=nil;stream.stop();overlay.dismiss(animated:false);overlay.discardLive();showing=false;finishing=false;needsImage=true;displayedScreenID=nil;prewarmedFrame=nil;health.stop() }
}
