import SwiftUI
import IslandCore
enum SettingsPage:String,CaseIterable,Identifiable {
 case general="General",modules="Módulos",ai="IA",displays="Pantallas",effects="Efectos"
 var id:String { rawValue }
 var symbol:String { switch self { case .general:return "gearshape";case .modules:return "square.grid.2x2";case .ai:return "sparkles";case .displays:return "display.2";case .effects:return "laptopcomputer" } }
 static func from(query:String?) -> SettingsPage {
 guard let query else { return .general }
 let value=query.split(separator:"&").compactMap { part -> String? in
  let kv=part.split(separator:"=",maxSplits:1).map(String.init)
  guard kv.count == 2, kv[0] == "page" || kv[0] == "tab" else { return nil }
  return kv[1].lowercased()
 }.first
 switch value {
 case "modulos","modules","musica","music": return .modules
 case "ia","ai": return .ai
 case "pantallas","displays": return .displays
 case "efectos","effects": return .effects
 case "general": return .general
 default: return .general
 }
 }
}
@MainActor struct SettingsView: View {
 @ObservedObject var calendar:CalendarService
 @ObservedObject var music:AppleMusicService
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 @ObservedObject var screenshots:ScreenshotService
 @ObservedObject var lid:LidEffectController
 @ObservedObject var updates:AppUpdateService
 @ObservedObject var store:PreferencesStore
 @State private var page:SettingsPage
 init(calendar:CalendarService,music:AppleMusicService,usage:CodexUsageService,activity:CodexActivityService,screenshots:ScreenshotService,lid:LidEffectController,updates:AppUpdateService,store:PreferencesStore,page:SettingsPage = .general) {
  self.calendar=calendar;self.music=music;self.usage=usage;self.activity=activity;self.screenshots=screenshots;self.lid=lid;self.updates=updates;self.store=store
  _page=State(initialValue:page)
 }
 var body:some View {
 VStack(spacing:0) {
 HStack(spacing:8) {
 ForEach(SettingsPage.allCases) { item in
 Button { page=item } label: {
 VStack(spacing:5) {
 Image(systemName:item.symbol).font(.system(size:21,weight:.medium)).frame(height:24)
 Text(item.rawValue).font(.system(size:12,weight:page == item ? .semibold : .regular))
 }.frame(width:92,height:58)
 .foregroundStyle(page == item ? Color.accentColor : .secondary)
 .background(page == item ? Color.accentColor.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:10))
 }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
 }
 }.padding(.vertical,10).frame(maxWidth:.infinity).background(.bar)
 Divider()
 Form {
 switch page {
 case .general: general
 case .modules: modules
 case .ai: ai
 case .displays: displays
 case .effects: effects
 }
 }.formStyle(.grouped).scrollContentBackground(.hidden)
 HStack { Text("Isla \(updates.currentVersion)");Spacer();Text("Los cambios se guardan automáticamente") }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,24).padding(.vertical,12)
 }.frame(width:640,height:480).background(Color(nsColor:.windowBackgroundColor))
 }
 private var general:some View {
 Group {
 Section {
 Text("Haz clic dentro del notch para abrir Isla.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Interacción",systemImage:"cursorarrow") }
 Section {
 HStack { Text("Ancho del panel");Spacer();Text("\(Int(store.value.expandedWidth)) pt").monospacedDigit().foregroundStyle(.secondary) }
 Slider(value:$store.value.expandedWidth,in:480...800,step:20).accessibilityLabel("Ancho del panel")
 Text("Panel compacto adaptado al contenido, con controles debajo del notch. Ajusta el ancho para dar más espacio a música y calendario.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Apariencia",systemImage:"rectangle.compress.vertical") }
 Section {
 Toggle("Avisarme de nuevas versiones",isOn:$updates.automaticChecksEnabled)
 HStack {
 Text("Versión \(updates.currentVersion)")
 Spacer()
 Button(updates.checking ? "Comprobando…" : "Buscar actualizaciones") { Task { await updates.check(force:true) } }.disabled(updates.checking)
 }
 if let update=updates.available {
 HStack { Label("Isla \(update.version) disponible",systemImage:"arrow.down.circle.fill").foregroundStyle(.green);Spacer();Button("Descargar",action:updates.openDownload) }
 } else if let error=updates.error { Text(error).font(.caption).foregroundStyle(.orange) }
 else if let checked=updates.lastChecked { Text("Última comprobación: \(checked.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary) }
 Text("Consulta las versiones publicadas en GitHub una vez por semana. Te avisa sin instalar nada automáticamente.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Actualizaciones",systemImage:"arrow.triangle.2.circlepath") }
 }
 }
 private var modules:some View {
 Group {
 Section {
 Toggle("Música",isOn:$store.value.musicEnabled)
 Picker("Fuente",selection:$store.value.musicSource) {
  ForEach(MusicSourcePreference.allCases,id:\.self) { source in Text(source.title).tag(source) }
 }.disabled(!store.value.musicEnabled)
 Toggle("EQ Adaptative",isOn:$store.value.musicClaudeEQEnabled)
  .disabled(!store.value.musicEnabled)
 Toggle("Calendario",isOn:$store.value.calendarEnabled)
 Toggle("Bandeja de archivos",isOn:$store.value.filesEnabled)
 Toggle("Tocadiscos en el escritorio",isOn:$store.value.recordDesktopEnabled)
 Toggle("Efecto al cerrar la tapa",isOn:$store.value.lidEffectEnabled)
 Text("Activa o desactiva las funciones principales. Codex, Cursor y Claude se configuran en la pestaña IA.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Funciones",systemImage:"switch.2") }
 Section {
 Text("Apple Music y Spotify comparten carátula, canción actual, progreso, volumen, controles, tocadiscos y widget. En Automática se usa la app que esté reproduciendo.").font(.caption).foregroundStyle(.secondary)
 if let error=music.error { Text(error).font(.caption).foregroundStyle(.orange) }
 Text("El EQ Adaptative analiza el audio de la app en tu Mac (sin API ni coste) y ajusta graves, medios y agudos según la salida: auriculares, AirPods o altavoces. Isla procesa el sonido ella misma, así que funciona igual con Spotify y Apple Music sin tocar sus ajustes. Pide permiso de captura de audio la primera vez. Las playlists y el cambiador de discos de Spotify necesitan conectar tu cuenta (más abajo).").font(.caption).foregroundStyle(.secondary)
 SpotifySetupView()
 } header: { Label("Música y EQ",systemImage:"music.note") }
 Section {
 if let error=calendar.error { Text(error).font(.caption).foregroundStyle(.orange) }
 if calendar.enabled {
 if calendar.calendars.isEmpty { Text("Los calendarios aparecerán al conceder acceso.").font(.caption).foregroundStyle(.secondary) }
 ForEach(calendar.calendars) { choice in
 Toggle(choice.title,isOn:calendarBinding(choice.id))
 }
 } else { Text("Activa Calendario arriba para consultar eventos sin modificarlos.").font(.caption).foregroundStyle(.secondary) }
 Button("Probar recordatorio (8 s)") { calendar.previewReminder() }.disabled(!calendar.enabled)
 Text("El próximo evento aparece en los laterales durante los diez minutos anteriores a su inicio.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Calendarios visibles",systemImage:"calendar") }
 Section {
 Text("Arrastra archivos al notch para la bandeja o AirDrop. Desactiva «Bandeja de archivos» si no quieres esa pestaña.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Archivos",systemImage:"tray") }
 Section {
 Toggle("Gestionar capturas",isOn:$store.value.screenshotsEnabled)
 Toggle("Copiar cada captura al portapapeles",isOn:$store.value.screenshotClipboardEnabled).disabled(!store.value.screenshotsEnabled)
 Button("Guardar en Escritorio/capturas") {
 do { try screenshots.configureSystemFolder();store.value.screenshotsEnabled=true }
 catch { screenshots.error="No se pudo configurar la carpeta de capturas." }
 }
 Button("Abrir carpeta de capturas") { NSWorkspace.shared.open(screenshots.folder) }
 Text("Las capturas se guardan en Escritorio/capturas y puedes pegarlas con ⌘V. No se añaden al notch.").font(.caption).foregroundStyle(.secondary)
 if let error=screenshots.error { Text(error).font(.caption).foregroundStyle(.orange) }
 } header: { Label("Capturas",systemImage:"camera.viewfinder") }
 }
 }
 private var ai:some View {
 Group {
 Section {
 HStack(spacing:12) {
 CodexUsageRing(fraction:usage.enabled ? usage.snapshot?.homeUsage?.usedFraction : nil,stale:usage.stale,reduceMotion:store.value.reduceMotion)
 VStack(alignment:.leading,spacing:4) { Text("Codex").font(.headline);Text(usage.enabled ? "Conectado a tu sesión de Codex" : "Usa tu sesión de Codex en este Mac").font(.caption).foregroundStyle(.secondary) }
 }
 Toggle("Conectar Codex",isOn:$store.value.codexEnabled)
 Toggle("Mostrar Codex en Inicio",isOn:$store.value.showCodexOnHome).disabled(!usage.notchReady)
 Text("El anillo rodea el logo y muestra el porcentaje consumido de la ventana corta. Solo aparece en el notch cuando la consulta de límites funciona.").font(.caption).foregroundStyle(.secondary)
 if !usage.notchReady,store.value.codexEnabled {
 Text("Codex no se muestra en el notch hasta que Actualizar devuelva límites.").font(.caption).foregroundStyle(.secondary)
 }
 if let error=usage.error { Text(error).font(.caption).foregroundStyle(.orange) }
 if usage.enabled {
 HStack { Text(usage.stale ? "Última lectura guardada" : "Uso de la cuenta").font(.caption).foregroundStyle(.secondary);Spacer();Button("Actualizar") { Task { await usage.refresh() } }.disabled(usage.loading) }
 }
 } header: { Text("Codex") }
 AIAccountSettings(service:AIUsageAccounts.shared.cursor,enabled:$store.value.cursorEnabled,showOnHome:$store.value.showCursorOnHome)
 AIAccountSettings(service:AIUsageAccounts.shared.claude,enabled:$store.value.claudeEnabled,showOnHome:$store.value.showClaudeOnHome)
 AIAccountSettings(service:AIUsageAccounts.shared.antigravity,enabled:$store.value.antigravityEnabled,showOnHome:$store.value.showAntigravityOnHome)
 Section {
 Picker("Modo de avisos",selection:$store.value.aiNotificationMode) {
 ForEach(AINotificationMode.allCases,id:\.self) { mode in Text(mode.title).tag(mode) }
 }
 Text("El botón junto a la chincheta alterna entre sonido y borde, solo borde o ningún aviso. La elección se guarda automáticamente.").font(.caption).foregroundStyle(.secondary)
 HStack { Text("Probar aviso");Spacer();ForEach(AlertSource.allCases,id:\.self) { source in Text(source.title).font(.body).padding(.horizontal,14).padding(.vertical,6).background(.quaternary,in:Capsule()).opacity(store.value.aiVisualEnabled ? 1 : 0.4).contentShape(Capsule()).onTapGesture { if store.value.aiVisualEnabled { activity.previewNotification(source:source) } }.accessibilityElement(children:.ignore).accessibilityLabel("Probar aviso de \(source.title)").accessibilityAddTraits(.isButton) } }
 Text("El borde de color resalta la isla al terminar y se desvanece: verde para Codex, naranja para Claude y blanco para Cursor. Sin avisos también oculta el mensaje de finalización.").font(.caption).foregroundStyle(.secondary)
 Text("Ocultar Codex de Inicio conserva sus avisos y estadísticas si sigue conectado.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Avisos",systemImage:"bell") }
 }
 }
 private var displays:some View {
 Section {
 Picker("Mostrar Isla en",selection:$store.value.showOnAllDisplays) {
 Text("Solo la pantalla principal").tag(false)
 Text("Todas las pantallas").tag(true)
 }
 Text("La pantalla principal es la elegida en Ajustes del Sistema → Pantallas. Puede ser la del Mac o un monitor externo.").font(.caption).foregroundStyle(.secondary)
 Label(store.value.showOnAllDisplays ? "Una isla en cada pantalla conectada" : "La isla aparece solo en tu pantalla principal",systemImage:store.value.showOnAllDisplays ? "display.2" : "display").foregroundStyle(.secondary).padding(.vertical,6)
 Text("La selección se aplica al instante, también al conectar o desconectar un monitor.").font(.caption).foregroundStyle(.secondary)
 } header: { Text("Dónde aparece Isla") }
 }
 private var effects:some View {
 Group {
 Section {
 Toggle("Efecto al cerrar la tapa",isOn:$store.value.lidEffectEnabled)
 Text("Desenfoque suave de arriba abajo sobre toda la pantalla, con un oscurecimiento ligero al bajar la tapa.").font(.caption).foregroundStyle(.secondary)
 if !lid.enabled,let angle=lid.angle { Text("Sensor detectado · \(Int(angle))°").font(.caption).foregroundStyle(.secondary) }
 if let error=lid.error {
 Text(error).font(.caption).foregroundStyle(.orange)
 HStack {
 Button("Abrir permisos") { if let url=URL(string:"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) } }
 Button("Reintentar") { Task { await lid.enable(requestPermission:true) } }.disabled(!store.value.lidEffectEnabled)
 }
 } else if lid.enabled {
 HStack {
 Label(lid.captureActive ? "Captura durante el cierre" : "Sin capturar · esperando movimiento",systemImage:lid.captureActive ? "circle.fill" : "checkmark.shield").font(.caption).foregroundStyle(lid.captureActive ? .orange : .secondary)
 Spacer()
 if let angle=lid.angle { Text("\(Int(angle))°").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
 }
 Button(lid.previewing ? "Probando…" : "Probar efecto (4 s)") { lid.preview() }.disabled(lid.previewing)
 }
 Text("La captura empieza al bajar la tapa desde su posición abierta. Al reabrir, el efecto retrocede con el ángulo. La captura se detiene al recuperar la pantalla o tras 3 segundos sin movimiento. No se guarda vídeo.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Cierre de pantalla",systemImage:"laptopcomputer") }
 Section {
 Toggle("Reducir movimiento",isOn:$store.value.reduceMotion)
 Text("Suaviza las transiciones. El efecto de cierre mantiene toda la pantalla cubierta con desenfoque progresivo.").font(.caption).foregroundStyle(.secondary)
 } header: { Label("Movimiento",systemImage:"accessibility") }
 }
 }
 private func calendarBinding(_ id:String) -> Binding<Bool> {
 Binding(get:{store.value.selectedCalendarIDs.isEmpty || store.value.selectedCalendarIDs.contains(id)},set:{ selected in
 var ids=store.value.selectedCalendarIDs.isEmpty ? calendar.calendars.map(\.id) : store.value.selectedCalendarIDs
 if selected { ids.removeAll{$0 == "__none__"};if !ids.contains(id) { ids.append(id) } } else { ids.removeAll{$0 == id} }
 store.value.selectedCalendarIDs=ids.isEmpty ? ["__none__"] : ids
 calendar.refresh()
 })
 }
}
