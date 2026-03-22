import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Background;

class DashApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {}

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {}

    //! Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        if (System has :ServiceDelegate) {
            // Fires every 5 minutes
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
        return [new DashView()];
    }

    // This is CRITICAL. It tells Garmin which class to wake up.
    function getServiceDelegate() {
        return [new GlobalBackgroundService()];
    }

    // This is triggered when Background.exit(temp) is called
    function onBackgroundData(data) {
        if (data != null) {
            Storage.setValue("sensorTemperature", data);
            WatchUi.requestUpdate();
        }
    }
}

function getApp() as DashApp {
    return Application.getApp() as DashApp;
}
