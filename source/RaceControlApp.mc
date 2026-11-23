import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class RaceControlApp extends Application.AppBase {

    private var mView as RaceControlView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new RaceControlView();
        mView = view;
        return [view];
    }

    function onStop(state as Dictionary?) as Void {
        var view = mView;
        if (view != null) {
            view.stop();
        }
    }

    // Fired when the theme is changed from Garmin Connect / the Connect IQ app.
    function onSettingsChanged() as Void {
        var view = mView;
        if (view != null) {
            view.loadTheme();
        }
        WatchUi.requestUpdate();
    }

    // On-device theme picker (watch face settings on the watch itself).
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new ThemeMenu(), new ThemeMenuDelegate()];
    }
}
