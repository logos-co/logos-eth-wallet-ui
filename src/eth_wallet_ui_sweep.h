#pragma once

#include <algorithm>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLatin1String>
#include <QString>

/// What a history reply says about the receipt sweep. `Unchanged` is the answer a read that
/// failed gives, and is the whole reason this is three-valued rather than a bool.
enum class SweepVerdict { Unchanged, Stop, Run };

/// Read the sweep schedule out of a `get_history` reply. A read that FAILED is not evidence
/// that nothing is due, so it says nothing: on an idle wallet nothing else would restart the
/// sweep. `stillDue` is the backend's own stop condition; an older backend omits it, so fall
/// back to "something is pending" rather than never sweeping.
inline SweepVerdict sweepVerdict(const QString &reply)
{
    const QJsonObject h = QJsonDocument::fromJson(reply.toUtf8()).object();
    if (!h.value(QStringLiteral("ok")).toBool())
        return SweepVerdict::Unchanged;
    if (h.contains(QStringLiteral("stillDue")))
        return h.value(QStringLiteral("stillDue")).toBool() ? SweepVerdict::Run
                                                            : SweepVerdict::Stop;
    const QJsonArray rows = h.value(QStringLiteral("transactions")).toArray();
    const bool pending = std::any_of(rows.begin(), rows.end(), [](const QJsonValue &v) {
        return v.toObject().value(QStringLiteral("status")).toString() == QLatin1String("pending");
    });
    return pending ? SweepVerdict::Run : SweepVerdict::Stop;
}
