// The guarded async lane, as a table.
//
// Two lanes are guarded this way — balances+history, and the quote — and for twelve passes they
// were written twice. Every defect named for the data path was still literally present in the
// quote path: no ticket gate on the completion, a lapse timer that cleared the spinner and
// stranded the re-price queued behind it, and a claim taken for exactly as long as the call it
// covered. So the protocol is written ONCE, in src/eth_wallet_ui_guard.h, and this is its table.
//
// Neither leg is reachable from doctests/assert_ui.py: it would have to hold a reply back for
// forty seconds and then deliver it. The decisions are plain claims over a deadline, a ticket
// and a queued flag, so they are tested directly.
//
// Run it from this directory — see doctests/run_tables.sh, or by hand:
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_data_guard.cpp -o /tmp/test_data_guard && /tmp/test_data_guard

#include <cstdio>

// Qt 6.9's qyieldcpu.h calls __yield() without declaring it, which is an error for a plain
// clang invocation on aarch64. Qt's own CMake build never sees it.
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include "eth_wallet_ui_guard.h"

namespace {

int failures = 0;

void expect(const char *label, const char *claim, bool got)
{
    if (!got)
        ++failures;
    std::printf("  %s  %-46s %s\n", got ? "PASS" : "FAIL", label, claim);
}

/// A lane wired the way the backend wires one, with the effects recorded rather than performed.
struct Recorded {
    AsyncLane lane;
    int reruns = 0;
    bool spinner = false;

    explicit Recorded(int budgetMs)
    {
        lane.budgetMs = budgetMs;
        lane.setLoading = [this](bool on) { spinner = on; };
        lane.rerun = [this] { ++reruns; };
    }

    /// What EthWalletUiBackend::handOnLane does, minus the Qt.
    void handOn()
    {
        if (laneFinish(lane) == LaneStep::Rerun)
            lane.rerun();
        else
            lane.setLoading(false);
    }
};

} // namespace

int main()
{
    std::printf("a claim must outlive the calls it covers, or it is not guarding them\n");
    expect("one call under one claim", "the budget is STRICTLY greater",
           guardBudgetMs(1) > kCallBudgetMs);
    expect("two chained legs under one claim", "so is theirs",
           guardBudgetMs(2) > 2 * kCallBudgetMs);
    expect("one call", "is what a quote and a probe each take", kOneCallBudgetMs == guardBudgetMs(1));
    expect("two", "is what balances-then-history takes", kTwoCallBudgetMs == guardBudgetMs(2));
    std::printf("   equal-to is the defect, and the quote lane HAD it: take(kCallBudgetMs)\n");
    std::printf("   against Timeout(kCallBudgetMs) is a guard that lapses at the instant its\n");
    std::printf("   own call times out\n");

    std::printf("\none call at a time, and a second is queued rather than run\n");
    {
        InFlight g;
        quint64 first = 0, second = 0;
        expect("the first read", "takes the slot", g.take(kTwoCallBudgetMs, &first));
        expect("a second read", "is refused while the first is live", !g.take(kTwoCallBudgetMs, &second));
        expect("the live claim", "is the current one", g.isCurrent(first));
        g.release(first);
        expect("its own release", "frees the slot", !g.busy() && g.take(kTwoCallBudgetMs, &second));
        expect("...and the next claim", "is a different ticket", second != first);
    }

    std::printf("\na claim that LAPSED is not a claim: the slot is re-issued under a new ticket\n");
    {
        InFlight g;
        quint64 lapsed = 0, live = 0;
        g.take(0, &lapsed);
        expect("a claim past its deadline", "is not busy", !g.busy());
        expect("the replacement read", "takes the slot", g.take(kTwoCallBudgetMs, &live));

        std::printf("   the reported defect: the lapsed reply then arrives. Both replies name\n");
        std::printf("   the SAME account and chain, so answersFor cannot tell them apart —\n");
        std::printf("   the ticket is the only thing that can\n");
        expect("the lapsed reply", "may not apply its rows", !g.isCurrent(lapsed));
        expect("...nor take the spinner down", "for the read that replaced it", !g.isCurrent(lapsed));
        g.release(lapsed);
        expect("...and releasing on its stale ticket", "cannot free the live claim", g.busy());
        expect("the read still running", "is the current one", g.isCurrent(live));
        g.release(live);
        expect("...and its own release", "does free the slot", !g.busy());
    }

    std::printf("\nthe lane: taking it raises the spinner and queues at most one re-run\n");
    {
        Recorded r(kOneCallBudgetMs);
        quint64 first = 0, second = 0;
        expect("the first call", "takes the lane", takeLane(r.lane, &first));
        expect("a second", "is REFUSED and queued", !takeLane(r.lane, &second) && r.lane.again);
        expect("a third", "coalesces into the same one re-run",
               !takeLane(r.lane, &second) && r.lane.again);
        expect("the live claim", "owns the lane", r.lane.owns(first));
    }

    std::printf("\nhanding the guard on is ONE decision, and the completion and the lapse\n");
    std::printf("timer owe the same answer\n");
    {
        Recorded r(kOneCallBudgetMs);
        quint64 slot = 0;
        takeLane(r.lane, &slot);
        r.lane.setLoading(true);
        r.lane.release(slot);
        r.handOn();
        expect("a completion with nothing queued", "takes the spinner down",
               !r.spinner && r.reruns == 0);
    }
    {
        Recorded r(kOneCallBudgetMs);
        quint64 first = 0, second = 0;
        takeLane(r.lane, &first);
        r.lane.setLoading(true);
        takeLane(r.lane, &second);
        r.lane.release(first);
        r.handOn();
        expect("a completion with one queued", "runs it and LEAVES the spinner up",
               r.reruns == 1 && r.spinner);
        expect("...and the queue", "is drained, not replayed", !r.lane.again);
    }

    std::printf("\nTHE REPORTED DEFECT: the quote lane's lapse timer cleared the spinner and\n");
    std::printf("stranded the re-price. It needs no race — open the dialog, quote(X) takes the\n");
    std::printf("lane, the user types again, quote(Y) is refused and queued, and X's callback\n");
    std::printf("never fires. Y is then never priced: no figures, no spinner, no error\n");
    {
        Recorded r(kOneCallBudgetMs);
        quint64 x = 0, y = 0;
        takeLane(r.lane, &x);
        r.lane.setLoading(true);
        expect("the edit behind the live price", "is queued", !takeLane(r.lane, &y) && r.lane.again);
        // X's callback never fires; the claim simply expires.
        r.lane.release(x);
        r.handOn();
        expect("the lapse timer", "prices Y rather than stranding it", r.reruns == 1);
        expect("...and does not take the spinner down", "a price is still running", r.spinner);
    }

    std::printf("\nand a completion whose claim was re-issued hands nothing on\n");
    {
        Recorded r(kOneCallBudgetMs);
        quint64 lapsed = 0, live = 0;
        r.lane.budgetMs = 0;
        takeLane(r.lane, &lapsed);
        r.lane.budgetMs = kOneCallBudgetMs;
        expect("the replacement price", "takes the lane", takeLane(r.lane, &live));
        expect("the lapsed reply", "may not apply its figures", !r.lane.owns(lapsed));
        expect("...nor hand the guard on", "the price that replaced it is still running",
               r.lane.owns(live));
    }

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
