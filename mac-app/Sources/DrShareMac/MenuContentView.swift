import SwiftUI
import DrShareShared

struct MenuContentView: View {
    private static let windowWidth: CGFloat = 280
    private static let windowHeight: CGFloat = 460

    @ObservedObject var model: AppModel
    @State private var showSettings = false
    @State private var showQR = false
    @State private var isDropTargeted = false
    @State private var isHoveringUpload = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.2))

            if showSettings {
                settingsPanel
            } else if showQR {
                qrPanelLarge
            } else {
                recentDropsPanel
            }
        }
        .frame(width: Self.windowWidth, height: Self.windowHeight, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("drshare")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            
            Spacer()

            if !showSettings && !showQR {
                Rectangle()
                    .fill(model.isHosting ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
            }

            Button {
                showQR.toggle()
                if showQR { showSettings = false }
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 12))
                    .foregroundColor(showQR ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)

            Button {
                showSettings.toggle()
                if showSettings { showQR = false }
            } label: {
                Image(systemName: showSettings ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(showSettings ? .primary : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var qrPanelLarge: some View {
        VStack(spacing: 20) {
            if let qrCodeImage = model.qrCodeImage {
                Image(nsImage: qrCodeImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .padding(12)
                    .background(Color.white)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .overlay(Text("NO QR").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary))
            }
            
            VStack(spacing: 4) {
                Text("SCAN TO CONNECT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("pair your phone")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Button("COPY URL") {
                model.copyShareURL()
                withAnimation { showQR = false }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Rectangle().fill(Color.white.opacity(0.1)))
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var recentDropsPanel: some View {
        VStack(spacing: 0) {
            uploadZone
            
            if let activeTransfer = model.activeTransfer {
                transferPanel(for: activeTransfer)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    model.reloadDrops()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 8)

            if model.recentDrops.isEmpty {
                VStack(spacing: 8) {
                    Rectangle()
                        .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2]))
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: "doc").font(.system(size: 12)).foregroundColor(.secondary.opacity(0.5)))
                    Text("no drops yet")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding(.bottom, 16)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(model.recentDrops) { drop in
                            dropRow(for: drop)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 400)
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            HStack {
                Text(model.primaryShareURL ?? "NOT HOSTING")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("COPY") {
                    model.copyShareURL()
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .disabled(model.primaryShareURL == nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var uploadZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.primary)
            
            Text("drop here")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            Rectangle()
                .fill(Color.white.opacity(isDropTargeted || isHoveringUpload ? 0.08 : 0.02))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.white.opacity(isDropTargeted ? 0.4 : 0.1), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
        )
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
            if let provider = providers.first {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            model.uploadFile(from: url)
                        }
                    } else if let url = item as? URL {
                        Task { @MainActor in
                            model.uploadFile(from: url)
                        }
                    }
                }
                return true
            }
            return false
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringUpload = hovering
            }
        }
        .onTapGesture {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.level = .floating
            
            NSApp.activate(ignoringOtherApps: true)
            
            if panel.runModal() == .OK, let url = panel.url {
                model.uploadFile(from: url)
            }
        }
    }

    private func dropRow(for drop: DropRecord) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                
                if let thumb = model.dropThumbnails[drop.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipped()
                } else {
                    Image(systemName: drop.kind == .text ? "text.alignleft" : "doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(drop.kind == .text ? (drop.text?.components(separatedBy: .newlines).first ?? "text") : (drop.filename ?? "file"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(drop.kind == .text ? "txt" : fileMeta(for: drop))
                    Text("·")
                    Text(drop.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                if drop.kind == .text {
                    Button {
                        model.copyText(for: drop)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        model.openFile(for: drop)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    model.deleteDrop(drop)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 2)
        }
        .padding(6)
        .background(Rectangle().fill(Color.white.opacity(0.02)))
        .onAppear {
            model.loadThumbnail(for: drop)
        }
    }

    private func transferPanel(for transfer: UploadActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(transferTitle(for: transfer))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(transfer.phase == .failed ? "error" : progressPercent(for: transfer))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(transfer.phase == .failed ? .red : .secondary)
            }

            ProgressView(value: max(transfer.progressFraction, transfer.phase == .completed ? 1 : 0))
                .progressViewStyle(.linear)
                .tint(transfer.phase == .failed ? .red : .white)
                .scaleEffect(x: 1, y: 0.65, anchor: .center)

            Text(transferSubtitle(for: transfer))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(transfer.phase == .failed ? .red : .secondary)
                .lineLimit(2)
        }
        .padding(8)
        .background(Rectangle().fill(Color.white.opacity(0.04)))
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack {
                    Rectangle()
                        .fill(model.isHosting ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(model.isHosting ? "hosting on lan" : "host stopped")
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isHosting },
                        set: { if $0 { model.startHosting() } else { model.stopHosting() } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PAIRING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 10) {
                    Button("show qr code") {
                        showSettings = false
                        showQR = true
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .buttonStyle(.plain)
                    
                    Button("rotate token") {
                        model.rotateToken()
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("RETENTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Picker("auto-clear", selection: Binding(
                    get: { model.retentionPolicy },
                    set: { model.updateRetentionPolicy($0) }
                )) {
                    ForEach(RetentionPolicy.allCases) { policy in
                        Text(policy.title.lowercased()).tag(policy)
                    }
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 11, design: .monospaced))

                Text(retentionSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.top, 4)

                if let retentionOverrideDescription = model.retentionOverrideDescription {
                    Text("override active: \(retentionOverrideDescription)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.2))
    }

    private func dropLabel(for drop: DropRecord) -> String {
        "\(drop.sender.rawValue.capitalized) \(drop.kind == .text ? "text" : "file")"
    }

    private func fileMeta(for drop: DropRecord) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeLabel = formatter.string(fromByteCount: Int64(drop.size))
        return "\(sizeLabel.lowercased())"
    }

    private var retentionSummary: String {
        if model.retentionDescription == "never" {
            return "drops stay until removed manually."
        }

        return "drops auto-expire after \(model.retentionDescription)."
    }

    private func transferTitle(for transfer: UploadActivity) -> String {
        let verb = transfer.direction == .sending ? "sending" : "receiving"
        return "\(verb) \(transfer.filename.lowercased())"
    }

    private func transferSubtitle(for transfer: UploadActivity) -> String {
        let bytes = "\(fileSizeLabel(transfer.transferredBytes)) / \(fileSizeLabel(transfer.totalBytes))"

        switch transfer.phase {
        case .preparing:
            return "preparing \(transfer.direction == .sending ? "upload" : "download")..."
        case .transferring:
            return transfer.direction == .sending ? "uploading \(bytes)" : "downloading \(bytes)"
        case .finalizing:
            return "finishing \(bytes)"
        case .completed:
            return "done \(bytes)"
        case .failed:
            return transfer.errorMessage ?? "transfer failed"
        }
    }

    private func progressPercent(for transfer: UploadActivity) -> String {
        "\(Int((transfer.progressFraction * 100).rounded()))%"
    }

    private func fileSizeLabel(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes)).lowercased()
    }
}
