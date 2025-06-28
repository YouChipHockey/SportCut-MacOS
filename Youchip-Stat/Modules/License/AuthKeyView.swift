//
//  AuthKeyView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 5/12/25.
//

import SwiftUI
import Foundation

struct AuthKeyView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var authKey: String = ""
    @State private var userName: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(^String.Titles.enterLicense)
                    .font(.title)
                
                Spacer()
                
                Link(destination: URL(string: "https://sportcut.youchip.pro/mac-pay")!) {
                    Text(^String.Titles.buyLicense)
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                }
                .padding(.trailing, 10)
            }
            .padding(.top)
            .padding(.horizontal)
            
            TextField(^String.Titles.license, text: $authKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
                .frame(width: 350)
            
            if let error = authManager.validationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            Spacer()
            
            HStack(spacing: 20) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text(^String.Titles.cancel)
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    authManager.validateAuth(code: authKey)
                }) {
                    if authManager.isValidating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text(^String.Titles.confirm)
                            .frame(width: 100)
                    }
                }
                .disabled(authManager.isValidating)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 200)
        .onReceive(authManager.$shouldDismissSheet) { shouldDismiss in
            if shouldDismiss {
                presentationMode.wrappedValue.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    authManager.shouldDismissSheet = false
                }
            }
        }
    }
}
