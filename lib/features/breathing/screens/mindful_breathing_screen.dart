import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/breathing_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../models/breathing_models.dart';

class MindfulBreathingScreen extends StatefulWidget {
  const MindfulBreathingScreen({super.key});

  @override
  State<MindfulBreathingScreen> createState() => _MindfulBreathingScreenState();
}

class _MindfulBreathingScreenState extends State<MindfulBreathingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gaugeController;
  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _cuePlayer = AudioPlayer();
  BreathingTechnique? _activeTechnique;
  _BreathingMood _selectedMood = _breathingMoods.first;
  _BreathingMood? _activeMood;
  Timer? _timer;
  DateTime? _startedAt;
  int _selectedMinutes = 3;
  int _elapsedSeconds = 0;
  bool _isPaused = false;
  bool _isCompleted = false;
  bool _soundEnabled = true;
  double _volume = .45;
  Set<String> _availableAudioAssets = const {};
  bool _audioAssetsChecked = false;

  @override
  void initState() {
    super.initState();
    _gaugeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      lowerBound: 0,
      upperBound: 1,
    )..repeat();
    _prepareAudio();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gaugeController.dispose();
    _musicPlayer.dispose();
    _cuePlayer.dispose();
    super.dispose();
  }

  Future<void> _prepareAudio() async {
    const ambientAsset = 'assets/audio/breathing/ambient_calm.mp3';
    try {
      _availableAudioAssets = await _loadAvailableAudioAssets();
      _audioAssetsChecked = true;
      if (!_availableAudioAssets.contains(ambientAsset)) {
        if (mounted) {
          setState(() => _soundEnabled = false);
        } else {
          _soundEnabled = false;
        }
        return;
      }
      await _musicPlayer.setAsset(ambientAsset);
      await _musicPlayer.setLoopMode(LoopMode.one);
      await _musicPlayer.setVolume(_volume);
    } catch (_) {
      _audioAssetsChecked = true;
      if (mounted) {
        setState(() => _soundEnabled = false);
      } else {
        _soundEnabled = false;
      }
    }
  }

  Future<Set<String>> _loadAvailableAudioAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where((asset) => asset.startsWith('assets/audio/breathing/'))
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeTechnique;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7E3),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _BreathingBackdrop()),
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _isCompleted && active != null
                  ? _CompletionView(
                      key: const ValueKey('completion'),
                      technique: active,
                      mood: _activeMood ?? _selectedMood,
                      isSaving: context.watch<BreathingProvider>().isSaving,
                      onDone: () => Navigator.of(context).pop(),
                      onRestart: () => _startSession(active, mood: _activeMood),
                    )
                  : active == null
                  ? _BreathingSetup(
                      key: const ValueKey('setup'),
                      selectedMood: _selectedMood,
                      selectedMinutes: _selectedMinutes,
                      animation: _gaugeController,
                      onMoodChanged: (mood) =>
                          setState(() => _selectedMood = mood),
                      onMinutesChanged: (minutes) =>
                          setState(() => _selectedMinutes = minutes),
                      onStart: () {
                        final technique = _selectedMood.toTechnique(
                          minutes: _selectedMinutes,
                        );
                        _startSession(technique, mood: _selectedMood);
                      },
                    )
                  : _BreathingPlayer(
                      key: const ValueKey('player'),
                      technique: active,
                      mood: _activeMood ?? _selectedMood,
                      elapsedSeconds: _elapsedSeconds,
                      isPaused: _isPaused,
                      soundEnabled: _soundEnabled,
                      volume: _volume,
                      gaugeAnimation: _gaugeController,
                      onTogglePause: _togglePause,
                      onRestart: () => _startSession(active, mood: _activeMood),
                      onExit: _confirmExit,
                      onToggleSound: _toggleSound,
                      onVolumeChanged: _setVolume,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startSession(
    BreathingTechnique technique, {
    _BreathingMood? mood,
  }) async {
    final shouldStart = await _confirmStart(technique);
    if (shouldStart != true || !mounted) return;

    _timer?.cancel();
    setState(() {
      _activeTechnique = technique;
      _activeMood = mood ?? _activeMood ?? _selectedMood;
      _startedAt = DateTime.now();
      _elapsedSeconds = 0;
      _isPaused = false;
      _isCompleted = false;
    });
    _gaugeController.repeat();
    unawaited(_playMusicIfEnabled());
    unawaited(_playCue('soft_chime.mp3'));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<bool?> _confirmStart(BreathingTechnique technique) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        icon: const Icon(
          Icons.self_improvement_rounded,
          color: _BreathingPalette.green,
          size: 34,
        ),
        title: const Text('Ready to begin?'),
        content: Text(
          'Find a comfortable position before starting ${technique.title}. You can pause or leave anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _BreathingPalette.gold,
              foregroundColor: _BreathingPalette.ink,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start breathing'),
          ),
        ],
      ),
    );
  }

  Future<void> _tick() async {
    final technique = _activeTechnique;
    if (technique == null || _isPaused || _isCompleted) return;

    final next = _elapsedSeconds + 1;
    if (next >= technique.durationSeconds) {
      setState(() {
        _elapsedSeconds = technique.durationSeconds;
      });
      await _completeSession();
      return;
    }

    setState(() => _elapsedSeconds = next);
  }

  Future<void> _completeSession() async {
    final technique = _activeTechnique;
    final userId = context.read<UserProvider>().user?.id;
    final startedAt = _startedAt;
    if (technique == null || startedAt == null || _isCompleted) return;

    _timer?.cancel();
    setState(() {
      _isCompleted = true;
      _isPaused = false;
    });
    unawaited(_musicPlayer.pause());
    unawaited(_playCue('session_complete.mp3'));

    if (userId == null || userId.trim().isEmpty) return;
    final saved = await context.read<BreathingProvider>().completeSession(
      userId: userId,
      technique: technique,
      completedSeconds: technique.durationSeconds,
      startedAt: startedAt,
    );
    if (!mounted || !saved) return;
    await _refreshProfileAndReport(userId);
  }

  Future<void> _refreshProfileAndReport(String userId) async {
    try {
      await context.read<UserProvider>().loadProfile(userId);
      await _readProviderOrNull<ReportProvider>()?.refreshWeeklyReport(userId);
      await _readProviderOrNull<InsightsProvider>()?.refreshLoadedContext(
        userId,
      );
    } catch (_) {
      // The completed breathing session remains saved even if summary refresh
      // is temporarily unavailable.
    }
  }

  T? _readProviderOrNull<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _togglePause() async {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _gaugeController.stop();
      await _musicPlayer.pause();
    } else {
      _gaugeController.repeat();
      unawaited(_playMusicIfEnabled());
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Leave this session?'),
        content: const Text(
          'Your breathing session is recorded only when the timer completes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _BreathingPalette.gold,
              foregroundColor: _BreathingPalette.ink,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (shouldExit != true || !mounted) return;
    _timer?.cancel();
    await _musicPlayer.pause();
    setState(() {
      _activeTechnique = null;
      _activeMood = null;
      _elapsedSeconds = 0;
      _isPaused = false;
    });
  }

  Future<void> _toggleSound() async {
    setState(() => _soundEnabled = !_soundEnabled);
    if (_soundEnabled) {
      unawaited(_playMusicIfEnabled());
    } else {
      await _musicPlayer.pause();
    }
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    try {
      await _musicPlayer.setVolume(value);
    } catch (_) {}
  }

  Future<void> _playMusicIfEnabled() async {
    if (!_soundEnabled || !_audioAssetsChecked) return;
    try {
      await _musicPlayer.setVolume(_volume);
      await _musicPlayer.play();
    } catch (_) {}
  }

  Future<void> _playCue(String fileName) async {
    if (!_soundEnabled || !_audioAssetsChecked) return;
    final asset = 'assets/audio/breathing/$fileName';
    if (!_availableAudioAssets.contains(asset)) return;
    try {
      await _cuePlayer.setAsset(asset);
      await _cuePlayer.play();
    } catch (_) {}
  }
}

