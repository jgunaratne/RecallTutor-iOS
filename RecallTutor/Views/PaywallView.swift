import StoreKit
import SwiftUI

/// Recall Tutor Pro paywall (ported from podchat's SubscriptionView). Shown
/// when the free built-in-tier allowance (3 lectures) is exhausted. Users can
/// subscribe, restore, or bail out to Settings and add their own API key.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private var manager: SubscriptionManager { .shared }

    /// Invoked when the user chooses "add your own API key" — the presenter
    /// should open Settings.
    var onOpenSettings: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 14) {
                        featureRow(
                            icon: "text.book.closed.fill",
                            title: "Unlimited lectures",
                            detail: "Learn any topic with the built-in tutor — no API key needed"
                        )
                        featureRow(
                            icon: "checkmark.circle.fill",
                            title: "Unlimited quizzes",
                            detail: "Test yourself after every lecture and track mastery"
                        )
                        featureRow(
                            icon: "sparkles",
                            title: "Powered by Gemini",
                            detail: "Fast, high-quality answers funded by your subscription"
                        )
                    }
                    .padding(.horizontal, 20)

                    purchaseSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
            .background(Theme.page.ignoresSafeArea())
            .navigationTitle("Recall Tutor Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await manager.loadProducts() }
        .onChange(of: manager.isPro) {
            if manager.isPro { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Theme.accent)

            Text("You've used your \(SubscriptionManager.freeLectureLimit) free lectures")
                .font(.serifDisplay(size: 24))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Subscribe for unlimited lectures and quizzes, or add your own API key in Settings — that path is always free.")
                .font(.appBody(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appBody(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.appBody(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if let product = manager.products.first {
                Button {
                    Task { await manager.purchase() }
                } label: {
                    VStack(spacing: 2) {
                        Text("Subscribe — \(product.displayPrice)/month")
                            .font(.appBody(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accentStrong, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)

                Text("Auto-renews monthly until cancelled. Cancel anytime in Settings at least 24 hours before the period ends.")
                    .font(.appBody(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            } else if manager.isLoading {
                ProgressView()
                    .padding(.vertical, 16)
            } else {
                Text("Subscription unavailable right now. You can always add your own API key in Settings.")
                    .font(.appBody(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.appBody(size: 13))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await manager.restore() }
            } label: {
                Text("Restore Purchases")
                    .font(.appBody(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Button {
                dismiss()
                onOpenSettings()
            } label: {
                Text("Use my own API key instead")
                    .font(.appBody(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }
}
