import SwiftUI
import AppKit
import AirCore

struct Panel: View {
    @ObservedObject var monitor: Monitor
    var onSettingsChange: (Bool) -> Void = { _ in }
    @State private var settings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill").font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qingping Air").font(.headline)
                    Text(monitor.connectionText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { settings.toggle() } label: { Image(systemName: settings ? "xmark" : "gearshape") }
                    .buttonStyle(.borderless).help("Настройки")
            }
            if settings { settingsView }
            else {
                if !monitor.alerts.isEmpty {
                    Label("Красная зона: " + monitor.alerts.map(\.label).joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 2) {
                    ForEach(Metric.allCases, id: \.self) { metric in
                        let sample = monitor.fresh(metric)
                        let red = monitor.alerts.contains(metric)
                        HStack {
                            Text(metric.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(sample.map { metric.format($0.value) } ?? "—")
                                .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(red ? Color.red : Color.primary)
                            Text(metric.unit).font(.caption).foregroundStyle(.secondary).frame(width: 49, alignment: .leading)
                        }.padding(.vertical, 7)
                        if metric != .humidity { Divider() }
                    }
                }
                if monitor.sensor == nil {
                    Text("Поставьте включённый датчик рядом. Если данных нет, включите BLE Gateway в Mi Home. Сопряжение с macOS не требуется.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            HStack {
                Text("Только Bluetooth · локально").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Выход") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }
        }.padding(18).frame(width: 350)
        .onChange(of: settings) { _, value in onSettingsChange(value) }
    }
    var settingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("В строке меню", selection: $monitor.selected) {
                ForEach(Metric.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("При красной зоне автоматически показывается проблемный показатель. При нескольких: CO₂ → PM2.5 → PM10 → температура → влажность.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !monitor.sensors.isEmpty {
                Picker("Датчик", selection: $monitor.selectedID) {
                    if monitor.sensors[monitor.selectedID] == nil { Text("Сохранённый (недоступен)").tag(monitor.selectedID) }
                    ForEach(monitor.sensors.keys.sorted(), id: \.self) { id in
                        Text("Qingping · " + id.suffix(8)).tag(id)
                    }
                }
            }
            Divider()
            Text("Красная зона").font(.subheadline.bold())
            Text("Пороги приложения, можно изменить. Срабатывание на границе и за её пределами.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Metric.allCases, id: \.self) { metric in
                HStack {
                    Text(metric.shortLabel).frame(width: 46, alignment: .leading)
                    if zone(metric).lower != nil {
                        Text("≤").foregroundStyle(.secondary)
                        TextField("Мин.", value: lowerBinding(metric), format: .number).frame(width: 45)
                        Text("или").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("≥").foregroundStyle(.secondary)
                    TextField("Макс.", value: upperBinding(metric), format: .number).frame(width: 54)
                    Text(metric.unit).font(.caption2).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                }.textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Сбросить пороги") { monitor.zones = [:] }
                Spacer()
                Button("Повторить поиск") { monitor.rescan() }
            }.controlSize(.small)
            Button("Разрешения Bluetooth…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") { NSWorkspace.shared.open(url) }
            }.buttonStyle(.link).font(.caption)
        }
    }
    func zone(_ metric: Metric) -> RedZone { monitor.zones[metric] ?? .defaultZone(for: metric) }
    func upperBinding(_ metric: Metric) -> Binding<Double> {
        Binding(get: { zone(metric).upper }, set: { value in
            guard value.isFinite, value > (zone(metric).lower ?? 0) else { return }
            var z = zone(metric); z.upper = value; monitor.zones[metric] = z
        })
    }
    func lowerBinding(_ metric: Metric) -> Binding<Double> {
        Binding(get: { zone(metric).lower ?? 0 }, set: { value in
            guard value.isFinite, value < zone(metric).upper else { return }
            var z = zone(metric); z.lower = value; monitor.zones[metric] = z
        })
    }
}