class _BreathingSetup extends StatelessWidget {
  const _BreathingSetup({
    super.key,
    required this.selectedMood,
    required this.selectedMinutes,
    required this.animation,
    required this.onMoodChanged,
    required this.onMinutesChanged,
    required this.onStart,
  });

  final _BreathingMood selectedMood;
  final int selectedMinutes;
  final Animation<double> animation;
  final ValueChanged<_BreathingMood> onMoodChanged;
  final ValueChanged<int> onMinutesChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sphereSize = math.min(constraints.maxWidth * .72, 300.0);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 46),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BreathingHeader(
                    closeIcon: Icons.arrow_back_ios_new_rounded,
                  ),
                  SizedBox(height: constraints.maxHeight < 720 ? 18 : 32),
                  Center(
                    child: _BreathingSphere(
                      size: sphereSize,
                      animation: animation,
                    ),
                  ),
                  SizedBox(height: constraints.maxHeight < 720 ? 24 : 42),
                  const Text(
                    'Breath to reduce',
                    style: TextStyle(
                      color: _BreathingPalette.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MoodSelector(
                    selectedMood: selectedMood,
                    onMoodChanged: onMoodChanged,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Time',
                    style: TextStyle(
                      color: _BreathingPalette.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _DurationSelector(
                    selectedMinutes: selectedMinutes,
                    onChanged: onMinutesChanged,
                  ),
                  const SizedBox(height: 34),
                  const Spacer(),
                  _GoldActionButton(
                    label: 'Start breathing',
                    onPressed: onStart,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BreathingPlayer extends StatelessWidget {
  const _BreathingPlayer({
    super.key,
    required this.technique,
    required this.mood,
    required this.elapsedSeconds,
    required this.isPaused,
    required this.soundEnabled,
    required this.volume,
    required this.gaugeAnimation,
    required this.onTogglePause,
    required this.onRestart,
    required this.onExit,
    required this.onToggleSound,
    required this.onVolumeChanged,
  });

  final BreathingTechnique technique;
  final _BreathingMood mood;
  final int elapsedSeconds;
  final bool isPaused;
  final bool soundEnabled;
  final double volume;
  final Animation<double> gaugeAnimation;
  final VoidCallback onTogglePause;
  final VoidCallback onRestart;
  final VoidCallback onExit;
  final VoidCallback onToggleSound;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final progress = (elapsedSeconds / technique.durationSeconds)
        .clamp(0, 1)
        .toDouble();
    final phase = BreathingPlan.phaseFor(technique, elapsedSeconds);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final sphereSize = math.min(
          constraints.maxWidth * (compact ? .82 : .92),
          compact ? 300.0 : 370.0,
        );
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 42),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  _BreathingHeader(
                    closeIcon: Icons.arrow_back_ios_new_rounded,
                    onClose: onExit,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CircleIconButton(
                          icon: Icons.replay_rounded,
                          tooltip: 'Restart',
                          onPressed: onRestart,
                        ),
                        const SizedBox(width: 8),
                        _CircleIconButton(
                          icon: soundEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          tooltip: soundEnabled ? 'Mute sound' : 'Enable sound',
                          onPressed: onToggleSound,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 20 : 34),
                  _BreathingSphere(
                    size: sphereSize,
                    animation: gaugeAnimation,
                    progress: progress,
                    phase: _phaseTitle(phase.label),
                    subtitle: 'Follow the sphere',
                  ),
                  SizedBox(height: compact ? 16 : 26),
                  _MoodPill(mood: mood, selected: true, compact: true),
                  const SizedBox(height: 26),
                  Text.rich(
                    TextSpan(
                      text: _formatTime(elapsedSeconds),
                      style: const TextStyle(
                        color: _BreathingPalette.ink,
                        fontSize: 31,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        TextSpan(
                          text: ' / ${_formatTime(technique.durationSeconds)}',
                          style: const TextStyle(
                            color: _BreathingPalette.mutedGreen,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SessionProgress(value: progress),
                  const SizedBox(height: 14),
                  _PhaseDots(
                    count: technique.pattern.steps.length,
                    activeIndex: _phaseIndex(technique, elapsedSeconds),
                  ),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      activeTrackColor: _BreathingPalette.gold,
                      inactiveTrackColor: _BreathingPalette.mutedGreen
                          .withValues(alpha: .2),
                      thumbColor: _BreathingPalette.gold,
                      overlayColor: _BreathingPalette.gold.withValues(
                        alpha: .12,
                      ),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                        disabledThumbRadius: 5,
                      ),
                    ),
                    child: Slider(
                      value: volume,
                      onChanged: soundEnabled ? onVolumeChanged : null,
                    ),
                  ),
                  const Spacer(),
                  _GoldActionButton(
                    icon: isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    label: isPaused ? 'Resume' : 'Pause',
                    onPressed: onTogglePause,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: onExit,
                    child: const Text(
                      'End session',
                      style: TextStyle(
                        color: _BreathingPalette.mutedGreen,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static int _phaseIndex(BreathingTechnique technique, int elapsedSeconds) {
    final steps = technique.pattern.steps;
    final cycleSeconds = steps.fold<int>(0, (sum, step) => sum + step.seconds);
    final elapsedInCycle = cycleSeconds == 0
        ? 0
        : elapsedSeconds % cycleSeconds;
    var cursor = 0;
    for (var index = 0; index < steps.length; index++) {
      cursor += steps[index].seconds;
      if (elapsedInCycle < cursor) return index;
    }
    return steps.length - 1;
  }

  static String _phaseTitle(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('exhale')) return 'Exhale';
    if (lower.contains('hold') || lower.contains('pause')) return 'Hold';
    if (lower.contains('inhale')) return 'Inhale';
    return 'Breathe';
  }
}

class _BreathingHeader extends StatelessWidget {
  const _BreathingHeader({
    this.closeIcon = Icons.arrow_back_ios_new_rounded,
    this.onClose,
    this.trailing,
  });

  final IconData closeIcon;
  final VoidCallback? onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _CircleIconButton(
              icon: closeIcon,
              tooltip: 'Back',
              onPressed: onClose ?? () => Navigator.of(context).pop(),
            ),
          ),
          const Text(
            'Breathing',
            style: TextStyle(
              color: _BreathingPalette.ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .78),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x19000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon, size: 22, color: _BreathingPalette.ink),
        ),
      ),
    );
  }
}

class _MoodSelector extends StatelessWidget {
  const _MoodSelector({
    required this.selectedMood,
    required this.onMoodChanged,
  });

  final _BreathingMood selectedMood;
  final ValueChanged<_BreathingMood> onMoodChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var index = 0; index < _breathingMoods.length; index++) ...[
            _MoodPill(
              mood: _breathingMoods[index],
              selected: _breathingMoods[index] == selectedMood,
              onTap: () => onMoodChanged(_breathingMoods[index]),
            ),
            if (index != _breathingMoods.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _MoodPill extends StatelessWidget {
  const _MoodPill({
    required this.mood,
    required this.selected,
    this.compact = false,
    this.onTap,
  });

  final _BreathingMood mood;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : _BreathingPalette.mutedGreen;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 15,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: selected
            ? _BreathingPalette.gold
            : Colors.white.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? _BreathingPalette.gold
              : _BreathingPalette.mutedGreen.withValues(alpha: .34),
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x35F5BC55),
                  blurRadius: 20,
                  offset: Offset(0, 9),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mood.icon, color: foreground, size: compact ? 18 : 19),
          const SizedBox(width: 8),
          Text(
            mood.label,
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: pill,
    );
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({
    required this.selectedMinutes,
    required this.onChanged,
  });

  final int selectedMinutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var minutes = 1; minutes <= 6; minutes++) ...[
            _DurationOption(
              minutes: minutes,
              selected: minutes == selectedMinutes,
              onTap: () => onChanged(minutes),
            ),
            if (minutes != 6) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _DurationOption extends StatelessWidget {
  const _DurationOption({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 82,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0CC) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$minutes min',
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: selected
                    ? _BreathingPalette.ink
                    : _BreathingPalette.mutedGreen,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: selected ? _BreathingPalette.gold : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreathingSphere extends StatelessWidget {
  const _BreathingSphere({
    required this.size,
    required this.animation,
    this.progress = 0,
    this.phase,
    this.subtitle,
  });

  final double size;
  final Animation<double> animation;
  final double progress;
  final String? phase;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Breathing sphere',
      value: phase,
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final breath = math.sin(animation.value * math.pi * 2);
            final scale = phase == null ? 1.0 : .94 + ((breath + 1) * .045);
            return Transform.scale(
              scale: scale,
              child: CustomPaint(
                painter: _BreathingSpherePainter(
                  animation: animation.value,
                  progress: progress,
                ),
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: phase == null ? 0 : 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          phase ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _BreathingPalette.ink.withValues(alpha: .92),
                            fontSize: math.max(26, size * .12),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subtitle ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _BreathingPalette.mutedGreen,
                            fontSize: math.max(14, size * .052),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SessionProgress extends StatelessWidget {
  const _SessionProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 4,
        width: 260,
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: _BreathingPalette.mutedGreen.withValues(alpha: .16),
          color: _BreathingPalette.gold,
        ),
      ),
    );
  }
}

class _PhaseDots extends StatelessWidget {
  const _PhaseDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: index == activeIndex
                  ? _BreathingPalette.gold
                  : _BreathingPalette.mutedGreen.withValues(alpha: .72),
              shape: BoxShape.circle,
            ),
          ),
          if (index != count - 1) const SizedBox(width: 20),
        ],
      ],
    );
  }
}

