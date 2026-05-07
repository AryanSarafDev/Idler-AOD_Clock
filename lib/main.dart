import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_media_controller/flutter_media_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlwaysOnDisplayApp());
}

class AlwaysOnDisplayApp extends StatelessWidget {
  const AlwaysOnDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Idler Clock',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const AlwaysOnDisplayScreen(),
    );
  }
}

class AlwaysOnDisplayScreen extends StatefulWidget {
  const AlwaysOnDisplayScreen({super.key});

  @override
  State<AlwaysOnDisplayScreen> createState() => _AlwaysOnDisplayScreenState();
}

class _AlwaysOnDisplayScreenState extends State<AlwaysOnDisplayScreen> {
  late PageController _pageController;
  Timer? _dimTimer;
  Timer? _mediaTimer;
  Timer? _notificationTimer;
  bool _isDimmed = false;
  bool _isLoadingMedia = false;
  bool _hasMediaInfo = false;
  bool _permissionRequested = false;
  int _mediaPositionMs = 0;
  int _mediaDurationMs = 0;
  String _trackTitle = 'No active media';
  String _artistName = 'Open Spotify or another app';
  String _thumbnailBase64 = '';
  bool _isPlaying = false;

  // Notifications
  bool _isNotificationAccessGranted = true;
  bool _isNotificationListenerConnected = false;
  List<Map<dynamic, dynamic>> _recentNotifications = [];
  static const _notificationChannel = MethodChannel(
    'com.example.idler/notifications',
  );

  static const Duration _dimAfter = Duration(seconds: 5);
  static const Duration _mediaRefreshInterval = Duration(seconds: 4);
  static const Duration _notificationRefreshInterval = Duration(seconds: 3);

  bool get _supportsMediaControls =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _scheduleDimTimer();

