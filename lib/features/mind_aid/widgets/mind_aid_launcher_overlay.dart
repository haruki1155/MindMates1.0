import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../routes/route_names.dart';
import '../domain/mind_aid_integration_models.dart';

class MindAidNavigation {
  const MindAidNavigation._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final observer = MindAidRouteObserver();
}

class MindAidRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> currentRoute = ValueNotifier(RouteNames.splash);
  String? _pendingRoute;
  bool _updateScheduled = false;

  void _set(Route<dynamic>? route) {
    _pendingRoute = route?.settings.name;
    if (_updateScheduled) return;
    _updateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      final nextRoute = _pendingRoute;
      if (currentRoute.value != nextRoute) {
        currentRoute.value = nextRoute;
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _set(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _set(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _set(newRoute);
  }
}

class MindAidLauncherOverlay extends StatefulWidget {
  const MindAidLauncherOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<MindAidLauncherOverlay> createState() => _MindAidLauncherOverlayState();
}

class _MindAidLauncherOverlayState extends State<MindAidLauncherOverlay> {
  static const double _launcherSize = 48;
  static const double _edgeMargin = 12;

  Offset? _position;
  Offset _displayedPosition = Offset.zero;

  static const _excludedRoutes = {
    RouteNames.splash,
    RouteNames.onboarding,
    RouteNames.login,
    RouteNames.signup,
    RouteNames.forgotPassword,
    RouteNames.mindAid,
  };

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().userId;
    return ValueListenableBuilder<String?>(
      valueListenable: MindAidNavigation.observer.currentRoute,
      builder: (context, route, _) {
        final show =
            route != null &&
            userId?.trim().isNotEmpty == true &&
            !_excludedRoutes.contains(route);
        return LayoutBuilder(
          builder: (context, constraints) {
            final bounds = _movementBounds(context, constraints);
            final position = _boundedPosition(bounds);
            _displayedPosition = position;

            return Stack(
              children: [
                widget.child,
                if (show)
                  Positioned(
                    left: position.dx,
                    top: position.dy,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        setState(() {
                          _position = _clampOffset(
                            (_position ?? _displayedPosition) + details.delta,
                            bounds,
                          );
                        });
                      },
                      child: Semantics(
                        button: true,
                        label: 'Talk to MindAid',
                        hint: 'Double tap to open or drag to move',
                        child: Material(
                          key: const ValueKey('globalMindAidLauncher'),
                          color: const Color(0xFFFFC107),
                          elevation: 6,
                          shadowColor: const Color(0x55000000),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _openMindAid(route),
                            child: const SizedBox.square(
                              dimension: _launcherSize,
                              child: Icon(
                                Icons.psychology_alt_rounded,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Rect _movementBounds(BuildContext context, BoxConstraints constraints) {
    final padding = MediaQuery.paddingOf(context);
    final left = padding.left + _edgeMargin;
    final top = padding.top + _edgeMargin;
    final right =
        constraints.maxWidth - padding.right - _edgeMargin - _launcherSize;
    final bottom =
        constraints.maxHeight - padding.bottom - _edgeMargin - _launcherSize;
    return Rect.fromLTRB(
      left,
      top,
      right < left ? left : right,
      bottom < top ? top : bottom,
    );
  }

  Offset _boundedPosition(Rect bounds) {
    return _clampOffset(
      _position ?? Offset(bounds.right, bounds.bottom),
      bounds,
    );
  }

  Offset _clampOffset(Offset position, Rect bounds) {
    return Offset(
      position.dx.clamp(bounds.left, bounds.right),
      position.dy.clamp(bounds.top, bounds.bottom),
    );
  }

  void _openMindAid(String? route) {
    final context = _launchContext(route);
    MindAidNavigation.navigatorKey.currentState?.pushNamed(
      RouteNames.mindAid,
      arguments: context,
    );
  }

  MindAidLaunchContext _launchContext(String? route) {
    switch (route) {
      case RouteNames.logMood:
        return const MindAidLaunchContext(
          source: 'mood',
          openingPrompt: 'Help me understand how I have been feeling.',
        );
      case RouteNames.journal:
        return const MindAidLaunchContext(
          source: 'journal',
          openingPrompt: 'Help me reflect without sharing my journal text.',
        );
      case RouteNames.studentAssessment:
      case RouteNames.studentAssessmentComplete:
        return const MindAidLaunchContext(
          source: 'assessment',
          openingPrompt: 'What does my assessment suggest?',
        );
      case RouteNames.mentalHealthReport:
      case RouteNames.mentalHealthInsights:
      case RouteNames.insights:
        return const MindAidLaunchContext(
          source: 'insights',
          openingPrompt: 'Help me understand my wellness patterns.',
        );
      case RouteNames.mindfulBreathing:
        return const MindAidLaunchContext(
          source: 'breathing',
          openingPrompt: 'Help me choose a calming exercise.',
        );
      case RouteNames.services:
        return const MindAidLaunchContext(
          source: 'counseling',
          openingPrompt: 'Help me decide what support service fits my concern.',
          appointmentConcern: 'I would like counseling support.',
        );
      case RouteNames.appointmentCalendar:
        return const MindAidLaunchContext(
          source: 'appointments',
          openingPrompt: 'Help me prepare for a counseling appointment.',
        );
      default:
        return const MindAidLaunchContext(
          source: 'home',
          openingPrompt: 'How can MindAid support me today?',
        );
    }
  }
}
