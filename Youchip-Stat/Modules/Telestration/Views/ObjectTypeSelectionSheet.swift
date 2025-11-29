//
//  ObjectTypeSelectionSheet.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ObjectTypeSelectionSheet: View {
    let viewModel: PolygonEditorViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text(^String.Titles.selectObjectType)
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(ObjectType.allCases, id: \.self) { type in
                    Button(action: {
                        viewModel.startCreatingObject(type: type)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Button(^String.Titles.cancel) {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 300)
    }
}

struct ObjectCustomizationSheet: View {
    @ObservedObject var viewModel: PolygonEditorViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            if let object = viewModel.pendingObject {
                Text("\(^String.Titles.configuration): \(object.type.displayName)")
                    .font(.headline)
                
                Group {
                    switch object.type {
                    case .zoneBetweenObjects:
                        ZoneBetweenObjectsCustomization(viewModel: viewModel)
                    case .lineBetweenObjects:
                        LineBetweenObjectsCustomization(viewModel: viewModel)
                    case .objectHighlight:
                        ObjectHighlightCustomization(viewModel: viewModel)
                    case .simpleZone:
                        SimpleZoneCustomization(viewModel: viewModel)
                    }
                }
                
                HStack {
                    Button(^String.Titles.cancel) {
                        viewModel.cancelObjectCreation()
                        presentationMode.wrappedValue.dismiss()
                    }
                    
                    Button(^String.Titles.apply) {
                        viewModel.confirmObjectCreation()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}
