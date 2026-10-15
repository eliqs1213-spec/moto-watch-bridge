import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @AppStorage("motowatch.notification.whatsapp.enabled") private var whatsAppEnabled = true
    @AppStorage("motowatch.notification.instagram.enabled") private var instagramEnabled = true
    @State private var source = "WhatsApp"
    @State private var sender = "Prueba iWatch"
    @State private var message = "Probando el puente con Atajos"
    @State private var status = "Esperando prueba"

    var body: some View {
        NavigationStack {
            Form {
                Section("Conexión al reloj") {
                    LabeledContent("Bluetooth", value: watch.connectionStatus)
                    Text(watch.notificationStatus).font(.caption).foregroundStyle(.secondary)
                    Text("Los avisos tienen prioridad. Si se corta el enlace, los pendientes esperan hasta 2 minutos en memoria para el mismo reloj.").font(.caption).foregroundStyle(.secondary)
                    Text("No depende de Windows. Mantener iWatch conectada al Moto Watch Fit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Notificaciones admitidas") {
                    Toggle("WhatsApp", isOn: $whatsAppEnabled)
                    Toggle("Instagram (experimental)", isOn: $instagramEnabled)
                    Text("Estas opciones filtran lo que recibe la acción de Atajos; no otorgan acceso directo a las notificaciones de otras apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Prueba de envío al reloj") {
                    Picker("Origen", selection: $source) {
                        Text("WhatsApp").tag("WhatsApp")
                        Text("Instagram").tag("Instagram")
                        Text("iWatch").tag("iWatch")
                    }
                    TextField("Remitente", text: $sender)
                    TextField("Mensaje", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Enviar al Moto Watch") {
                        status = watch.sendNotification(source: source, sender: sender, message: message)
                            ? "Aviso encolado con prioridad"
                            : "No enviado: conexión BLE o mensaje inválido"
                    }
                    .buttonStyle(.borderedProminent)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Section("Automatizar en iOS 27") {
                    Text("Atajos → Automatización → + → Notificación → WhatsApp.")
                    Text("En la automatización, agregá la acción de iWatch «Enviar notificación al Moto Watch». Asigná Aplicación = WhatsApp, Remitente = título/remitente de la notificación, Mensaje = contenido de la notificación.")
                    Text("Antes de conectar los campos, probá «Mostrar resultado» con «Entrada de Atajo» para comprobar si WhatsApp entrega el texto. En iOS 27 puede variar según la aplicación.")
                    Text("Repetí la automatización para Instagram cuando WhatsApp funcione.")
                    Text("Ejecutarse con iPhone bloqueado es una prueba pendiente: Atajos y CoreBluetooth pueden sufrir restricciones en segundo plano.")
                        .foregroundStyle(.orange)
                }
                Section("Privacidad") {
                    Text("El remitente y el mensaje no se guardan en el registro de iWatch. Solo registramos el origen y el tamaño del paquete BLE. Los avisos pendientes se conservan temporalmente en memoria, sin guardarlos en disco.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notificaciones")
        }
    }
}
