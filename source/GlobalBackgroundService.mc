using Toybox.System;
using Toybox.Sensor;
using Toybox.Background;

// Use the (:background) annotation so the system knows to load this in the background
(:background)
class GlobalBackgroundService extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    // THIS is the only place this function works
    function onTemporalEvent() {
        var sensorInfo = Sensor.getInfo();
        // getInfo() can come back null when the background slice runs before
        // the sensor subsystem is up; exit empty rather than fault the service.
        var temperature = sensorInfo != null ? sensorInfo.temperature : null;
        Background.exit(temperature);
    }
}
