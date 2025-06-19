//
//  StreamsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Foundation
import Combine
import FirebaseAppCheck

struct StreamsView: View {
    @ObservedObject private var streamManager = StreamManager.shared
    @State private var selectedStreamId: Int? = nil
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Доступные трансляции")
                .font(.title2)
                .fontWeight(.bold)
            
            Button(action: {
                streamManager.refreshAvailableStreams()
            }) {
                Label("Обновить список", systemImage: "arrow.clockwise")
            }
            .disabled(streamManager.isLoading)
            
            if streamManager.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.0)
                    .padding()
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(streamManager.availableStreams, id: \.id) { stream in
                        StreamCard(
                            stream: stream,
                            isSelected: selectedStreamId == stream.id,
                            isAvailable: streamManager.isStreamAvailable(stream)
                        )
                        .onTapGesture {
                            selectedStreamId = stream.id
                            playSelectedStream(stream.id)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            if streamManager.availableStreams.isEmpty && !streamManager.isLoading {
                VStack {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .padding()
                    
                    Text("Нет доступных трансляций")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear {
            if streamManager.availableStreams.isEmpty {
                streamManager.refreshAvailableStreams()
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Ошибка"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func playSelectedStream(_ streamId: Int) {
        streamManager.playStream(streamId: streamId) { result in
            switch result {
            case .success:
                print("Stream started successfully")
                
                WindowsManager.shared.openVideoPlayerWindow(
                    id: String(streamId)
                )
                
            case .failure(let error):
                errorMessage = error.description
                showErrorAlert = true
            }
        }
    }
}

struct StreamCard: View {
    let stream: Stream
    let isSelected: Bool
    let isAvailable: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: stream.scheduledStart)
    }
    
    var body: some View {
        HStack {
            if stream.isLive {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text("LIVE")
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                .padding(.trailing, 8)
            } else {
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(stream.title)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(isAvailable ? .blue : .gray)
            }
            .disabled(!isAvailable)
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .opacity(isAvailable ? 1.0 : 0.7)
    }
}
