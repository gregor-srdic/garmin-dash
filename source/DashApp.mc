import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Background;
import Toybox.Time;

class DashApp extends Application.AppBase {
    // Held so background temperature and setting changes can be pushed
    // straight into the view instead of the view polling for them.
    private var mView as DashView? = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {}

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {}

    //! Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Only register when nothing is registered yet. Calling this on every
        // load replaces the existing registration and restarts the five-minute
        // window, so a field that is reloaded often never reaches its first
        // temporal event. The view deletes the registration outright once it
        // has proved the device reports temperature directly.
        if (
            System has :ServiceDelegate &&
            Background.getTemporalEventRegisteredTime() == null
        ) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
        mView = new DashView();
        return [mView];
    }

    // This is CRITICAL. It tells Garmin which class to wake up.
    function getServiceDelegate() {
        return [new GlobalBackgroundService()];
    }

    // This is triggered when Background.exit(temp) is called
    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data == null) {
            return;
        }
        // Persisted so the value survives a restart, and handed to the view
        // directly so compute() never has to read Storage on the 1 Hz path.
        Storage.setValue("sensorTemperature", data);
        var view = mView;
        if (view != null) {
            view.onSensorTemperature(data as Numeric);
        }
        WatchUi.requestUpdate();
    }

    // FTP, the speed gauge scale and the unit settings are all read once and
    // cached. Without this an FTP edit in Connect IQ did nothing until the
    // data field was recreated.
    function onSettingsChanged() as Void {
        var view = mView;
        if (view != null) {
            view.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}

function getApp() as DashApp {
    return Application.getApp() as DashApp;
}
