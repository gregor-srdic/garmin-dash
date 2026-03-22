import Toybox.Application;
import Toybox.Graphics;
import Toybox.WatchUi;
using Toybox.Background;

class Background extends WatchUi.Drawable {
    hidden var mColor as ColorValue;

    function initialize() {
        var dictionary = {
            :identifier => "Background",
        };

        Drawable.initialize(dictionary);

        mColor = Graphics.COLOR_WHITE;
    }

    function setColor(color as ColorValue) as Void {
        mColor = color;
    }

    function draw(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, mColor);
        dc.clear();
    }

    // function onTemporalEvent() {
    //     var info = Sensor.getInfo();
    //     var temp = info != null ? info.temperature : null;
    //     System.println("Hello from the Gauge!");

    //     // Send the temperature back to the main process
    //     Background.exit(temp);
    // }
}
