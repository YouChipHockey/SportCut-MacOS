//
//  View+Alerts.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 31.07.2024.
//

import SwiftUI

@available(macOS 12.0, *)
private struct InfoAlert: ViewModifier {
    
    let title: String
    let message: String
    let action: (() -> Void)?
    let show: Binding<Bool>
    
    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: show,
            actions: {
                Button(action: {
                    action?()
                }) {
                    Text(^String.Alerts.alertsOkTitle)
                }
            },
            message: {
                Text(message)
            }
        )
    }
}

@available(macOS 12.0, *)
private struct ActionAlert: ViewModifier {
    
    let title: String
    let message: String
    let cancelTitle: String
    let actionTitle: String
    let cancel: (() -> Void)?
    let action: () -> Void
    let destructive: Bool
    let show: Binding<Bool>
    
    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: show,
            actions: {
                Button(role: destructive ? .destructive : nil, action: action) {
                    Text(actionTitle)
                }
                Button(role: .cancel, action: {
                    cancel?()
                }) {
                    Text(cancelTitle)
                }
            },
            message: {
                Text(message)
            }
        )
    }
}

@available(macOS 12.0, *)
private struct TextFieldAlert: ViewModifier {
    
    let title: String
    let message: String
    let cancelTitle: String
    let actionTitle: String
    let cancel: (() -> Void)?
    let action: (String) -> Void
    let placeholder: String
    let show: Binding<Bool>
    
    @State private var text: String = ""
    
    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: show,
            actions: {
                TextField(placeholder, text: $text)
                Button(action: {
                    action(text)
                }) {
                    Text(actionTitle)
                }
                Button(role: .cancel, action: {
                    cancel?()
                }) {
                    Text(cancelTitle)
                }
            },
            message: {
                Text(message)
            }
        )
    }
}

extension View {
    @ViewBuilder
    func infoAlert(
        title: String,
        message: String,
        action: (() -> Void)? = nil,
        show: Binding<Bool>
    ) -> some View {
        if #available(macOS 12.0, *) {
            self.modifier(InfoAlert(title: title, message: message, action: action, show: show))
        } else {
            self.alert(isPresented: show) {
                Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text(^String.Alerts.alertsOkTitle), action: action)
                )
            }
        }
    }
    
    @ViewBuilder
    func actionAlert(
        title: String,
        message: String,
        cancelTitle: String = ^String.ButtonTitles.cancelButtonTitle,
        actionTitle: String,
        cancel: (() -> Void)? = nil,
        action: @escaping () -> Void,
        destructive: Bool = false,
        show: Binding<Bool>
    ) -> some View {
        if #available(macOS 12.0, *) {
            self.modifier(
                ActionAlert(
                    title: title,
                    message: message,
                    cancelTitle: cancelTitle,
                    actionTitle: actionTitle,
                    cancel: cancel,
                    action: action,
                    destructive: destructive,
                    show: show
                )
            )
        } else {
            self.alert(isPresented: show) {
                Alert(
                    title: Text(title),
                    message: Text(message),
                    primaryButton: .default(Text(actionTitle), action: action),
                    secondaryButton: .cancel(Text(cancelTitle), action: cancel)
                )
            }
        }
    }
    
    @available(macOS 12.0, *)
    @ViewBuilder
    func textFieldAlert(
        title: String,
        message: String,
        cancelTitle: String = ^String.ButtonTitles.cancelButtonTitle,
        actionTitle: String,
        cancel: (() -> Void)? = nil,
        action: @escaping (String) -> Void,
        placeholder: String,
        show: Binding<Bool>
    ) -> some View {
        self.modifier(
            TextFieldAlert(
                title: title,
                message: message,
                cancelTitle: cancelTitle,
                actionTitle: actionTitle,
                cancel: cancel,
                action: action,
                placeholder: placeholder,
                show: show
            )
        )
    }
}
