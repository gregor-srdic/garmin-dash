import Toybox.Lang;
import Toybox.Test;

// Run No Evil tests for PowerMetrics. Stripped from debug and release builds;
// build with --unit-test and run under monkeydo with /t.

// Helpers live in a module because a (:test) global function must be a test:
// the compiler insists on the Logger parameter and Boolean return. The module
// annotation still keeps them out of debug and release builds.
(:test)
module PowerMetricsTestKit {
    function feed(metrics as PowerMetrics, power as Number?, seconds as Number) as Void {
        for (var i = 0; i < seconds; i++) {
            metrics.addSample(power, 1000);
        }
    }

    function near(actual as Numeric?, expected as Numeric, tolerance as Numeric) as Boolean {
        if (actual == null) {
            return false;
        }
        return (actual - expected).abs() <= tolerance;
    }

    function newMetrics() as PowerMetrics {
        var metrics = new PowerMetrics();
        metrics.setThresholds(200, 250, 20000);
        return metrics;
    }
}

(:test)
function steadyRideMatchesCogganTotals(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 200, 3600);
    logger.debug(
        "np=" + metrics.np() + " if=" + metrics.intensity() +
        " tss=" + metrics.tss() + " kj=" + metrics.kilojoules()
    );
    return metrics.np() == 200 &&
        PowerMetricsTestKit.near(metrics.intensity(), 1.0, 0.01) &&
        PowerMetricsTestKit.near(metrics.tss(), 100.0, 0.5) &&
        metrics.kilojoules() == 720;
}

(:test)
function npIsNullUntilWindowFills(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 200, 29);
    var before = metrics.np() == null &&
        metrics.intensity() == null &&
        metrics.tss() == null;
    PowerMetricsTestKit.feed(metrics, 200, 1);
    return before && metrics.np() == 200;
}

(:test)
function npWeightsSurgesAboveAverage(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 400, 30);
    PowerMetricsTestKit.feed(metrics, 0, 30);
    var np = metrics.np();
    logger.debug("np=" + np);
    return np != null && np > 200;
}

(:test)
function wbalDrainsAboveCpAndRecoversBelow(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 350, 60);
    if (!PowerMetricsTestKit.near(metrics.wbal(), 14000.0, 1.0)) {
        logger.error("after drain wbal=" + metrics.wbal());
        return false;
    }
    var last = metrics.wbal();
    for (var i = 0; i < 300; i++) {
        metrics.addSample(150, 1000);
        var now = metrics.wbal();
        if (now <= last || now > 20000.0) {
            logger.error("step " + i + " wbal=" + now + " last=" + last);
            return false;
        }
        last = now;
    }
    return last > 14000.0 && last < 20000.0;
}

(:test)
function wbalGoesNegativeAndTracksMinimum(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 450, 300);
    logger.debug("wbal=" + metrics.wbal() + " pct=" + metrics.wbalPercent());
    return metrics.wbal() < 0.0 &&
        metrics.minWbal() == metrics.wbal() &&
        metrics.wbalPercent() < 0;
}

(:test)
function pausesAndGapsAreIgnored(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    metrics.addSample(400, 0);
    metrics.addSample(400, -1000);
    metrics.addSample(400, 9000);
    if (metrics.hasSamples() || metrics.kilojoules() != 0) {
        logger.error("pause or gap was counted");
        return false;
    }
    metrics.addSample(300, 3000);
    // Three one-second samples at 300 W, 50 W over CP each.
    return PowerMetricsTestKit.near(metrics.wbal(), 19850.0, 0.5) &&
        metrics.hasSamples();
}

(:test)
function dropoutsChangeNothing(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 300, 10);
    var wbal = metrics.wbal();
    PowerMetricsTestKit.feed(metrics, null, 60);
    // Twenty more seconds fill the window only if the dropouts did not
    // advance it: 10 + 20 = 30.
    PowerMetricsTestKit.feed(metrics, 300, 19);
    var stillEmpty = metrics.np() == null;
    PowerMetricsTestKit.feed(metrics, 300, 1);
    return stillEmpty &&
        metrics.np() == 300 &&
        PowerMetricsTestKit.near(metrics.wbal(), wbal - 50.0 * 20, 0.5);
}

(:test)
function lapMinimumRestartsAtLap(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 450, 30);
    PowerMetricsTestKit.feed(metrics, 100, 60);
    var current = metrics.wbal();
    metrics.startLap();
    return metrics.lapMinWbal() == current &&
        metrics.minWbal() < current;
}

(:test)
function resetRestoresInitialState(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 450, 120);
    metrics.reset();
    return !metrics.hasSamples() &&
        metrics.np() == null &&
        metrics.kilojoules() == 0 &&
        metrics.wbal() == 20000.0 &&
        metrics.minWbal() == 20000.0 &&
        metrics.lapMinWbal() == 20000.0;
}

(:test)
function smallerWPrimeClampsBalanceAndKeepsTotals(logger as Logger) as Boolean {
    var metrics = PowerMetricsTestKit.newMetrics();
    PowerMetricsTestKit.feed(metrics, 200, 60);
    var kj = metrics.kilojoules();
    metrics.setThresholds(200, 250, 15000);
    return metrics.wbal() == 15000.0 &&
        metrics.kilojoules() == kj &&
        metrics.np() == 200;
}