class _GoldActionButton extends StatelessWidget {
  const _GoldActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 26), const SizedBox(width: 12)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      height: 72,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _BreathingPalette.gold,
          foregroundColor: _BreathingPalette.ink,
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({
    super.key,
    required this.technique,
    required this.mood,
    required this.isSaving,
    required this.onDone,
    required this.onRestart,
  });

  final BreathingTechnique technique;
  final _BreathingMood mood;
  final bool isSaving;
  final VoidCallback onDone;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      child: Column(
        children: [
          const _BreathingHeader(),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: .72)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1FF2B84B),
                  blurRadius: 40,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD878), Color(0xFFF3B74A)],
                    ),
                  ),
                  child: const Icon(
                    Icons.self_improvement_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Session complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _BreathingPalette.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _MoodPill(mood: mood, selected: true, compact: true),
                const SizedBox(height: 14),
                Text(
                  '${technique.title} | ${technique.durationLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _BreathingPalette.mutedGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Notice one thing that feels softer now. Your body may need a few quiet seconds before moving on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _BreathingPalette.mutedGreen,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                if (isSaving)
                  const LinearProgressIndicator(
                    minHeight: 4,
                    color: _BreathingPalette.gold,
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRestart,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Again'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _BreathingPalette.gold,
                          foregroundColor: _BreathingPalette.ink,
                        ),
                        onPressed: onDone,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _BreathingBackdrop extends CustomPainter {
  const _BreathingBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFBF0), Color(0xFFFFF0C8), Color(0xFFFFFAEA)],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    _drawGlow(
      canvas,
      size,
      Offset(size.width * .14, size.height * .11),
      size.width * .42,
      const Color(0x66FFFFFF),
    );
    _drawGlow(
      canvas,
      size,
      Offset(size.width * .92, size.height * .22),
      size.width * .46,
      const Color(0x55FFD06A),
    );
    _drawGlow(
      canvas,
      size,
      Offset(size.width * .13, size.height * .86),
      size.width * .32,
      const Color(0x44FFFFFF),
    );

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 7; i++) {
      final path = Path()
        ..moveTo(-30, size.height * (.68 + i * .015))
        ..cubicTo(
          size.width * .22,
          size.height * (.58 + i * .015),
          size.width * .34,
          size.height * (.72 + i * .012),
          size.width * .52,
          size.height * (.63 + i * .015),
        );
      canvas.drawPath(path, linePaint);
    }

    final leafPaint = Paint()
      ..color = const Color(0xFF9DBFAA).withValues(alpha: .23)
      ..style = PaintingStyle.fill;
    final stemPaint = Paint()
      ..color = const Color(0xFF9DBFAA).withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final stem = Path()
      ..moveTo(size.width * .78, size.height * .95)
      ..cubicTo(
        size.width * .72,
        size.height * .78,
        size.width * .81,
        size.height * .68,
        size.width * .88,
        size.height * .59,
      );
    canvas.drawPath(stem, stemPaint);
    for (final leaf in [
      Offset(size.width * .71, size.height * .76),
      Offset(size.width * .86, size.height * .71),
      Offset(size.width * .77, size.height * .63),
      Offset(size.width * .93, size.height * .59),
    ]) {
      canvas.save();
      canvas.translate(leaf.dx, leaf.dy);
      canvas.rotate(leaf.dx < size.width * .8 ? -.55 : .55);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 52, height: 94),
        leafPaint,
      );
      canvas.restore();
    }
  }

  static void _drawGlow(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    Color color,
  ) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BreathingBackdrop oldDelegate) => false;
}

