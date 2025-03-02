//
//  View+Alerts.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 31.07.2024.
//

import SwiftUI

private struct InfoAlert: ViewModifier {
    
    let title: String
    let message: String
    
    let action: (() -> Void)?
    
    let show: Binding<Bool>
    
    func body(content: Content) -> some View {
        content
            .alert(
                title,
                isPresented: show,
                actions: {
                    Button(
                        action: {
                            action?()
                        },
                        label: {
                            Text(^String.Alerts.alertsOkTitle)
                        }
                    )
                },
                message: {
                    Text(message)
                }
            )
    }
    
}

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
        content
            .alert(
                title,
                isPresented: show,
                actions: {
                    Button(
                        role: destructive ? .destructive : nil,
                        action: {
                            action()
                        },
                        label: {
                            Text(actionTitle)
                        }
                    )
                    Button(
                        role: .cancel,
                        action: {
                            cancel?()
                        },
                        label: {
                            Text(cancelTitle)
                        }
                    )
                },
                message: {
                    Text(message)
                }
            )
    }
    
}

private struct TextFieldAlert: ViewModifier {
    
    let title: String
    let message: String
    
    let cancelTitle: String
    let actionTitle: String
    
    let cancel: (() -> Void)?
    let action: (String) -> Void
    
    let placeholder: String
    
    let show: Binding<Bool>
    
    @State private var text = ""
    
    func body(content: Content) -> some View {
        content
            .alert(
                title,
                isPresented: show,
                actions: {
                    TextField(placeholder, text: $text)
                    Button(
                        action: {
                            action(text)
                        },
                        label: {
                            Text(actionTitle)
                        }
                    )
                    Button(
                        role: .cancel,
                        action: {
                            cancel?()
                        },
                        label: {
                            Text(cancelTitle)
                        }
                    )
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
        modifier(
            InfoAlert(
                title: title,
                message: message,
                action: action,
                show: show
            )
        )
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
        modifier(
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
    }
    
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
        modifier(
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