    if (_supportsMediaControls) {
      _refreshMediaInfo(silent: true);
      _mediaTimer = Timer.periodic(_mediaRefreshInterval, (_) {
        _refreshMediaInfo(silent: true);
      });

      // Reset notification listener binding to ensure it reconnects
      _resetNotificationListener();

      // Start fetching notifications
      _checkNotificationPermission();
      _fetchNotifications(silent: true);
      _notificationTimer = Timer.periodic(_notificationRefreshInterval, (_) {
        _checkNotificationPermission();
        _fetchNotifications(silent: true);
      });
    }
  }

  Future<void> _checkNotificationPermission() async {
    try {
      final bool? isGranted = await _notificationChannel.invokeMethod<bool>(
        'isNotificationServiceEnabled',
      );
      // Also check whether the native NotificationListener instance is connected
      final bool? isListenerConnected = await _notificationChannel.invokeMethod<bool>('isNotificationListenerConnected');
      if (mounted && isGranted != null && isGranted != _isNotificationAccessGranted) {
        setState(() {
          _isNotificationAccessGranted = isGranted;
        });
      }
      if (mounted && isListenerConnected != null && isListenerConnected != _isNotificationListenerConnected) {
        setState(() {
          _isNotificationListenerConnected = isListenerConnected;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _dimTimer?.cancel();
    _mediaTimer?.cancel();
    _notificationTimer?.cancel();
    _pageController.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openAssistant() async {
    await HapticFeedback.mediumImpact();
    _handleInteraction(); // Wake up
    try {
      await _notificationChannel.invokeMethod('openAssistant');
    } catch (e) {
      debugPrint('Error opening assistant: $e');
    }
  }

  Future<void> _resetNotificationListener() async {
    try {
      await _notificationChannel.invokeMethod('resetNotificationListener');
    } catch (e) {
      debugPrint('Error resetting notification listener: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          children: [
            // Page 0: Main clock screen with separate clock timer
            _ClockDisplay(
              isDimmed: _isDimmed,
              isLoadingMedia: _isLoadingMedia,
              hasMediaInfo: _hasMediaInfo,
              trackTitle: _trackTitle,
              artistName: _artistName,
              thumbnailBase64: _thumbnailBase64,
              isPlaying: _isPlaying,
              progressPositionMs: _mediaPositionMs,
              progressDurationMs: _mediaDurationMs,
              onEnableAccess: _requestMediaPermissions,
              onRefresh: () => _refreshMediaInfo(),
              onPrevious: _previousTrack,
              onPlayPause: _togglePlayPause,
              onNext: _nextTrack,
              supportsMediaControls: _supportsMediaControls,
              recentNotifications: _recentNotifications,
              onTap: _handleInteraction,
              onOpenAssistant: _openAssistant,
            ),
            // Page 1: Full notifications screen
            _buildNotificationsScreen(
              context,
              MediaQuery.of(context).orientation,
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildNotificationsScreen(
    BuildContext context,
    Orientation orientation,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleInteraction,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(
                color: const Color(0xFF0A0A0A),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Notifications',
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          IconButton(
                            onPressed: _openNotificationSettings,
                            icon: const Icon(
                              Icons.settings,
                              size: 20,
                              color: Color(0xFF9A9A9A),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // Divider
                    Container(height: 1, color: const Color(0x15FFFFFF)),
                    // Notifications list
                    Expanded(
                      child: (() {
                        if (!_isNotificationAccessGranted) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Notification access disabled',
                                  style: TextStyle(
                                    color: Color(0xFF6A6A6A),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _openNotificationSettings,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0x33FFFFFF),
                                    ),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Enable Access'),
                                ),
                              ],
                            ),
                          );
                        }

                        if (!_isNotificationListenerConnected) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Notification listener not connected',
                                  style: TextStyle(
                                    color: Color(0xFF6A6A6A),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    OutlinedButton(
                                      onPressed: _openNotificationSettings,
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Color(0x33FFFFFF),
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Open Settings'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () async {
                                        await _checkNotificationPermission();
                                        await _fetchNotifications();
                                      },
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        if (_recentNotifications.isEmpty) {
                          return Center(
                            child: Text(
                              'No notifications',
                              style: const TextStyle(
                                color: Color(0xFF6A6A6A),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: _recentNotifications.length,
                          separatorBuilder: (context, index) => Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            color: const Color(0x10FFFFFF),
                          ),
                          itemBuilder: (context, index) {
                            final notification = _recentNotifications[index];
                            final key = notification['key'] ?? '';
                            final pkg = notification['package'] ?? '';
                            final title = notification['title'] ?? 'Notification';
                            final body = notification['body'] ?? '';
                            final iconBase64 = notification['iconBase64'] ?? '';

                            return _buildNotificationListItem(
                              context,
                              key,
                              pkg,
                              title,
                              body,
                              iconBase64,
                            );
                          },
                        );
                      })(),
                    ),
                  ],
                ),
              ),
              // Swipe hint at bottom
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Swipe right to return',
                    style: const TextStyle(
                      color: Color(0xFF5A5A5A),
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotificationListItem(
    BuildContext context,
    String key,
    String pkg,
    String title,
    String body,
    String iconBase64,
  ) {
    return Dismissible(
      key: ValueKey(key.isNotEmpty ? key : '$pkg|$title'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) async {
        await _dismissNotification(key, pkg, title);
      },
      background: Container(
        color: const Color(0xFFD32F2F),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white, size: 20),
      ),
      child: InkWell(
        onTap: () async {
          await showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF060606),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            builder: (ctx) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF7F7F7),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFFBDBDBD),
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _openApp(pkg);
                          },
                          child: const Text('Open App'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _dismissNotification(key, pkg, title);
                          },
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _notificationAppIcon(iconBase64, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFA8A8A8),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationAppIcon(String iconBase64, {double size = 28}) {
    if (iconBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(iconBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.2),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        // Fall back to the default icon.
      }
    }

    return Icon(
      Icons.notifications,
      size: size * 0.58,
      color: const Color(0xFF6A9CFF),
    );
  }

  void _handleInteraction() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isDimmed = false;
    });

    _scheduleDimTimer();
  }

  void _scheduleDimTimer() {
    _dimTimer?.cancel();
    _dimTimer = Timer(_dimAfter, () {
      if (mounted) {
        setState(() {
          _isDimmed = true;
        });
      }
    });
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _notificationChannel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  Future<void> _openApp(String packageName) async {
    try {
      await _notificationChannel.invokeMethod('openApp', {
        'package': packageName,
      });
    } catch (_) {}
  }

  Future<void> _dismissNotification(
    String key,
    String packageName,
    String title,
  ) async {
    try {
      final removed = await _notificationChannel.invokeMethod<bool>(
        'dismissNotification',
        {
          'key': key,
          'package': packageName,
          'title': title,
        },
      );
      if (removed == true) {
        setState(() {
          _recentNotifications.removeWhere(
            (n) => key.isNotEmpty
                ? n['key'] == key
                : n['package'] == packageName && n['title'] == title,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _requestMediaPermissions() async {
    if (!_supportsMediaControls) {
      return;
    }

    _permissionRequested = true;
    await FlutterMediaController.requestPermissions();
    await _refreshMediaInfo();
  }

  Future<void> _refreshMediaInfo({bool silent = false}) async {
    if (!_supportsMediaControls) {
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoadingMedia = true;
      });
    }

    try {
      final mediaInfo = await FlutterMediaController.getCurrentMediaInfo();
      final mediaProgress = await _notificationChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getMediaProgress',
      );
      if (!mounted) {
        return;
      }

      final track = mediaInfo.track.trim();
      final artist = mediaInfo.artist.trim();
      final hasMedia =
          mediaInfo.isPlaying ||
          (track.isNotEmpty && track != 'No track playing') ||
          (artist.isNotEmpty && artist != 'Unknown artist');

      final newPositionMs = (mediaProgress?['positionMs'] as num?)?.toInt() ?? 0;
      final newDurationMs = (mediaProgress?['durationMs'] as num?)?.toInt() ?? 0;

      if (_hasMediaInfo != hasMedia ||
          _trackTitle != (hasMedia ? track : 'No active media') ||
          _artistName != (hasMedia ? artist : (_permissionRequested ? 'Enable notification access, then refresh' : 'Open Spotify or another app')) ||
          _thumbnailBase64 != mediaInfo.thumbnailUrl ||
          _isPlaying != mediaInfo.isPlaying ||
          _mediaPositionMs != newPositionMs ||
          _mediaDurationMs != newDurationMs) {
        setState(() {
          _hasMediaInfo = hasMedia;
          _trackTitle = hasMedia ? track : 'No active media';
          _artistName = hasMedia
              ? artist
              : (_permissionRequested
                    ? 'Enable notification access, then refresh'
                    : 'Open Spotify or another app');
          _thumbnailBase64 = mediaInfo.thumbnailUrl;
          _isPlaying = mediaInfo.isPlaying;
          _mediaPositionMs = newPositionMs;
          _mediaDurationMs = newDurationMs;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      final fallbackArtist = _permissionRequested
          ? 'Enable notification access, then refresh'
          : 'Open Spotify or another app';

      if (_hasMediaInfo != false ||
          _trackTitle != 'No active media' ||
          _artistName != fallbackArtist ||
          _thumbnailBase64 != '' ||
          _isPlaying != false ||
          _mediaPositionMs != 0 ||
          _mediaDurationMs != 0) {
        setState(() {
          _hasMediaInfo = false;
          _trackTitle = 'No active media';
          _artistName = fallbackArtist;
          _thumbnailBase64 = '';
          _isPlaying = false;
          _mediaPositionMs = 0;
          _mediaDurationMs = 0;
        });
      }
    } finally {
      if (!silent && mounted) {
        setState(() {
          _isLoadingMedia = false;
        });
      }
    }
  }

  Future<void> _previousTrack() async {
    if (!_supportsMediaControls) {
      return;
    }

    await FlutterMediaController.previousTrack();
    await _refreshMediaInfo(silent: true);
  }

  Future<void> _togglePlayPause() async {
    if (!_supportsMediaControls) {
      return;
    }

    await FlutterMediaController.togglePlayPause();
    await _refreshMediaInfo(silent: true);
  }

  Future<void> _nextTrack() async {
    if (!_supportsMediaControls) {
      return;
    }

    await FlutterMediaController.nextTrack();
    await _refreshMediaInfo(silent: true);
  }

  Future<void> _fetchNotifications({bool silent = false}) async {
    if (!_supportsMediaControls) {
      return;
    }

    try {
      final result = await _notificationChannel.invokeMethod<List<dynamic>>(
        'getActiveNotifications',
      );

      if (!mounted) {
        return;
      }

      final notifications = (result ?? []).cast<Map<dynamic, dynamic>>();
      final processedNotifications = notifications
          .map(
            (n) => {
              'key': (n['key'] ?? '').toString(),
              'package': (n['package'] ?? '').toString(),
              'title': (n['title'] ?? 'Notification').toString(),
              'body': (n['body'] ?? '').toString(),
              'iconBase64': (n['iconBase64'] ?? '').toString(),
            },
          )
          .toList();

      if (mounted && !listEquals(_recentNotifications, processedNotifications)) {
        setState(() {
          _recentNotifications = processedNotifications;
        });
      }
    } catch (e) {
      // Silently fail - notifications may not have permission
    }
  }
}

class _PrettyDateCard extends StatelessWidget {
  const _PrettyDateCard({
    required this.weekdayText,
    required this.monthText,
    required this.dayText,
    required this.yearText,
    required this.width,
    required this.fontSize,
  });

  final String weekdayText;
  final String monthText;
  final String dayText;
  final String yearText;
  final double width;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF050505),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x22FFFFFF), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekdayText.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFB7B7B7),
                  fontSize: fontSize * 0.46,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    monthText,
                    style: TextStyle(
                      color: const Color(0xFFF2F2F2),
                      fontSize: fontSize * 0.72,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dayText,
                    style: TextStyle(
                      color: const Color(0xFFF7F7F7),
                      fontSize: fontSize * 1.15,
                      fontWeight: FontWeight.w700,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    yearText,
                    style: TextStyle(
                      color: const Color(0xFF9E9E9E),
                      fontSize: fontSize * 0.58,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigitalTimeFace extends StatelessWidget {
  const _DigitalTimeFace({
    required this.hourText,
    required this.minuteText,
    required this.fontSize,
    required this.width,
  });

  final String hourText;
  final String minuteText;
  final double fontSize;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF020202),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0x22FFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _WatchDigitBlock(text: hourText, fontSize: fontSize),
              const SizedBox(width: 10),
              _Colon(fontSize: fontSize * 0.95),
              const SizedBox(width: 10),
              _WatchDigitBlock(text: minuteText, fontSize: fontSize),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchDigitBlock extends StatelessWidget {
  const _WatchDigitBlock({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fontSize * 1.28,
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: const Color(0xFFF8F8F8),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: const [
            Shadow(color: Color(0x33000000), blurRadius: 4),
            Shadow(color: Color(0x11000000), blurRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      ':',
      style: TextStyle(
        color: const Color(0xFFE0E0E0),
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1,
        shadows: const [
          Shadow(color: Color(0x22000000), blurRadius: 4),
          Shadow(color: Color(0x11000000), blurRadius: 10),
        ],
      ),
    );
  }
}

class _SpotifyStyleMediaBar extends StatelessWidget {
  const _SpotifyStyleMediaBar({
    required this.isLoading,
    required this.hasMediaInfo,
    required this.trackTitle,
    required this.artistName,
    required this.thumbnailBase64,
    required this.isPlaying,
    required this.progressPositionMs,
    required this.progressDurationMs,
    required this.onEnableAccess,
    required this.onRefresh,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.isLandscape,
  });

  final bool isLoading;
  final bool hasMediaInfo;
  final String trackTitle;
  final String artistName;
  final String thumbnailBase64;
  final bool isPlaying;
  final int progressPositionMs;
  final int progressDurationMs;
  final Future<void> Function() onEnableAccess;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final albumSize = isLandscape ? 62.0 : 50.0;
    final prevNextIconSize = isLandscape ? 32.0 : 20.0;
    final playIconSize = isLandscape ? 36.0 : 28.0;
    final titleFontSize = isLandscape ? 15.0 : 13.0;
    final artistFontSize = isLandscape ? 13.0 : 11.0;
    final padH = isLandscape ? 14.0 : 10.0;
    final padV = isLandscape ? 8.0 : 6.0;
    final canShowProgress = progressDurationMs > 0;

    Widget albumArt;
    if (thumbnailBase64.isNotEmpty) {
      try {
        final imageBytes = base64Decode(
          thumbnailBase64.replaceAll(RegExp(r'\s'), ''),
        );
        albumArt = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(imageBytes, fit: BoxFit.cover),
        );
      } catch (_) {
        albumArt = _placeholderArt(isLandscape);
      }
    } else {
      albumArt = _placeholderArt(isLandscape);
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border(
          top: BorderSide(color: const Color(0x22FFFFFF), width: 1),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: !hasMediaInfo && !isLoading
            ? Center(
                child: SizedBox(
                  height: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            'Enable notification access to see media',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFF9A9A9A),
                              fontSize: isLandscape ? 14.0 : 13.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: isLandscape ? 48 : 40,
                        child: OutlinedButton(
                          onPressed: onEnableAccess,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF2F2F2),
                            side: const BorderSide(color: Color(0x22FFFFFF)),
                            padding: EdgeInsets.symmetric(
                              horizontal: isLandscape ? 18 : 16,
                            ),
                          ),
                          child: Text(
                            'Enable',
                            style: TextStyle(fontSize: isLandscape ? 13 : 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (canShowProgress) ...[
                    _MediaProgressStrip(
                      positionMs: progressPositionMs,
                      durationMs: progressDurationMs,
                      isPlaying: isPlaying,
                    ),
                    SizedBox(height: isLandscape ? 8 : 6),
                  ],
                  Row(
                    children: [
                      // Album thumbnail
                      SizedBox(
                        width: albumSize,
                        height: albumSize,
                        child: albumArt,
                      ),
                      SizedBox(width: isLandscape ? 16 : 8),

                      // Track info (left side)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trackTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFFF7F7F7),
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: isLandscape ? 4 : 2),
                            Text(
                              artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFF9A9A9A),
                                fontSize: artistFontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: isLandscape ? 10 : 6),

                      // Transport controls (right side)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MediaButton(
                            icon: Icons.skip_previous_rounded,
                            onPressed: () => onPrevious(),
                            enabled: hasMediaInfo,
                            size: prevNextIconSize,
                          ),
                          SizedBox(width: isLandscape ? 4 : 2),
                          _MediaButton(
                            icon: isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            onPressed: () => onPlayPause(),
                            enabled: hasMediaInfo,
                            isPrimary: true,
                            size: playIconSize,
                          ),
                          SizedBox(width: isLandscape ? 4 : 2),
                          _MediaButton(
                            icon: Icons.skip_next_rounded,
                            onPressed: () => onNext(),
                            enabled: hasMediaInfo,
                            size: prevNextIconSize,
                          ),
                          SizedBox(width: isLandscape ? 4 : 2),
                          if (isLoading)
                            SizedBox(
                              width: playIconSize,
                              height: playIconSize,
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else
                            _MediaButton(
                              icon: Icons.refresh_rounded,
                              onPressed: () => onRefresh(),
                              enabled: true,
                              size: prevNextIconSize,
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _placeholderArt(bool isLandscape) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Icon(
        Icons.graphic_eq,
        color: const Color(0xFFBDBDBD),
        size: isLandscape ? 28 : 22,
      ),
    );
  }
}

class _MediaProgressStrip extends StatefulWidget {
  const _MediaProgressStrip({
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
  });

  final int positionMs;
  final int durationMs;
  final bool isPlaying;

  @override
  State<_MediaProgressStrip> createState() => _MediaProgressStripState();
}

class _MediaProgressStripState extends State<_MediaProgressStrip> {
  Timer? _timer;
  late int _currentPositionMs;

  @override
  void initState() {
    super.initState();
    _currentPositionMs = widget.positionMs;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _MediaProgressStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionMs != widget.positionMs ||
        oldWidget.durationMs != widget.durationMs ||
        oldWidget.isPlaying != widget.isPlaying) {
      _currentPositionMs = widget.positionMs;
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.isPlaying || widget.durationMs <= 0) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      final newPositionMs = (_currentPositionMs + 1000).clamp(0, widget.durationMs);
      if (newPositionMs != _currentPositionMs) {
        setState(() {
          _currentPositionMs = newPositionMs;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.durationMs > 0
        ? (_currentPositionMs / widget.durationMs).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: widget.durationMs > 0 ? progress : null,
            minHeight: 4,
            backgroundColor: const Color(0x1FFFFFFF),
            valueColor: const AlwaysStoppedAnimation<Color>(Color.fromARGB(68, 255, 255, 255)),
          ),
        ),
  
      ],
    );
  }

 
}

class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.icon,
    required this.onPressed,
    required this.enabled,
    this.isPrimary = false,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool isPrimary;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? const Color(0x12FFFFFF) : const Color(0x0AFFFFFF),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          icon,
          color: enabled ? const Color(0xFFF2F2F2) : const Color(0xFF5E5E5E),
        ),
        iconSize: size,
        constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
      ),
    );
  }
}

// Removed _NotificationsSection - now using separate screen instead

// Clock display widget with its own timer - prevents media bar from rebuilding
class _ClockDisplay extends StatefulWidget {
  const _ClockDisplay({
    required this.isDimmed,
    required this.isLoadingMedia,
    required this.hasMediaInfo,
    required this.trackTitle,
    required this.artistName,
    required this.thumbnailBase64,
    required this.isPlaying,
    required this.progressPositionMs,
    required this.progressDurationMs,
    required this.onEnableAccess,
    required this.onRefresh,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.supportsMediaControls,
    required this.recentNotifications,
    required this.onTap,
    required this.onOpenAssistant,
  });

  final bool isDimmed;
  final bool isLoadingMedia;
  final bool hasMediaInfo;
  final String trackTitle;
  final String artistName;
  final String thumbnailBase64;
  final bool isPlaying;
  final int progressPositionMs;
  final int progressDurationMs;
  final Future<void> Function() onEnableAccess;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final bool supportsMediaControls;
  final List<Map<dynamic, dynamic>> recentNotifications;
  final VoidCallback onTap;
  final VoidCallback onOpenAssistant;

  @override
  State<_ClockDisplay> createState() => _ClockDisplayState();
}

class _ClockDisplayState extends State<_ClockDisplay> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final now = DateTime.now();
        if (now.minute != _now.minute || now.day != _now.day) {
          setState(() {
            _now = now;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatHour(DateTime dt) => dt.hour.toString().padLeft(2, '0');
  String _formatMinute(DateTime dt) => dt.minute.toString().padLeft(2, '0');
  String _formatWeekday(DateTime dt) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
  String _formatMonth(DateTime dt) => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][dt.month - 1];

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;

    final String hourText = _formatHour(_now);
    final String minuteText = _formatMinute(_now);
    final String weekdayText = _formatWeekday(_now);
    final String monthText = _formatMonth(_now);
    final String dayText = _now.day.toString();
    final String yearText = _now.year.toString();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortestSide = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;
          final textWidth = constraints.maxWidth * 0.92;
          final isLandscape = orientation == Orientation.landscape;
          final mediaHeight =
              constraints.maxHeight * (isLandscape ? 0.24 : 0.12);

          final double timeSize = shortestSide * (isLandscape ? 0.38 : 0.30);
          final double dateSize = shortestSide * (isLandscape ? 0.12 : 0.09);

          return Stack(
            children: [
              // Center clock, date, and notification icons
              Center(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLandscape ? mediaHeight : 0,
                  ),
                  child: AnimatedOpacity(
                    opacity: widget.isDimmed ? 0.28 : 1.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: isLandscape
                        ? _buildLandscapeLayout(
                            timeSize,
                            dateSize,
                            textWidth,
                            hourText,
                            minuteText,
                            weekdayText,
                            monthText,
                            dayText,
                            yearText,
                          )
                        : _buildPortraitLayout(
                            timeSize,
                            dateSize,
                            textWidth,
                            hourText,
                            minuteText,
                            weekdayText,
                            monthText,
                            dayText,
                            yearText,
                          ),
                  ),
                ),
              ),

              // Bottom media control bar
              if (widget.supportsMediaControls)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: mediaHeight,
                  child: AnimatedOpacity(
                    opacity: widget.isDimmed ? 0.28 : 1.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: _SpotifyStyleMediaBar(
                      isLoading: widget.isLoadingMedia,
                      hasMediaInfo: widget.hasMediaInfo,
                      trackTitle: widget.trackTitle,
                      artistName: widget.artistName,
                      thumbnailBase64: widget.thumbnailBase64,
                      isPlaying: widget.isPlaying,
                      progressPositionMs: widget.progressPositionMs,
                      progressDurationMs: widget.progressDurationMs,
                      onEnableAccess: widget.onEnableAccess,
                      onRefresh: widget.onRefresh,
                      onPrevious: widget.onPrevious,
                      onPlayPause: widget.onPlayPause,
                      onNext: widget.onNext,
                      isLandscape: isLandscape,
                    ),
                  ),
                ),
                
              // Google Assistant floating button
              Positioned(
                top: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: widget.isDimmed ? 0.15 : 0.85,
                  duration: const Duration(milliseconds: 350),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        widget.onTap(); // Keep device awake
                        widget.onOpenAssistant();
                      },
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mic_none_rounded,
                              color: Colors.white60,
                              size: 28,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ASSISTANT',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: isLandscape ? 10 : 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPortraitLayout(
    double timeSize,
    double dateSize,
    double textWidth,
    String hourText,
    String minuteText,
    String weekdayText,
    String monthText,
    String dayText,
    String yearText,
  ) {
    return SizedBox(
      width: textWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DigitalTimeFace(
              hourText: hourText,
              minuteText: minuteText,
              fontSize: timeSize,
              width: textWidth,
            ),
            const SizedBox(height: 20),
            _PrettyDateCard(
              weekdayText: weekdayText,
              monthText: monthText,
              dayText: dayText,
              yearText: yearText,
              width: textWidth,
              fontSize: dateSize,
            ),
            const SizedBox(height: 16),
            _buildNotificationIconsForClock(),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(
    double timeSize,
    double dateSize,
    double textWidth,
    String hourText,
    String minuteText,
    String weekdayText,
    String monthText,
    String dayText,
    String yearText,
  ) {
    return SizedBox(
      width: textWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Large clock on left
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _DigitalTimeFace(
                hourText: hourText,
                minuteText: minuteText,
                fontSize: timeSize,
                width: textWidth * 0.6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Date and icons stacked on right
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _PrettyDateCard(
                    weekdayText: weekdayText,
                    monthText: monthText,
                    dayText: dayText,
                    yearText: yearText,
                    width: textWidth * 0.35,
                    fontSize: dateSize * 0.85,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 28,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildNotificationIconsForClock(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIconsForClock() {
    if (widget.recentNotifications.isEmpty) {
      return SizedBox(
        height: 28,
        child: Center(
          child: Text(
            'Swipe left for notifications',
            style: TextStyle(
              color: const Color(0xFF6A6A6A),
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 28,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: math.min(widget.recentNotifications.length, 8),
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final notification = widget.recentNotifications[index];
          final title = notification['title'] ?? '';
          final iconBase64 = notification['iconBase64'] ?? '';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Tooltip(
              message: '$title',
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x20FFFFFF)),
                ),
                child: _notificationAppIcon(iconBase64, size: 16),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _notificationAppIcon(String iconBase64, {double size = 28}) {
    if (iconBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(iconBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.2),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        // Fall back to the default icon.
      }
    }

    return Icon(
      Icons.notifications,
      size: size * 0.58,
      color: const Color(0xFF6A9CFF),
    );
  }
}