class _BreathingSpherePainter extends CustomPainter {
  const _BreathingSpherePainter({
    required this.animation,
    required this.progress,
  });

  final double animation;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final shadowPaint = Paint()
      ..color = const Color(0x29F2B84B)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, size.height * .88),
        width: size.width * .58,
        height: size.height * .12,
      ),
      shadowPaint,
    );

    for (var index = 0; index < 5; index++) {
      final ringRadius = radius * (.55 + index * .105);
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: .38 - index * .035);
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    final orbRect = Rect.fromCircle(center: center, radius: radius * .68);
    final orbPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.45, -.38),
        radius: .96,
        colors: [
          Color(0xFFFFE382),
          Color(0xFFFFF4D6),
          Color(0xFFD5E7DF),
          Color(0xFFA8C9B8),
        ],
        stops: [0, .42, .74, 1],
      ).createShader(orbRect);
    canvas.drawCircle(center, radius * .68, orbPaint);

    final glazePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: .72),
          Colors.white.withValues(alpha: .08),
          Colors.white.withValues(alpha: .34),
        ],
      ).createShader(orbRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius * .68, glazePaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          _BreathingPalette.gold.withValues(alpha: .72),
          Colors.white.withValues(alpha: .82),
          _BreathingPalette.green.withValues(alpha: .46),
          _BreathingPalette.gold.withValues(alpha: .72),
        ],
      ).createShader(orbRect);
    if (progress > 0) {
      canvas.drawArc(
        orbRect.deflate(7),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        progressPaint,
      );
    }

    final shinePaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: .9),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                size.width * (.32 + animation * .05),
                size.height * .32,
              ),
              radius: radius * .22,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * (.32 + animation * .05), size.height * .32),
      radius * .22,
      shinePaint,
    );

    final flashPaint = Paint()
      ..color = Colors.white.withValues(alpha: .7)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .58),
      math.pi * (1.58 + animation * .08),
      math.pi * .18,
      false,
      flashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BreathingSpherePainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.progress != progress;
  }
}

