import Toybox.Lang;
import Toybox.Math;

// Ride-level power analytics: Normalized Power, IF, TSS, work and W' balance.
//
// Deliberately free of WatchUi and Activity so the arithmetic can be unit
// tested (PowerMetricsTest.mc) and lifted into a separate build later. The
// view feeds it one call per compute() with the timer delta; everything here
// works in one-second steps, which is the rate NP and the W'bal model are
// defined at.
class PowerMetrics {
    // NP's rolling window, in one-second samples.
    private const WINDOW = 30;
    // A timer delta longer than this is a gap (the field was suspended, or
    // recreated mid-ride), not five seconds of riding at the current power.
    private const MAX_STEP_MS = 5000;
    // The SDK has Math.pow but no Math.exp.
    private const E = 2.718281828459045;
    private const W_PRIME_DEFAULT = 20000;

    private var mFtp as Number = 200;
    private var mCp as Number = 200;
    // Divisor in the recovery exponent and in wbalPercent, so never <= 0.
    private var mWPrime as Number = W_PRIME_DEFAULT;

    private var mWindow as Array<Number>;
    private var mWindowIdx as Number = 0;
    private var mWindowFill as Number = 0;
    private var mWindowSum as Number = 0;

    // Sum of the fourth power of each 30 s rolling mean. A long ride takes it
    // to ~1e15, well past what a 32-bit Float's mantissa can add 1e9-sized
    // terms to without losing them, hence Double.
    private var mSum4 as Double = 0.0d;
    private var mNpCount as Number = 0;
    private var mSeconds as Number = 0;
    private var mJoules as Double = 0.0d;

    private var mWbal as Float = W_PRIME_DEFAULT.toFloat();
    private var mMinWbal as Float = W_PRIME_DEFAULT.toFloat();
    private var mLapMinWbal as Float = W_PRIME_DEFAULT.toFloat();

    function initialize() {
        mWindow = new Array<Number>[WINDOW];
        reset();
    }

    // May be called mid-ride from onSettingsChanged. NP, work and the elapsed
    // count are kept; W'bal keeps its absolute value but cannot sit above the
    // new W'. Before the first sample W'bal simply starts full at the new W'.
    function setThresholds(ftp as Number, cp as Number, wPrime as Number) as Void {
        mFtp = ftp > 0 ? ftp : 200;
        mCp = cp > 0 ? cp : mFtp;
        mWPrime = wPrime > 0 ? wPrime : W_PRIME_DEFAULT;
        var full = mWPrime.toFloat();
        if (mSeconds == 0 || mWbal > full) {
            mWbal = full;
        }
        if (mSeconds == 0 || mMinWbal > full) {
            mMinWbal = mWbal;
        }
        if (mSeconds == 0 || mLapMinWbal > full) {
            mLapMinWbal = mWbal;
        }
    }

    // `dtMs` is the activity timer's advance since the previous call, so a
    // paused or stopped timer arrives as 0 and is ignored for free. A null
    // power is a meter dropout: nothing advances, including the NP window, so
    // a dropout neither drags NP towards zero nor counts as recovery time.
    function addSample(power as Number?, dtMs as Number) as Void {
        if (dtMs <= 0 || dtMs > MAX_STEP_MS || power == null) {
            return;
        }
        // compute() runs at ~1 Hz but can be late; a 3 s delta is three
        // seconds of riding, not one.
        var steps = (dtMs + 500) / 1000;
        if (steps < 1) {
            steps = 1;
        }
        for (var i = 0; i < steps; i++) {
            step(power);
        }
    }

    private function step(power as Number) as Void {
        mSeconds++;
        mJoules += power;

        mWindowSum += power - mWindow[mWindowIdx];
        mWindow[mWindowIdx] = power;
        mWindowIdx = (mWindowIdx + 1) % WINDOW;
        if (mWindowFill < WINDOW) {
            mWindowFill++;
        }
        if (mWindowFill == WINDOW) {
            var mean = mWindowSum.toDouble() / WINDOW;
            mSum4 += mean * mean * mean * mean;
            mNpCount++;
        }

        // Skiba's differential W'bal: spend above CP joule for joule, recover
        // below it exponentially towards W', faster the further under CP.
        if (power > mCp) {
            mWbal -= power - mCp;
        } else {
            var recovery = Math.pow(E, -(mCp - power).toFloat() / mWPrime);
            mWbal = mWPrime - (mWPrime - mWbal) * recovery;
        }
        if (mWbal < mMinWbal) {
            mMinWbal = mWbal;
        }
        if (mWbal < mLapMinWbal) {
            mLapMinWbal = mWbal;
        }
    }

    function reset() as Void {
        for (var i = 0; i < WINDOW; i++) {
            mWindow[i] = 0;
        }
        mWindowIdx = 0;
        mWindowFill = 0;
        mWindowSum = 0;
        mSum4 = 0.0d;
        mNpCount = 0;
        mSeconds = 0;
        mJoules = 0.0d;
        mWbal = mWPrime.toFloat();
        mMinWbal = mWbal;
        mLapMinWbal = mWbal;
    }

    function startLap() as Void {
        mLapMinWbal = mWbal;
    }

    function hasSamples() as Boolean {
        return mSeconds > 0;
    }

    // Null until the first 30 s window has filled.
    private function npExact() as Double? {
        if (mNpCount == 0) {
            return null;
        }
        return Math.pow(mSum4 / mNpCount, 0.25).toDouble();
    }

    function np() as Number? {
        var np = npExact();
        return np != null ? roundToNumber(np) : null;
    }

    function intensity() as Float? {
        var np = npExact();
        return np != null ? (np / mFtp).toFloat() : null;
    }

    function tss() as Float? {
        var np = npExact();
        if (np == null) {
            return null;
        }
        return (mSeconds * np * np / (mFtp * mFtp * 3600.0d) * 100.0d).toFloat();
    }

    function kilojoules() as Number {
        return roundToNumber(mJoules / 1000.0d);
    }

    // Joules. Starts at W' and can go negative: that means CP or W' is set
    // too low, which is worth showing rather than hiding at zero.
    function wbal() as Float {
        return mWbal;
    }

    function wbalPercent() as Number {
        return roundToNumber(mWbal * 100.0 / mWPrime);
    }

    function minWbal() as Float {
        return mMinWbal;
    }

    function lapMinWbal() as Float {
        return mLapMinWbal;
    }

    // Half away from zero; toNumber() alone truncates towards it.
    private function roundToNumber(value as Numeric) as Number {
        return value >= 0
            ? (value + 0.5).toNumber()
            : (value - 0.5).toNumber();
    }
}
