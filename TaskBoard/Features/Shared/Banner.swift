import os
import SwiftUI

private enum Constants {
    enum Layout {
        static let spacing: CGFloat = 12
        static let stackedSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 20
        static let shadowRadius: CGFloat = 4
        static let shadowOffset: CGFloat = 2
        static let hitTarget: CGFloat = 44
        static let font = Font.subheadline
        static let actionPriority = 1.0
    }

    enum Timing {
        static let errorAutoHide = Duration.seconds(4)
        static let undoAutoHide = Duration.seconds(6)
    }

    enum Symbols {
        static let error = "exclamationmark.circle.fill"
        static let dismiss = "xmark"
        static let deleted = "trash"
    }

    enum Strings {
        static let dismiss: LocalizedStringKey = "Dismiss"
        static let undo: LocalizedStringKey = "Undo"
        static let deleted = String(localized: "Task deleted")
    }
}

struct Banner<Action: View>: View {
    let message: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let action: Action

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.Layout.spacing) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(message)
                .font(Constants.Layout.font)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Constants.Layout.spacing) {
                content
                Spacer(minLength: 0)
                action.fixedSize().layoutPriority(Constants.Layout.actionPriority)
            }
            VStack(alignment: .leading, spacing: Constants.Layout.stackedSpacing) {
                content
                action.fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.vertical, Constants.Layout.verticalPadding)
        .background(.regularMaterial, in: .rect(cornerRadius: Constants.Layout.cornerRadius))
        .shadow(radius: Constants.Layout.shadowRadius, y: Constants.Layout.shadowOffset)
    }
}

/// Owns its auto-hide timer, so it keeps running while a screen is pushed over the list.
struct ErrorBannerView: View {
    let banner: ErrorBanner
    let onDismiss: () -> Void

    var body: some View {
        Banner(message: banner.message, systemImage: Constants.Symbols.error, tint: .red) {
            Button(Constants.Strings.dismiss, systemImage: Constants.Symbols.dismiss) {
                Logger.ui.info("Error banner dismissed")
                onDismiss()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: Constants.Layout.hitTarget, minHeight: Constants.Layout.hitTarget)
            .contentShape(.rect)
        }
        .task(id: banner.id) {
            Logger.ui.info("Error banner shown")
            AccessibilityNotification.Announcement(banner.message).post()
            try? await Task.sleep(for: Constants.Timing.errorAutoHide)
            guard !Task.isCancelled else { return }
            onDismiss()
            Logger.ui.info("Error banner auto-hidden")
        }
    }
}

struct UndoBannerView: View {
    let id: TaskItem.ID
    let onUndo: () -> Void
    let onExpire: () -> Void

    var body: some View {
        Banner(message: Constants.Strings.deleted, systemImage: Constants.Symbols.deleted, tint: .secondary) {
            Button(Constants.Strings.undo) {
                Logger.ui.info("Undo tapped")
                onUndo()
            }
            .fontWeight(.semibold)
            .frame(minHeight: Constants.Layout.hitTarget)
            .contentShape(.rect)
        }
        .task(id: id) {
            Logger.ui.info("Undo banner shown")
            AccessibilityNotification.Announcement(Constants.Strings.deleted).post()
            try? await Task.sleep(for: Constants.Timing.undoAutoHide)
            guard !Task.isCancelled else { return }
            onExpire()
            Logger.ui.info("Undo banner auto-hidden")
        }
    }
}

extension View {
    func groupedBackground() -> some View {
        background(Color(.systemGroupedBackground))
    }
}

#if DEBUG
#Preview("Banners") {
    VStack(spacing: Constants.Layout.stackedSpacing) {
        ErrorBannerView(banner: ErrorBanner(message: "Network request failed. Please try again."), onDismiss: {})
        UndoBannerView(id: UUID(), onUndo: {}, onExpire: {})
    }
    .padding()
}

#Preview("Banners, accessibility size") {
    VStack(spacing: Constants.Layout.stackedSpacing) {
        ErrorBannerView(banner: ErrorBanner(message: "Network request failed. Please try again."), onDismiss: {})
        UndoBannerView(id: UUID(), onUndo: {}, onExpire: {})
    }
    .padding()
    .dynamicTypeSize(.accessibility5)
}
#endif
