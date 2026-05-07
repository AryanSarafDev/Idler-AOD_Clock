# Idler - Always-On Display Clock

Idler is a Flutter-based always-on display (AOD) app for Android devices that shows a customizable clock with notification support, media playback information, and minimal power consumption.

## Features

- **Always-On Clock Display**: Shows time, date, and current information on the lock screen or home screen without draining battery
- **Notification Monitoring**: Displays recent notifications from all installed apps (excluding media notifications)
- **Media Player Integration**: Shows currently playing track, artist, album art, and playback controls
- **Inactive Display**: Clock with automatic dimming after inactivity
- **Gesture Controls**: Swipe navigation between clock and notifications screens
- **Screen Wake Lock**: Keeps the display on when needed

<img width="1600" height="720" alt="image" src="https://github.com/user-attachments/assets/5e069b9d-72df-4e6d-886a-c59bfccc6260" />

<img width="2400" height="1080" alt="image" src="https://github.com/user-attachments/assets/8dd01e4b-7f64-4706-8727-3839339d0f46" />


## Requirements

- **Android 7.0+** (API level 24+)
- **Notification Access Permission**: Required to monitor and display notifications

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd Idler
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Connect your Android device or launch an emulator

4. Run the app:
   ```bash
   flutter run
   ```

5. **Grant Permissions**:
   - Open Settings → Apps → Special app access → Notification listeners
   - Enable "Idler" to allow notification access

## Usage

### Main Screen
- Displays current time, date, and weather/media information
- Swipe left to view recent notifications
- Tap to wake up the screen if dimmed

### Notifications Screen
- Shows the 5 most recent notifications from all apps
- **Swipe left on a notification** to dismiss it
- **Tap on a notification** to view full details and open the app
- Tap **"Open Settings"** if notifications are not appearing
- Tap **"Retry"** to check listener connection status

### Media Playback
- Displays album art, track title, and artist name
- **Previous/Next/Play-Pause buttons** for media control
- Works with Spotify, YouTube Music, and other media players
- Requires notification access to be enabled

## Troubleshooting

### Notifications Not Showing
1. **Check Permission**: Settings → Apps → Special app access → Notification listeners → Ensure "Idler" is enabled
2. **Listener Not Connected**: If you see "Notification listener not connected":
   - Tap "Open Settings" and toggle Idler off then back on
   - Tap "Retry" in the app
   - Restart the device
3. **After App Restart**: The app automatically resets the listener connection on startup, but if notifications still don't appear:
   - Manually re-enable notification access in Settings
   - Force-close and reopen the app

### Media Information Not Showing
- Ensure a media player app (Spotify, YouTube Music, etc.) is open
- Enable notification access for the app in Settings
- Some media players may not expose playback information

### Display Always On
- The app enables a wake lock to keep the display on
- To disable, force-close the app or navigate away from the app

## Architecture

The app follows a layered architecture:
- **UI Layer** (`lib/main.dart`): Flutter widgets for display and user interaction
- **Logic Layer**: Media controller integration and state management
- **Data Layer**: Native Android integration via method channels
- **Native Layer** (`android/`): Kotlin for notification listening and media session access

### Key Components
- **NotificationListener.kt**: Android service that captures system notifications
- **MainActivity.kt**: Bridges Flutter and native Android functionality via method channels
- **NotificationListener Binding**: Automatically resets on app startup to ensure consistent operation

## Development

### Project Structure
```
.
├── android/              # Android native code
│   ├── app/
│   │   └── src/main/
│   │       ├── kotlin/
│   │       │   └── com/example/idler/
│   │       │       ├── MainActivity.kt
│   │       └── NotificationListener.kt
│   │       └── AndroidManifest.xml
│   └── build.gradle.kts
├── ios/                  # iOS configuration
├── lib/
│   └── main.dart        # Main Flutter app
├── pubspec.yaml         # Dependencies
└── README.md           # This file
```

### Building

**Debug Build**:
```bash
flutter build apk --debug
```

**Release Build**:
```bash
flutter build apk --release
```

**Install to Device**:
```bash
flutter install
```

## Permissions

The app requests the following permissions:
- `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`: To receive system notifications
- `android.permission.POST_NOTIFICATIONS`: To display app notifications (if any)

## Known Issues

- Notifications may stop updating after device reboot; the app now automatically resets the listener connection on startup
- Media player information may lag by a few seconds
- Some custom ROM devices may have stricter battery optimization policies that prevent notifications

## Future Improvements

- Support for additional notification customization
- Dark/Light theme options
- Custom color schemes
- Gesture-based app shortcuts
- Integration with smart home systems

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss your proposed changes.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Enable native logs: `adb logcat -s NotificationListener`
3. Open an issue with detailed steps to reproduce

---

**Made with ❤️ using Flutter**
