import Charts
import SwiftData
import SwiftUI

/// 30-day cash-flow projection: the low-point hero (the overdraft guard),
/// a balance line with paydays and bills marked, and the event list.
struct CashFlowCalendarView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query private var accounts: [Account]

    @State private var selectedDate: Date?

    private var projections: [CashFlowProjector.DayProjection] {
        guard let forecast = appEnvironment.pipeline.forecast,
              let profile = appEnvironment.pipeline.profile else { return [] }
        return CashFlowProjector.project(
            accounts: accounts,
            forecast: forecast,
            profile: profile,
            series: appEnvironment.pipeline.recurringSeries
        )
    }

    private var selectedDay: CashFlowProjector.DayProjection? {
        guard let selectedDate else { return nil }
        return projections.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                if projections.isEmpty {
                    EmptyStateView(
                        systemImage: "calendar",
                        title: "Projection is warming up",
                        message: "Cash flow needs a synced forecast — pull to refresh on Home."
                    )
                    .padding(.top, 60)
                } else {
                    lowPointCard
                    balanceChartCard
                    eventsCard
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Cash Flow")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lowPointCard: some View {
        Card(title: "Projected Low Point", systemImage: "arrow.down.to.line") {
            if let low = CashFlowProjector.lowPoint(of: projections) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    AmountText(
                        amount: low.projectedBalance,
                        font: .system(size: 38, weight: .bold),
                        style: AnyShapeStyle(low.projectedBalance < 200 ? AnyShapeStyle(Theme.negative) : AnyShapeStyle(Theme.heroGradient))
                    )
                    Text("on \(low.date.shortDay)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(low.projectedBalance < 200
                    ? "Liquid balance gets tight — consider shifting a discretionary purchase past that date."
                    : "Liquid balance stays comfortable through the next 30 days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var balanceChartCard: some View {
        Card(title: "Next 30 Days", systemImage: "chart.xyaxis.line") {
            Chart {
                ForEach(projections) { day in
                    AreaMark(
                        x: .value("Date", day.date),
                        y: .value("Balance", day.projectedBalance.doubleValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.chartAreaGradient)

                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Balance", day.projectedBalance.doubleValue)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Theme.heroGradient)
                }
                ForEach(projections.filter { $0.paycheck != nil }) { day in
                    PointMark(
                        x: .value("Date", day.date),
                        y: .value("Balance", day.projectedBalance.doubleValue)
                    )
                    .foregroundStyle(Theme.positive)
                    .symbolSize(70)
                }
                ForEach(projections.filter { !$0.bills.isEmpty }) { day in
                    PointMark(
                        x: .value("Date", day.date),
                        y: .value("Balance", day.projectedBalance.doubleValue)
                    )
                    .foregroundStyle(Theme.warning)
                    .symbolSize(40)
                }
                RuleMark(y: .value("Zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Theme.negative.opacity(0.6))
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Decimal(amount).currencyCompact())
                        }
                    }
                }
            }
            .frame(height: 200)
            .sensoryFeedback(.selection, trigger: selectedDay?.id)

            if let selectedDay {
                HStack(spacing: 6) {
                    Text(selectedDay.date.shortDay).font(.caption).foregroundStyle(.secondary)
                    AmountText(amount: selectedDay.projectedBalance, font: .caption.bold(), showCents: false)
                    if let pay = selectedDay.paycheck {
                        Text("· paycheck +\(pay.currency(showCents: false))")
                            .font(.caption)
                            .foregroundStyle(Theme.positive)
                    }
                    if !selectedDay.bills.isEmpty {
                        Text("· \(selectedDay.bills.count) bill\(selectedDay.bills.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Label("Paycheck", systemImage: "circle.fill")
                        .foregroundStyle(Theme.positive)
                    Label("Bill due", systemImage: "circle.fill")
                        .foregroundStyle(Theme.warning)
                    Spacer()
                }
                .font(.caption2)
            }
        }
    }

    private var eventsCard: some View {
        Card(title: "Scheduled", systemImage: "calendar.badge.clock") {
            let eventDays = projections.filter { $0.paycheck != nil || !$0.bills.isEmpty }.prefix(10)
            if eventDays.isEmpty {
                Text("No recurring bills or paychecks detected in the window yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(eventDays)) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.date.shortDay)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let pay = day.paycheck {
                        HStack {
                            Label("Paycheck", systemImage: "arrow.down.circle.fill")
                                .foregroundStyle(Theme.positive)
                            Spacer()
                            AmountText(amount: -pay, font: .subheadline, colorBySign: true)
                        }
                        .font(.subheadline)
                    }
                    ForEach(day.bills) { bill in
                        HStack {
                            Label(bill.merchant, systemImage: bill.category.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            AmountText(amount: bill.amount, font: .subheadline)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
}

#Preview {
    NavigationStack { CashFlowCalendarView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