class _BreathingMood {
  const _BreathingMood({
    required this.id,
    required this.label,
    required this.icon,
    required this.bestFor,
    required this.howTo,
  });

  final String id;
  final String label;
  final IconData icon;
  final String bestFor;
  final String howTo;

  BreathingTechnique toTechnique({required int minutes}) {
    final pattern = switch (id) {
      'anger' => BreathingPattern.longExhale,
      'anxiety' =>
        minutes >= 5 ? BreathingPattern.nhsCalm : BreathingPattern.balanced,
      'stress' =>
        minutes >= 3 ? BreathingPattern.box : BreathingPattern.balanced,
      'overwhelm' => BreathingPattern.emergencyReset,
      _ => BreathingPattern.balanced,
    };
    final hasBreathHold = id == 'stress' && minutes >= 3;
    return BreathingTechnique(
      id: 'mood_${id}_${minutes}m',
      title: '$label Breathing',
      durationSeconds: minutes * 60,
      bestFor: bestFor,
      howTo: howTo,
      pattern: pattern,
      hasBreathHold: hasBreathHold,
    );
  }
}

const _breathingMoods = [
  _BreathingMood(
    id: 'anger',
    label: 'Anger',
    icon: Icons.sentiment_very_dissatisfied_rounded,
    bestFor: 'Cooling down strong feelings',
    howTo: 'Use a longer exhale to soften tension and slow the body down.',
  ),
  _BreathingMood(
    id: 'anxiety',
    label: 'Anxiety',
    icon: Icons.local_florist_rounded,
    bestFor: 'Settling worry and nervous energy',
    howTo: 'Breathe evenly and keep the body comfortable without strain.',
  ),
  _BreathingMood(
    id: 'stress',
    label: 'Stress',
    icon: Icons.waves_rounded,
    bestFor: 'Rebuilding focus under pressure',
    howTo: 'Follow steady counts and use gentle holds only if comfortable.',
  ),
  _BreathingMood(
    id: 'overwhelm',
    label: 'Overwhelm',
    icon: Icons.adjust_rounded,
    bestFor: 'Finding a small first reset',
    howTo: 'Keep the rhythm simple with a soft inhale and slow exhale.',
  ),
];

class _BreathingPalette {
  const _BreathingPalette._();

  static const ink = Color(0xFF18233D);
  static const green = Color(0xFF8CB8AA);
  static const mutedGreen = Color(0xFF88A5A1);
  static const gold = Color(0xFFF7C85D);
}

String _formatTime(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final remainder = safe % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}
