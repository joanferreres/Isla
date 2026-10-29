import SwiftUI
import Combine
import IslandCore
@MainActor final class AppleMusicService:ObservableObject {
 @Published var state=MediaState()
 @Published var error:String?
 @Published var enabled=false
 let stream=SystemMediaStream()
 var receivedAt=Date()
 var retryStreamAfter=Date.distantPast
 let reader:any AppleMusicReading
 var timer:Timer?
 var observer:NSObjectProtocol?
 private var permissionDenied=false
 private var refreshing=false
 private var generation=0
 init(reader:any AppleMusicReading=AppleMusicBridge()) { self.reader=reader }
 func connect() {
 guard !enabled else { return };permissionDenied=false;enabled=true;generation += 1
 observer=DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.apple.Music.playerInfo"),object:nil,queue:.main) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
 stream.onReply={ [weak self] reply in
 guard let self,self.enabled else { return }
 if let snapshot=reply.snapshot {
 self.state.update(snapshot);self.receivedAt=Date();self.error=nil
 if let data=reply.artwork(for:snapshot.trackID) { _=self.state.acceptArtwork(data,for:snapshot.trackID) }
 } else { Task { await self.refresh() } }
 }
 stream.onStopped={ [weak self] in guard let self,self.enabled else { return };self.retryStreamAfter=Date().addingTimeInterval(60);self.startFallbackTimer();Task { await self.refresh() } }
 if !stream.start() { startFallbackTimer();Task { await refresh() } }

 }
 func startFallbackTimer() {
 guard timer == nil else { return }
 timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in Task { @MainActor in
 guard let self,self.enabled else { return }
 if Date()>=self.retryStreamAfter,self.stream.start() { self.timer?.invalidate();self.timer=nil;return }
 await self.refresh()
 } };timer?.tolerance=3
 }
 func displayPosition(at date:Date) -> Double {
 guard let snapshot=state.snapshot else { return 0 }
 return min(snapshot.duration,max(0,snapshot.position+(snapshot.playing ? max(0,date.timeIntervalSince(receivedAt)) : 0)))
 }
 func pauseForSleep() { enabled=false;generation += 1;timer?.invalidate();timer=nil;stream.stop();if let observer { DistributedNotificationCenter.default().removeObserver(observer) };observer=nil }
 func disconnect() { enabled=false;stream.stop();generation += 1;timer?.invalidate();timer=nil;if let observer { DistributedNotificationCenter.default().removeObserver(observer) };observer=nil;state.update(nil) }
 func refresh() async {
 guard enabled,!refreshing,!permissionDenied else { return };refreshing=true;defer { refreshing=false };let current=generation
 guard await reader.isRunning() else { state.update(nil);error=nil;return }
 do {
 let snapshot=try await reader.read();guard enabled,current == generation else { return }
 let changed=state.snapshot?.trackID != snapshot?.trackID
 state.update(snapshot);receivedAt=Date();error=nil
 if let snapshot,changed || state.artworkData == nil {
 let data=try await reader.artwork(trackID:snapshot.trackID)
 // Re-read identity after artwork because Music can change while its artwork query is in flight.
 let latest=try await reader.read()
 guard enabled,current == generation else { return }
 state.update(latest);receivedAt=Date()
 if let data,latest?.trackID == snapshot.trackID { _=state.acceptArtwork(data,for:snapshot.trackID) }
 }
 } catch { guard enabled,current == generation else { return };self.error=error.localizedDescription;state.update(nil);if (error as? MusicFailure)?.code == -1743 { permissionDenied=true;timer?.invalidate();timer=nil } }
 }
 func send(_ command:MediaCommand) { guard !permissionDenied else { return };Task { do { guard await reader.isRunning() else { state.update(nil);return };try await reader.send(command);await refresh() } catch { self.error=error.localizedDescription } } }
}
