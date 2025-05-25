//
//  View+CloudFiles.swift
//  smm-printer-mac
//
//  Created by tpe on 09.09.2024.
//

import SwiftUI

private struct CloudFilesAlerts: ViewModifier {
    
    let showFilesDownloadAlert: Binding<Bool>
    let showFilesDownloadingAlert: Binding<Bool>
    
    let downloadFiles: () -> Void

    func body(content: Content) -> some View {
        content
            .actionAlert(
                title: ^String.Titles.alertsInfoTitle,
                message: ^String.Titles.rootTheFileIsPlacedInCloudTitle,
                actionTitle: ^String.Titles.rootDownloadTitle,
                action: {
                    downloadFiles()
                },
                show: showFilesDownloadAlert
            )
            .infoAlert(
                title: ^String.Titles.alertsInfoTitle,
                message: ^String.Titles.rootDownloadingHasStartedTitle,
                show: showFilesDownloadingAlert
            )
    }
    
}

extension View {
    
    func cloudFilesAlerts(
        showFilesDownloadAlert: Binding<Bool>,
        showFilesDownloadingAlert: Binding<Bool>,
        downloadFiles: @escaping () -> Void
    ) -> some View {
        modifier(
            CloudFilesAlerts(
                showFilesDownloadAlert: showFilesDownloadAlert,
                showFilesDownloadingAlert: showFilesDownloadingAlert,
                downloadFiles: downloadFiles
            )
        )
    }

}

extension View {
    @ViewBuilder
    func conditionalButtonStyle() -> some View {
        if #available(macOS 12.0, *) {
            self.buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}
