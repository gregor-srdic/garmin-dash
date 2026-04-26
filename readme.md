# Dash - Peak Performance Data Field


![Edge 1050](assets/hero.jpg)

<hr>

| ![Edge 1050](assets/Edge1050.png) | ![Edge 1040](assets/Edge1040.png) | ![Edge 1030](assets/Edge1030.png) | ![Edge Explore 2](assets/EdgeExplore2.png) |
|:-:|:-:|:-:|:-:|
| Edge 1050 | Edge 1040 | Edge 1030 | Edge Explore 2 |

Dash is a custom data field for Garmin Edge devices (1050, 1040, 1030, 1030 Plus, 1030 Bontrager, Edge Explore 2), built using Garmin's Connect IQ platform. It provides advanced cycling metrics and background services to enhance your ride experience.

Available in [Garmin Connect IQ Store](https://apps.garmin.com/apps/006a95b6-3619-47ec-a796-496a8dd6a3c9)

## Data fields:

1. Top row:
    - Ambient Temperature (left)
    - Current time (center)
    - Current elevation (right)

2. Speed gauge:
    - Average speed (top left)
    - Max speed (top right)
    - Current speed (center)

3. Middle row:
    - Elapsed time (top)
    - Cadence (bottom left)
    - Di2 current gears (bottom center)
    - Grade (bottom right)

4. Heart rate & Power gauge:
    - Current heart rate between 0 and 200 bpm (left gauge)
    - Current heart rate (center left)
    - Average heart rate (bottom left)
    - Current 3s power (center right)
    - Average 3s power (bottom right)
    - Current power, scaled to 400W or your session max power, whichever is higher (right gauge)

5. Bottom row:
    - Total ascent (left)
    - Total distance (center)
    - Total calories (right)

### No power data?

If you don't have a power meter, the right gauge will display current cadence between 0 and 150 rpm along with current and average cadence.

### Units & appearance

All values automatically adapt to your device settings: speed in km/h or mph, distance in km or miles, elevation and ascent in metres or feet, and temperature in °C or °F. The UI also adapts to your device's light or dark background color setting.

## Installation

If you are downloading this from the Connect IQ Store, installation is automatic. You can also manually copy the file onto the device's hard drive. Here are the simple, step-by-step instructions you can follow:

### Phase 1: Transferring the File to Your Edge
1. Build the project using the Monkey C SDK and Connect IQ tools or download the pre-built PRG file from the releases section of this repository.
2. Plug your Garmin Edge into your PC or Mac using a USB cable.
3. Open the Garmin Drive: Wait a moment for the computer to recognize the device. Open your file explorer (Windows) or Finder (Mac) and open the drive named GARMIN.
4. Navigate to the Apps Folder: Double-click the folder named Garmin, and then open the folder named Apps (GARMIN/Garmin/Apps/).
5. Copy the File: Drag and drop your compiled Dash.prg file directly into this Apps folder.
6. Safely Disconnect: Safely eject the Garmin drive from your computer and unplug the USB cable. The Edge will power on (or reboot) and automatically install your new data field.
7. Add the Dash data field to your activity profile on the device.

### Phase 2: Adding the Data Field to Your Screen

1. On your Edge home screen, go to Settings (the three lines or gear icon) > Activity Profiles.
2. Select the profile you want to use (e.g., Road, Indoor, etc.).
3. Select Data Screens.
4. Choose an existing screen to edit, or click Add New. Dash is a complex data field and you should use it in "1-Field" layout so it takes up the whole screen.
5. Tap the data field on the screen that you want to replace.
6. In the category list that pops up, scroll down and select Connect IQ.
7. Select Dash from the list.
8. Hit the back button to save your changes.

That's it! When you start a ride with that profile, your custom UI will be live on the screen.

## Development
### Prerequisites
- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
- [Monkey C plugin for VS Code](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c)

### Build & Deploy
1. Open the project in VS Code.
2. Use the Monkey C commands to build and deploy:
	- `Monkey C: Build for Device`
	- `Monkey C: Install to Device`

### Project Structure
- `source/` — Main Monkey C source files
- `resources/` — Layouts, drawables, and strings
- `assets/` — Images and icons
- `bin/` — Build outputs

### Main Files
- `DashApp.mc` — Application entry point; registers a background service that runs every 5 minutes to fetch ambient temperature from the device sensor
- `DashView.mc` — UI logic; computes and renders all data fields, calculates real-time grade from GPS altitude and distance (smoothed over 15 m intervals, capped at ±30%)
- `DashBackground.mc` — Background service logic
- `GlobalBackgroundService.mc` — Global background handler

## Contributing
Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License
This project is licensed under the MIT License.