import SwiftUI
import PhotosUI
import UIKit

// Editor local y exportador de fondos para el Moto Watch Fit.
// NO instala una esfera por Bluetooth. La transferencia de álbum/fotografía
// debe validarse primero con la aplicación oficial Motorola y una captura HCI.
private enum FaceLayout: String, CaseIterable, Identifiable {
    case grande = "Grande"
    case centrado = "Centrado"
    case compacto = "Compacto"
    var id: String { rawValue }
}

private enum FaceAccent: String, CaseIterable, Identifiable {
    case blanco = "Blanco"
    case naranja = "Naranja"
    case celeste = "Celeste"
    case verde = "Verde"
    var id: String { rawValue }
    var tint: Color {
        switch self {
        case .blanco: return .white
        case .naranja: return Color(red: 1.0, green: 0.66, blue: 0.25)
        case .celeste: return Color(red: 0.33, green: 0.88, blue: 1.0)
        case .verde: return Color(red: 0.70, green: 0.98, blue: 0.53)
        }
    }
}

private struct FaceExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct FaceShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Imagen a resolución 390 × 450 como plantilla de trabajo obtenida del
/// layout de la APK XT2541-1. NO supone que sea el paquete Motorola instalable.
private struct FaceArtwork: View {
    let image: UIImage?
    let layout: FaceLayout
    let accent: FaceAccent
    let date: Date
    let temperature: Int?
    let showWeatherExample: Bool
    let includeOverlay: Bool

