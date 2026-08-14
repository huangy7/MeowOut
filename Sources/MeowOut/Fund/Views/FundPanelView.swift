import SwiftUI

public struct FundPanelView: View {
    @ObservedObject var viewModel: FundPanelViewModel
    var appState: AppState?
    var language: AppState.AppLanguage = .system

    @State private var refreshRotation: Double = 0

    public init(viewModel: FundPanelViewModel, appState: AppState? = nil, language: AppState.AppLanguage = .system) {
        self.viewModel = viewModel
        self.appState = appState
        self.language = language
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            if viewModel.funds.isEmpty {
                emptyStateView
            } else {
                summaryBar
                fundList
            }
            footerView
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.10))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("📊")
                .font(.system(size: 15))
            Text(I18n.localized("fund_panel_title", language: language))
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // 隐私模式切换
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.togglePrivacy()
                }
            }) {
                Image(systemName: viewModel.isPrivacyMode ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.isPrivacyMode ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .background(viewModel.isPrivacyMode ? Color.orange.opacity(0.12) : Color.primary.opacity(0.06))
            .cornerRadius(6)
            .help(I18n.localized(viewModel.isPrivacyMode ? "fund_privacy_on" : "fund_privacy_off", language: language))

            // 手动刷新按钮
            Button(action: {
                withAnimation(.easeOut(duration: 0.5)) {
                    refreshRotation += 360
                }
                Task { await viewModel.refresh() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(refreshRotation))
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            .help(I18n.localized("fund_refresh", language: language))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(I18n.localized("fund_daily_gain_title", language: language))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(viewModel.isPrivacyMode ? "****" : formatSignedMoney(viewModel.dailyEstimatedGain))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.isPrivacyMode ? .secondary : gainColor(viewModel.dailyEstimatedGain))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [gainColor(viewModel.dailyEstimatedGain).opacity(0.08), Color.primary.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Fund List

    private var fundList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(viewModel.funds) { fund in
                    fundRow(fund: fund)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 340)
    }

    private func fundRow(fund: FundInfo) -> some View {
        let config = viewModel.config(for: fund.code)
        let shares = config?.shares ?? 0
        let isUp = fund.changePercent > 0
        let isDown = fund.changePercent < 0
        // A股惯例：红涨绿跌
        let trendColor = isUp ? Color.red : (isDown ? Color.green : Color.secondary)

        return HStack(spacing: 8) {
            // 左侧彩色边条 (红涨绿跌)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(trendColor)
                .frame(width: 3, height: 32)

            // 基金信息
            VStack(alignment: .leading, spacing: 2) {
                Text(fund.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(fund.code)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if let gsz = fund.estimatedValue {
                        Text("估值 \(String(format: "%.4f", gsz))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    } else if fund.netValue > 0 {
                        Text("净值 \(String(format: "%.4f", fund.netValue))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // 涨跌幅 + 收益 (红涨绿跌)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPercent(fund.changePercent))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(trendColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(trendColor.opacity(0.12))
                    .cornerRadius(5)

                if shares > 0 {
                    let gain = fund.estimatedGain(shares: shares)
                    Text(viewModel.isPrivacyMode ? "****" : formatSignedMoney(gain))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(viewModel.isPrivacyMode ? .secondary : gainColor(gain))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .help(fund.name)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("📈")
                .font(.system(size: 32))
            Text(I18n.localized("fund_empty_title", language: language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(I18n.localized("fund_empty_subtitle", language: language))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: { openFundSettings() }) {
                Text(I18n.localized("fund_manage", language: language))
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let _ = viewModel.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text(I18n.localized("fund_network_error", language: language))
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else {
                Text("更新于 \(viewModel.formattedUpdateTime)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            Button(action: { openFundSettings() }) {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 9))
                    Text(I18n.localized("fund_manage", language: language))
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .border(width: 0.5, edges: [.top], color: Color.primary.opacity(0.06))
    }

    private func openFundSettings() {
        FundPanelController.shared.hide()
        appState?.settingsNavigationTarget = .fund
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsWindow"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("OpenFundSettings"), object: nil)
    }

    // MARK: - Formatting Helpers

    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "¥" + (formatter.string(from: NSNumber(value: value)) ?? "0")
    }

    private func formatSignedMoney(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return sign + "¥" + (formatter.string(from: NSNumber(value: abs(value))) ?? "0.00")
    }

    private func formatPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + String(format: "%.2f%%", value)
    }

    private func formatSignedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + String(format: "%.2f%%", value)
    }

    // A股惯例：红涨绿跌
    private func gainColor(_ value: Double) -> Color {
        if value > 0 {
            return .red
        } else if value < 0 {
            return .green
        } else {
            return .secondary
        }
    }
}

private extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(
            GeometryReader { geo in
                ForEach(edges, id: \.self) { edge in
                    switch edge {
                    case .top:
                        Rectangle().fill(color).frame(height: width).position(x: geo.size.width / 2, y: width / 2)
                    case .bottom:
                        Rectangle().fill(color).frame(height: width).position(x: geo.size.width / 2, y: geo.size.height - width / 2)
                    case .leading:
                        Rectangle().fill(color).frame(width: width).position(x: width / 2, y: geo.size.height / 2)
                    case .trailing:
                        Rectangle().fill(color).frame(width: width).position(x: geo.size.width - width / 2, y: geo.size.height / 2)
                    }
                }
            }
        )
    }
}
