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
        var temperature = sensorInfo.temperature;
        Background.exit(temperature);
    }
}
