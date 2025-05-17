//
//  OnboardingView.swift
//  Allium
//
//  Created by Snoolie K (0xilis) on 2025/05/16.
//

import SwiftUI
import UIOnboarding

struct OnboardingView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIOnboardingViewController {
        let configuration = UIOnboardingViewConfiguration(
            appIcon: UIImage.init(),
            firstTitleLine: NSMutableAttributedString(string: "Allium"),
            secondTitleLine: NSMutableAttributedString(string: "🌸 Beautiful Text Editor"),
            features: [
                UIOnboardingFeature(
                    icon: UIImage(systemName: "note.text")!,
                    title: "Smart Notes",
                    description: "Create beautifully formatted notes with markdown support"
                ),
                UIOnboardingFeature(
                    icon: UIImage(systemName: "magnifyingglass")!,
                    title: "Advanced Search",
                    description: "Find and replace text across all your notes"
                ),
                UIOnboardingFeature(
                    icon: UIImage(systemName: "square.and.arrow.up")!,
                    title: "Export Options",
                    description: "Share individual notes or export entire collections"
                )
            ],
            textViewConfiguration: UIOnboardingTextViewConfiguration(
                text: "Version \(Bundle.main.versionNumber)",
                linkTitle: nil,
                link: nil
            ),
            buttonConfiguration: UIOnboardingButtonConfiguration(
                title: "Continue",
                titleColor: .white,
                backgroundColor: .systemBlue
            )
        )
        
        let onboardingController = UIOnboardingViewController(withConfiguration: configuration)
        onboardingController.delegate = context.coordinator
        return onboardingController
    }
    
    func updateUIViewController(_ uiViewController: UIOnboardingViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }
    
    class Coordinator: NSObject, UIOnboardingViewControllerDelegate {
        let dismiss: DismissAction
        
        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }
        
        func didFinishOnboarding(onboardingViewController: UIOnboardingViewController) {
            dismiss()
        }
    }
}

extension Bundle {
    var versionNumber: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
