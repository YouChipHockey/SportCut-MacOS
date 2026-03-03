//
//  LiveSourceSelectionView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 14/02/26.
//

import SwiftUI
import AVFoundation

struct LiveSourceSelectionView: View {
    
    @ObservedObject private var liveManager = LiveStreamManager.shared
    
    @State private var selectedVideoDevice: AVCaptureDevice?
    @State private var selectedAudioDevice: AVCaptureDevice?
    @State private var availableFormats: [(format: AVCaptureDevice.Format, description: String)] = []
    @State private var selectedFormatIndex: Int = 0
    @State private var errorMessage: String?
    @State private var isConfiguring: Bool = false
    
    var onConfigure: (AVCaptureDevice, AVCaptureDevice?, AVCaptureDevice.Format?) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            ScrollView {
                VStack(spacing: 20) {
                    videoSourceSection
                    audioSourceSection
                    qualitySection
                    
                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            
            footerSection
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 480, maxHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            liveManager.discoverDevices()
            
            // Auto-select first device
            if selectedVideoDevice == nil, let first = liveManager.availableVideoDevices.first {
                selectedVideoDevice = first
                updateFormats(for: first)
            }
            if selectedAudioDevice == nil, let first = liveManager.availableAudioDevices.first {
                selectedAudioDevice = first
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "record.circle")
                    .foregroundColor(.red)
                    .font(.system(size: 20))
                
                Text(^String.Titles.liveStreamTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(^String.Titles.liveStreamDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - Video Source Section
    
    private var videoSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.liveStreamVideoSource)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            if liveManager.availableVideoDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(^String.Titles.liveStreamNoVideoDevices)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                ForEach(liveManager.availableVideoDevices, id: \.uniqueID) { device in
                    deviceRow(
                        device: device,
                        isSelected: selectedVideoDevice?.uniqueID == device.uniqueID,
                        icon: deviceIcon(for: device)
                    ) {
                        selectedVideoDevice = device
                        updateFormats(for: device)
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Source Section
    
    private var audioSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.liveStreamAudioSource)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            // Temporary simplified audio selection:
            // we always use the Mac's built-in microphone (or no audio if it's unavailable).
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundColor(.secondary)
                Text("Источник звука: микрофон компьютера (автоматически)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Quality Section
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.liveStreamQuality)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            if availableFormats.isEmpty {
                Text(^String.Titles.liveStreamSelectDeviceFirst)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
            } else {
                Picker("", selection: $selectedFormatIndex) {
                    ForEach(0..<availableFormats.count, id: \.self) { index in
                        Text(availableFormats[index].description)
                            .tag(index)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(^String.Titles.collectionsButtonCancel)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: {
                    configureAndStart()
                }) {
                    HStack(spacing: 8) {
                        if isConfiguring {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Image(systemName: "video.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text(^String.Titles.liveStreamStartButton)
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: .red.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedVideoDevice == nil || isConfiguring)
                .opacity(selectedVideoDevice == nil || isConfiguring ? 0.6 : 1.0)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Device Row
    
    private func deviceRow(device: AVCaptureDevice, isSelected: Bool, icon: String, onTap: @escaping () -> Void) -> some View {
        deviceRow(label: device.localizedName, isSelected: isSelected, icon: icon, onTap: onTap)
    }
    
    private func deviceRow(label: String, isSelected: Bool, icon: String, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)
                .font(.system(size: 16))
            
            Image(systemName: icon)
                .foregroundColor(isSelected ? .blue : .secondary)
                .font(.system(size: 14))
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .primary : .secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.4) : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    // MARK: - Helpers
    
    private func deviceIcon(for device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInWideAngleCamera:
            return "camera.fill"
        case .externalUnknown:
            return "video.fill"
        default:
            return "camera.fill"
        }
    }
    
    private func updateFormats(for device: AVCaptureDevice) {
        availableFormats = liveManager.getAvailableFormats(for: device)
        selectedFormatIndex = 0
    }
    
    private func configureAndStart() {
        guard let videoDevice = selectedVideoDevice else { return }
        
        isConfiguring = true
        errorMessage = nil
        
        let format = availableFormats.isEmpty ? nil : availableFormats[selectedFormatIndex].format
        
        // HaishinKit configureSession triggers async Task internally
        _ = liveManager.configureSession(
            videoDevice: videoDevice,
            audioDevice: selectedAudioDevice,
            format: format
        )
        
        // Poll for configuration result (HaishinKit MediaMixer is an actor, async setup)
        pollForConfiguration(videoDevice: videoDevice, format: format, attempts: 0)
    }
    
    private func pollForConfiguration(videoDevice: AVCaptureDevice, format: AVCaptureDevice.Format?, attempts: Int) {
        let maxAttempts = 20 // Up to 4 seconds (20 * 200ms)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            if liveManager.isSessionConfigured {
                isConfiguring = false
                onConfigure(videoDevice, selectedAudioDevice, format)
            } else if attempts >= maxAttempts {
                isConfiguring = false
                errorMessage = ^String.Titles.liveStreamConfigError
            } else {
                pollForConfiguration(videoDevice: videoDevice, format: format, attempts: attempts + 1)
            }
        }
    }
}
