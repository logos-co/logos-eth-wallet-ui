#pragma once

#include <functional>

#include <QDeadlineTimer>

/// How long a call may be outstanding before its callback is treated as LOST rather than
/// late. It matches the deadline handed to the transport, so there is one number, not two.
constexpr int kCallBudgetMs = 20000;
/// STRICTLY greater than the calls it covers: a guard lapsing at the instant its own calls
/// time out is not guarding them, and the reply landing on that boundary is the one that
/// applies forty-second-old rows.
constexpr int kGuardSlackMs = 1000;

/// The budget a claim covering `legs` chained calls must hold, plus the dispatch between them.
/// One number for both lanes, so a lane cannot be written with no margin at all.
constexpr int guardBudgetMs(int legs) { return legs * kCallBudgetMs + kGuardSlackMs; }

/// Every claim in this view is one of these two. Nothing is ever taken for kCallBudgetMs
/// itself: balances then history is two chained calls, a quote or a probe is one.
constexpr int kOneCallBudgetMs = guardBudgetMs(1);
constexpr int kTwoCallBudgetMs = guardBudgetMs(2);

/// An in-flight claim that EXPIRES. An async callback can simply never fire, so a guard
/// derived from one is a deadline, never a latch.
class InFlight
{
public:
    /// True while a call taken out inside its budget has neither answered nor expired.
    bool busy() const { return m_held && !m_deadline.hasExpired(); }
    /// Take the slot, or refuse it to a second call while the first is still live. The
    /// ticket identifies THIS claim, so a completion arriving after its deadline lapsed
    /// cannot free the call that replaced it.
    bool take(int budgetMs, quint64 *ticket)
    {
        if (busy())
            return false;
        m_held = true;
        m_deadline.setRemainingTime(budgetMs);
        *ticket = ++m_ticket;
        return true;
    }
    void release(quint64 ticket)
    {
        if (ticket == m_ticket)
            m_held = false;
    }
    /// Whether `ticket` is still the claim in force. A completion whose claim was re-issued may
    /// not apply its rows, drain the re-read behind it, or clear the spinner for its successor.
    bool isCurrent(quint64 ticket) const { return ticket == m_ticket; }

private:
    bool m_held = false;
    quint64 m_ticket = 0;
    QDeadlineTimer m_deadline;
};

/// The spinner a claim raises and lowers. Named, so a signature carrying one stays greppable.
using SetLoading = std::function<void(bool)>;

/// One guarded asynchronous lane: at most one call live, exactly one re-run coalesced behind
/// it, and a claim that EXPIRES so a callback that never fires cannot wedge it shut. Both
/// async paths in this view share this, so a fix cannot land on one and miss its twin.
struct AsyncLane {
    InFlight flight;
    /// A re-run asked for while one was live. Queued rather than dropped: a keystroke or a
    /// chain switch arriving mid-call must still be priced or re-read.
    bool again = false;
    int budgetMs = 0;
    /// The spinner this lane raises, and what running the queued re-run means. Wired once, so
    /// the shared helpers below can hand the guard on without knowing which lane they hold.
    SetLoading setLoading;
    std::function<void()> rerun;

    /// True only for the claim in force: a lapsed reply may neither apply its payload nor hand
    /// the guard on. Two replies can name the same account and chain, so nothing else separates
    /// them.
    bool owns(quint64 ticket) const { return flight.isCurrent(ticket); }
    void release(quint64 ticket) { flight.release(ticket); }
    bool busy() const { return flight.busy(); }
};

/// Take the lane, or coalesce behind the live call.
inline bool takeLane(AsyncLane &lane, quint64 *ticket)
{
    if (lane.flight.take(lane.budgetMs, ticket))
        return true;
    lane.again = true;
    return false;
}

/// Handing the guard on means exactly one of two things, and never both.
enum class LaneStep { Idle, Rerun };

/// Drain the re-run queued behind this claim, if there is one. The completion and the lapse
/// timer owe the same answer, which is why it is written once.
inline LaneStep laneFinish(AsyncLane &lane)
{
    if (!lane.again)
        return LaneStep::Idle;
    lane.again = false;
    return LaneStep::Rerun;
}
