import SwiftUI
import TipKit

/// The period selector with the period total. Shown above the expense list and the report.
struct PeriodBar: View {
    @Environment(ExpenseStore.self) private var store

    private let periodTip = PeriodTip()

    var body: some View {
        let isAll = store.period.type == .all
        HStack(spacing: 4) {
            Button {
                withAnimation { store.showPreviousPeriod() }
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .disabled(isAll)
            .accessibilityLabel("Previous period")

            Menu {
                Picker("Period", selection: Binding(get: { store.period.type },
                                                    set: { store.setPeriodType($0) })) {
                    ForEach(PeriodType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                Divider()
                Button("Current Date", systemImage: "calendar.badge.clock") {
                    withAnimation { store.showCurrentPeriod() }
                }
            } label: {
                Text(store.period.title())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            .popoverTip(periodTip)

            Button {
                withAnimation { store.showNextPeriod() }
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled(isAll)
            .accessibilityLabel("Next period")

            Spacer()

            Text(store.total.formattedCurrency(store.appCurrency))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard !isAll, abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation {
                    if value.translation.width < 0 { store.showNextPeriod() } else { store.showPreviousPeriod() }
                }
            }
        )
    }
}
