import CoreBluetooth
import SwiftUI

struct DiagnosticsHostView: View {
    @StateObject private var bluetooth = BluetoothProbe()

    var body: some View {
        DiagnosticsView()
            .environmentObject(bluetooth)
            .onAppear { bluetooth.startScan() }
    }
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: BluetoothProbe

    var body: some View {
        NavigationStack {
            List {
                Section("探测结果") {
                    LabeledContent("蓝牙", value: bluetooth.bluetoothState.displayName)
                    LabeledContent("结果", value: bluetooth.result.title)
                    LabeledContent("发现设备", value: "\(bluetooth.discoveredDeviceCount)")
                    LabeledContent("Buds 候选", value: "\(bluetooth.candidateDevices.count)")
                    LabeledContent("可写 GATT", value: bluetooth.hasWritableGatt ? "已发现" : "未发现")
                }

                ForEach(bluetooth.candidateDevices) { device in
                    Section(device.name) {
                        LabeledContent("标识", value: device.id.uuidString)
                            .font(.caption)
                        LabeledContent("RSSI", value: "\(device.rssi)")
                        LabeledContent("广播服务", value: device.advertisedServiceUUIDs.joined(separator: "\n").nilIfEmpty ?? "无")
                            .font(.caption.monospaced())
                        if let manufacturerHex = device.manufacturerHex {
                            LabeledContent("厂商数据", value: manufacturerHex)
                                .font(.caption.monospaced())
                        }
                        ForEach(device.services) { service in
                            DisclosureGroup(service.uuid) {
                                if service.characteristics.isEmpty {
                                    Text("无特征")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(service.characteristics) { characteristic in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(characteristic.uuid)
                                                .font(.caption.monospaced().weight(.semibold))
                                            Text(characteristic.properties.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if let value = characteristic.lastValueHex {
                                                Text(value)
                                                    .font(.caption2.monospaced())
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                            }
                            .font(.caption.monospaced())
                        }
                    }
                }

                Section("实时日志") {
                    Text(bluetooth.logLines.suffix(180).joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("蓝牙诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: bluetooth.logFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("导出日志")
                    Button {
                        bluetooth.clearLog()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("清空日志")
                }
            }
        }
    }
}

private extension CBManagerState {
    var displayName: String {
        switch self {
        case .unknown: "未知"
        case .resetting: "重置中"
        case .unsupported: "不支持"
        case .unauthorized: "未授权"
        case .poweredOff: "已关闭"
        case .poweredOn: "已开启"
        @unknown default: "未知"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
