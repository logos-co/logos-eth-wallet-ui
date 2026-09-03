// The receipt-sweep decision, as a table.
//
// The branch that matters here is unreachable from doctests/assert_ui.py: `get_history`
// answers `ok:false` only when the backend module has no context, and the harness has no
// lever to take it away. So the decision is tested directly, and a revert of "a failed read
// leaves the schedule alone" fails rows 5-9 below rather than passing silently.
//
// Run it from this directory, with PKG_CONFIG_PATH pointing at the qtbase this module
// builds against (`<qtbase>/lib/pkgconfig`):
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) \
//       test_sweep_decision.cpp -o /tmp/test_sweep_decision && /tmp/test_sweep_decision

#include <cstdio>

// Qt 6.9's qyieldcpu.h calls __yield() without declaring it, which is an error for a plain
// clang invocation on aarch64. Qt's own CMake build never sees it.
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif

#include "eth_wallet_ui_sweep.h"

namespace {

int failures = 0;

const char *name(SweepVerdict v)
{
    switch (v) {
    case SweepVerdict::Unchanged: return "Unchanged";
    case SweepVerdict::Stop:      return "Stop";
    case SweepVerdict::Run:       return "Run";
    }
    return "?";
}

void check(const char *label, const char *reply, SweepVerdict want)
{
    const SweepVerdict got = sweepVerdict(QString::fromUtf8(reply));
    const bool ok = got == want;
    if (!ok)
        ++failures;
    std::printf("  %s  %s   got=%s want=%s\n", ok ? "PASS" : "FAIL", label, name(got), name(want));
}

} // namespace

int main()
{
    std::printf("a read that SUCCEEDED sets the schedule from the backend's own stop condition\n");
    check("nothing can move again", R"({"ok":true,"stillDue":false})", SweepVerdict::Stop);
    check("a row is still due", R"({"ok":true,"stillDue":true})", SweepVerdict::Run);

    std::printf("an older backend sends no stillDue, so a pending row stands in for it\n");
    check("a pending row",
          R"({"ok":true,"transactions":[{"status":"pending"}]})", SweepVerdict::Run);
    check("no pending row",
          R"({"ok":true,"transactions":[{"status":"confirmed"}]})", SweepVerdict::Stop);

    std::printf("a read that FAILED says nothing — it is not evidence that nothing is due\n");
    check("the backend refused", R"({"ok":false,"error":"module context not ready"})",
          SweepVerdict::Unchanged);
    check("a transport failure arrives empty", "", SweepVerdict::Unchanged);
    check("or not as JSON at all", "<html>502</html>", SweepVerdict::Unchanged);
    std::printf("   the control: a refusal carrying the field must NOT be mined for a stop,\n");
    std::printf("   or every failed read answers Stop and the sweep never runs again\n");
    check("refusal carrying stillDue:false", R"({"ok":false,"stillDue":false})",
          SweepVerdict::Unchanged);
    check("refusal carrying a due row",
          R"({"ok":false,"transactions":[{"status":"pending"}]})", SweepVerdict::Unchanged);

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