    private var clock: String {
        date.formatted(.dateTime.hour().minute())
    }
    private var today: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            .uppercased()
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 390, height: 450)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.07, green: 0.10, blue: 0.25),
                                 Color(red: 0.02, green: 0.13, blue: 0.23), .black],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(accent.tint.opacity(0.24))
                        .frame(width: 330, height: 330)
                        .blur(radius: 85)
                        .offset(x: 110, y: -100)
                    Circle()
                        .stroke(accent.tint.opacity(0.30), lineWidth: 2)
                        .frame(width: 310, height: 310)
                        .offset(x: 104, y: 107)
                }
            }

            if includeOverlay {
                LinearGradient(colors: [.black.opacity(0.36), .clear,
                                        .black.opacity(0.52)],
                               startPoint: .top, endPoint: .bottom)
                overlay
                    .padding(26)
            }
        }
        .frame(width: 390, height: 450)
        .clipped()
    }

    @ViewBuilder
    private var overlay: some View {
        switch layout {
        case .grande:
            VStack(alignment: .leading, spacing: 10) {
                Text(today).font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                Text(clock)
                    .font(.system(size: 82, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(accent.tint)
                Spacer()
                exampleWeather
            }
        case .centrado:
            VStack(spacing: 11) {
                Spacer()
                Text(clock)
                    .font(.system(size: 82, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(accent.tint)
                Text(today)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                exampleWeather
            }
            .frame(maxWidth: .infinity)
        case .compacto:
            VStack(alignment: .leading, spacing: 9) {
                Spacer()
                Text(clock)
                    .font(.system(size: 62, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.65).lineLimit(1)
                    .foregroundStyle(accent.tint)
                Text(today)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                exampleWeather
            }
        }
    }

    @ViewBuilder
    private var exampleWeather: some View {
        if showWeatherExample {
            HStack(spacing: 9) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(accent.tint, .white)
                Text(temperature.map { "\($0)°" } ?? "--°")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("CLIMA").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(12)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct WatchFaceStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var weather = WatchWeatherService.shared
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var layout: FaceLayout = .grande
    @State private var accent: FaceAccent = .celeste
    @State private var weatherExample = false
    @State private var shareFile: FaceExport?
    @State private var errorMessage: String?
    @State private var isPicking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Diseñá tu esfera")
                    .font(.title2.bold())
                Text("Elegí una imagen, un estilo de reloj y un color. Se prepara en iWatch; todavía no se instala por Bluetooth.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    FaceArtwork(image: photo, layout: layout, accent: accent, date: .now,
                                temperature: weather.snapshot.map { Int($0.temperatureCelsius.rounded()) },
                                showWeatherExample: weatherExample, includeOverlay: true)
                        .scaleEffect(0.73)
                        .frame(width: 285, height: 329)
                        .clipShape(RoundedRectangle(cornerRadius: 45))
                        .overlay(RoundedRectangle(cornerRadius: 45)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 2))
                    Spacer()
                }
                Text("VISTA PREVIA · 390 × 450 · La hora y el clima se dibujan solo en iWatch")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Fondo").font(.headline)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $chosenPhoto, matching: .images) {
                            Label("Elegir foto", systemImage: "photo.on.rectangle.angled")
                        }
                        .buttonStyle(.borderedProminent)
                        if photo != nil {
                            Button("Quitar foto") {
                                photo = nil
                                chosenPhoto = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("La fotografía se procesa en el teléfono y no se envía a un servidor.")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("Estilo del reloj").font(.headline)
                    Picker("Estilo", selection: $layout) {
                        ForEach(FaceLayout.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Color de la hora").font(.headline)
                    HStack {
                        ForEach(FaceAccent.allCases) { value in
                            Button {
                                accent = value
                            } label: {
                                Circle()
                                    .fill(value.tint)
                                    .frame(width: 32, height: 32)
                                    .padding(5)
                                    .overlay(Circle()
                                        .stroke(accent == value ? Color.primary : .clear,
                                                lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(value.rawValue)
                        }
                    }

                    Toggle("Ver ejemplo de clima", isOn: $weatherExample)
                    Text("El bloque de clima es una maqueta. Su instalación como complicación dinámica no está confirmada para una esfera fotográfica.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 20))

                VStack(spacing: 10) {
                    Button {
                        export(includeOverlay: false)
                    } label: {
                        Label("Exportar fondo PNG", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        export(includeOverlay: true)
                    } label: {
                        Label("Compartir vista previa", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("Para usarlo hoy, exportá el fondo y cargalo como foto de esfera desde la app Motorola en un Android. El archivo de vista previa, con números dibujados, no es una esfera animada.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .navigationTitle("Personalizar esfera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { dismiss() }
            }
        }
        .onChange(of: chosenPhoto) { item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let original = UIImage(data: data) {
                        // Reducir memoria para fotos grandes antes de la vista previa.
                        let format = UIGraphicsImageRendererFormat.default()
                        format.scale = 1
                        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 780, height: 900),
                                                               format: format)
                        let scaled = renderer.image { _ in
                            let scale = max(780 / original.size.width,
                                            900 / original.size.height)
                            let size = CGSize(width: original.size.width * scale,
                                              height: original.size.height * scale)
                            original.draw(in: CGRect(x: (780 - size.width) / 2,
                                                     y: (900 - size.height) / 2,
                                                     width: size.width, height: size.height))
                        }
                        photo = scaled
                    } else {
                        errorMessage = "No se pudo abrir la imagen elegida."
                    }
                } catch {
                    errorMessage = "No se pudo cargar la fotografía."
                }
            }
        }
        .sheet(item: $shareFile) { file in
            FaceShareSheet(url: file.url)
        }
        .alert("No se pudo exportar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Error de exportación")
            }
    }

    @MainActor
    private func export(includeOverlay: Bool) {
        let drawing = FaceArtwork(
            image: photo, layout: layout, accent: accent, date: .now,
            temperature: weather.snapshot.map { Int($0.temperatureCelsius.rounded()) },
            showWeatherExample: weatherExample, includeOverlay: includeOverlay)
        let renderer = ImageRenderer(content: drawing)
        renderer.scale = 1
        guard let output = renderer.uiImage?.pngData() else {
            errorMessage = "iOS no pudo generar la imagen."
            return
        }
        do {
            let name = includeOverlay ? "iWatch-VistaPrevia-390x450.png" :
                                        "iWatch-Fondo-390x450.png"
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(name)
            try output.write(to: destination, options: .atomic)
            shareFile = FaceExport(url: destination)
        } catch {
            errorMessage = "No se pudo guardar la imagen exportada."
        }
    }
}
