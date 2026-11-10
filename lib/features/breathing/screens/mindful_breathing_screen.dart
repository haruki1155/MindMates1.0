import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/breathing_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../models/breathing_models.dart';
import '../services/breathing_sound_service.dart';

class MindfulBreathingScreen extends StatefulWidget {
  const MindfulBreathingScreen({super.key});

  @override
  State<MindfulBreathingScreen> createState() => _MindfulBreathingScreenState();
}

const _ambientTracks = <String>[
  'Morning Mood (Your Audio)',
  'Original Calm',
  'Ocean Hush',
  'Rain Sanctuary',
  'Forest Stillness',
  'Moonlight Drift',
  'Soft Piano Glow',
  'Gentle Wind',
  'Morning Dew',
  'Deep Rest',
  'Warm Sunrise',
];
const _ambientFiles = <String>[
  'morning_mood.mp3',
  'ambient_calm.mp3',
  'ocean_hush.mp3',
  'rain_sanctuary.mp3',
  'forest_stillness.mp3',
  'moonlight_drift.mp3',
  'soft_piano_glow.mp3',
  'gentle_wind.mp3',
  'morning_dew.mp3',
  'deep_rest.mp3',
  'warm_sunrise.mp3',
];
const _sceneAssets = <String>[
  'misty_mountains.png',
  'calm_ocean.png',
  'zen_garden.png',
  'quiet_night.png',
  'rose_sunset.png',
];

const _breathingThemes = <String>[
  'Golden Dawn',
  'Ocean Mist',
  'Sage Garden',
  'Lavender Night',
  'Rose Sunset',
];
const _themeColors = <List<Color>>[
  [Color(0xFFFFFBF0), Color(0xFFFFEFC6), Color(0xFFFFF8E8)],
  [Color(0xFFE7F8FA), Color(0xFFBFDDE6), Color(0xFFF1FAFB)],
  [Color(0xFFF0F8E9), Color(0xFFD0E6D1), Color(0xFFF8FAED)],
  [Color(0xFFF2EEFF), Color(0xFFD8D2ED), Color(0xFFF7F2FA)],
  [Color(0xFFFFF0E9), Color(0xFFF7D8D0), Color(0xFFFFF8EE)],
];

class _MindfulBreathingScreenState extends State<MindfulBreathingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _gaugeController;

  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _cuePlayer = AudioPlayer();
  final AudioPlayer _voicePlayer = AudioPlayer();
  int _voiceToken = 0;
  String _voiceGender = 'female';
  final BreathingSoundService _breathingSound = BreathingSoundService();

  BreathingTechnique? _activeTechnique;
  _BreathingMood _selectedMood = _breathingMoods.first;
  _BreathingMood? _activeMood;

  Timer? _timer;
  DateTime? _startedAt;

  static const int _fixedSessionMinutes = 5;
  int _elapsedSeconds = 0;
  bool _isPaused = false;
  bool _isCompleted = false;
  bool _soundEnabled = true;
  bool _audioAssetsChecked = false;
  bool _ambientReady = false;
  int _selectedTrack = 0;
  int _selectedTheme = 0;
  int _musicChangeToken = 0;
  double _volume = 0.80;

  Set<String> _availableAudioAssets = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _gaugeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    unawaited(_prepareAudio());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _gaugeController.dispose();
    unawaited(_breathingSound.dispose());
    unawaited(_musicPlayer.dispose());
    unawaited(_cuePlayer.dispose());
    ++_voiceToken;
    unawaited(_voicePlayer.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_activeTechnique != null && !_isPaused && !_isCompleted) {
        setState(() => _isPaused = true);
        _gaugeController.stop();
        unawaited(_breathingSound.stop());
        ++_voiceToken;
        unawaited(_voicePlayer.stop());
        unawaited(_musicPlayer.pause());
        unawaited(_cuePlayer.stop());
      }
    }
  }

  Future<void> _prepareAudio() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _availableAudioAssets = manifest
          .listAssets()
          .where((asset) => asset.startsWith('assets/audio/breathing/'))
          .toSet();
      _audioAssetsChecked = true;
      await _loadSelectedMusic();
    } catch (error) {
      _audioAssetsChecked = true;
      _ambientReady = false;
      debugPrint('Optional breathing music unavailable: $error');
    }
  }

  Future<void> _loadSelectedMusic() async {
    final token = ++_musicChangeToken;
    final asset = 'assets/audio/breathing/${_ambientFiles[_selectedTrack]}';
    _ambientReady = false;
    try {
      await _musicPlayer.stop();
      if (token != _musicChangeToken || !mounted) return;
      if (!_availableAudioAssets.contains(asset)) {
        _ambientReady = false;
        debugPrint('Missing ambient track: $asset');
        return;
      }
      await _musicPlayer.setAsset(asset);
      if (token != _musicChangeToken || !mounted) return;
      await _musicPlayer.setLoopMode(LoopMode.one);
      await _musicPlayer.setVolume(_volume * 0.65);
      _ambientReady = true;
      if (_activeTechnique != null && !_isPaused && !_isCompleted) {
        unawaited(_playMusicIfEnabled());
      }
    } catch (error) {
      _ambientReady = false;
      debugPrint('Unable to load selected music: $error');
    }
  }

  void _changeTrack(int index) {
    if (index == _selectedTrack || index < 0 || index >= _ambientFiles.length) {
      return;
    }
    setState(() => _selectedTrack = index);
    if (_audioAssetsChecked) unawaited(_loadSelectedMusic());
  }

  void _changeVoice(String? value) {
    if (value != 'female' && value != 'male') return;
    setState(() => _voiceGender = value!);
    ++_voiceToken;
    unawaited(_voicePlayer.stop());
    final technique = _activeTechnique;
    if (technique != null && !_isPaused && !_isCompleted && _soundEnabled) {
      unawaited(_announceMindMateVoice(technique));
    }
  }

  void _changeTheme(int index) {
    if (index < 0 || index >= _breathingThemes.length) return;
    setState(() => _selectedTheme = index);
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeTechnique;
    final isNight = _selectedTheme == 3;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7E3),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 650),
              child: Image.asset(
                'assets/images/breathing/${_sceneAssets[_selectedTheme]}',
                key: ValueKey(_selectedTheme),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) =>
                    CustomPaint(painter: _SimpleScenicBackdrop(_selectedTheme)),
              ),
            ),
          ),
          // A gentle night overlay keeps text readable over the scene image.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeInOut,
                color: isNight ? const Color(0x990B1430) : Colors.transparent,
              ),
            ),
          ),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: isNight ? const Color(0xFFF7F4FF) : _BreathingPalette.ink,
            ),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeInOut,
            builder: (context, foreground, child) {
              final textColor = foreground ?? _BreathingPalette.ink;
              return Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.apply(
                    bodyColor: textColor,
                    displayColor: textColor,
                  ),
                  iconTheme: IconThemeData(color: textColor),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: textColor),
                  child: child!,
                ),
              );
            },
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _isCompleted && active != null
                    ? _CompletionView(
                        key: const ValueKey('completion'),
                        technique: active,
                        mood: _activeMood ?? _selectedMood,
                        isSaving: context.watch<BreathingProvider>().isSaving,
                        onDone: () => Navigator.of(context).pop(),
                        onRestart: () =>
                            unawaited(_startSession(active, mood: _activeMood)),
                      )
                    : active == null
                    ? _BreathingSetup(
                        key: const ValueKey('setup'),
                        selectedMood: _selectedMood,
                        voiceGender: _voiceGender,
                        onVoiceChanged: _changeVoice,
                        selectedTrack: _selectedTrack,
                        selectedTheme: _selectedTheme,
                        onTrackChanged: _changeTrack,
                        onThemeChanged: _changeTheme,
                        animation: _gaugeController,
                        onMoodChanged: (mood) {
                          setState(() => _selectedMood = mood);
                        },
                        onStart: () {
                          final technique = _selectedMood.toTechnique(
                            minutes: _fixedSessionMinutes,
                          );
                          unawaited(
                            _startSession(technique, mood: _selectedMood),
                          );
                        },
                      )
                    : _BreathingPlayer(
                        key: const ValueKey('player'),
                        technique: active,
                        mood: _activeMood ?? _selectedMood,
                        selectedTrack: _selectedTrack,
                        selectedTheme: _selectedTheme,
                        onTrackChanged: _changeTrack,
                        onThemeChanged: _changeTheme,
                        elapsedSeconds: _elapsedSeconds,
                        isPaused: _isPaused,
                        soundEnabled: _soundEnabled,
                        volume: _volume,
                        gaugeAnimation: _gaugeController,
                        onTogglePause: () => unawaited(_togglePause()),
                        onRestart: () =>
                            unawaited(_startSession(active, mood: _activeMood)),
                        onExit: () => unawaited(_confirmExit()),
                        onToggleSound: () => unawaited(_toggleSound()),
                        onVolumeChanged: (value) =>
                            unawaited(_setVolume(value)),
                      ),
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
    final confirmed = await _confirmStart(technique);
    if (confirmed != true || !mounted) return;

    _timer?.cancel();
    await _breathingSound.stop();
    ++_voiceToken;
    unawaited(_voicePlayer.stop());
    await _musicPlayer.pause();
    await _cuePlayer.stop();

    if (!mounted) return;

    setState(() {
      _activeTechnique = technique;
      _activeMood = mood ?? _selectedMood;
      _startedAt = DateTime.now();
      _elapsedSeconds = 0;
      _isPaused = false;
      _isCompleted = false;
    });

    _beginBreathingPhase(technique);
    unawaited(_playMusicIfEnabled());
    unawaited(_playCue('soft_chime.mp3'));

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_tick()),
    );
  }

  void _beginBreathingPhase(
    BreathingTechnique technique, {
    bool resume = false,
  }) {
    final phase = BreathingPlan.phaseFor(technique, _elapsedSeconds);

    _gaugeController.stop();
    _gaugeController.duration = Duration(seconds: phase.stepSeconds);

    if (resume && phase.stepSeconds > 0) {
      final completed = phase.stepSeconds - phase.remainingStepSeconds;
      final progress = (completed / phase.stepSeconds)
          .clamp(0.0, 1.0)
          .toDouble();
      _gaugeController.forward(from: progress);
    } else {
      _gaugeController.forward(from: 0);
    }

    unawaited(_announceMindMateVoice(technique));
  }

  Future<bool?> _confirmStart(BreathingTechnique technique) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        icon: const Icon(
          Icons.self_improvement_rounded,
          color: _BreathingPalette.green,
          size: 34,
        ),
        title: const Text('Ready to begin?'),
        content: Text(
          'Pattern: ${BreathingPlan.patternLabel(technique)}. '
          'Find a comfortable position and breathe gently. '
          'Do not force your breath; stop if dizzy or uncomfortable. '
          'You can pause or leave anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _BreathingPalette.gold,
              foregroundColor: _BreathingPalette.ink,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
      setState(() => _elapsedSeconds = technique.durationSeconds);
      await _completeSession();
      return;
    }

    final oldPhase = BreathingPlan.phaseFor(technique, _elapsedSeconds);

    setState(() => _elapsedSeconds = next);

    final newPhase = BreathingPlan.phaseFor(technique, _elapsedSeconds);

    if (oldPhase.stepIndex != newPhase.stepIndex) {
      _beginBreathingPhase(technique);
    }
  }

  Future<void> _completeSession() async {
    final technique = _activeTechnique;
    final startedAt = _startedAt;

    if (technique == null || startedAt == null || _isCompleted) return;

    final userId = context.read<UserProvider>().user?.id;
    final breathingProvider = context.read<BreathingProvider>();

    _timer?.cancel();
    _gaugeController.stop();

    setState(() {
      _isCompleted = true;
      _isPaused = false;
    });

    await _breathingSound.stop();
    ++_voiceToken;
    unawaited(_voicePlayer.stop());
    unawaited(_musicPlayer.pause());
    unawaited(_playCue('session_complete.mp3'));

    if (userId == null || userId.trim().isEmpty) return;

    final saved = await breathingProvider.completeSession(
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
      if (!mounted) return;
      await _readProviderOrNull<ReportProvider>()?.refreshWeeklyReport(userId);
    } catch (error) {
      debugPrint('Breathing report refresh unavailable: $error');
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
    if (_activeTechnique == null || _isCompleted) return;

    setState(() => _isPaused = !_isPaused);

    if (_isPaused) {
      _gaugeController.stop();
      await _breathingSound.stop();
      ++_voiceToken;
      unawaited(_voicePlayer.stop());
      await _musicPlayer.pause();
      await _cuePlayer.stop();
    } else {
      final technique = _activeTechnique;
      if (technique != null) {
        _beginBreathingPhase(technique, resume: true);
      }
      unawaited(_playMusicIfEnabled());
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Leave this session?'),
        content: const Text(
          'Your breathing session is recorded only '
          'when the guided session finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _BreathingPalette.gold,
              foregroundColor: _BreathingPalette.ink,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldExit != true || !mounted) return;

    _timer?.cancel();
    await _breathingSound.stop();
    ++_voiceToken;
    unawaited(_voicePlayer.stop());
    await _musicPlayer.pause();
    await _cuePlayer.stop();

    if (!mounted) return;

    _gaugeController.stop();
    _gaugeController.duration = const Duration(milliseconds: 1800);
    _gaugeController.repeat();

    setState(() {
      _activeTechnique = null;
      _activeMood = null;
      _startedAt = null;
      _elapsedSeconds = 0;
      _isPaused = false;
      _isCompleted = false;
    });
  }

  Future<void> _toggleSound() async {
    setState(() => _soundEnabled = !_soundEnabled);

    if (_soundEnabled) {
      final technique = _activeTechnique;

      if (technique != null && !_isPaused && !_isCompleted) {
        unawaited(_announceMindMateVoice(technique));
      }

      unawaited(_playMusicIfEnabled());
    } else {
      await _breathingSound.stop();
      ++_voiceToken;
      unawaited(_voicePlayer.stop());
      await _musicPlayer.pause();
      await _cuePlayer.stop();
    }
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);

    await _breathingSound.setVolume(value);

    try {
      await _musicPlayer.setVolume(value * 0.65);
      await _cuePlayer.setVolume(value);
      await _voicePlayer.setVolume((value * 0.42).clamp(0.0, 1.0));
    } catch (error) {
      debugPrint('Audio volume adjustment: $error');
    }
  }

  // Spoken phase cues. Existing phase timings, visuals, and session saving remain unchanged.
  // MindMate female breathing guidance.
  // Always use the new calm_*.mp3 files.
  // Never fall back to the old voice recordings.
  Future<void> _announceMindMateVoice(BreathingTechnique technique) async {
    if (!mounted ||
        !_soundEnabled ||
        _isPaused ||
        _isCompleted ||
        _activeTechnique == null) {
      return;
    }
    final label = BreathingPlan.phaseFor(
      technique,
      _elapsedSeconds,
    ).label.toLowerCase();

    String? phase;

    if (label.contains('exhale') || label.contains('breathe out')) {
      phase = 'exhale';
    } else if (label.contains('inhale') || label.contains('breathe in')) {
      phase = 'inhale';
    } else if (label.contains('hold') || label.contains('pause')) {
      phase = 'hold';
    }

    if (phase == null) return;
    final asset =
        'assets/audio/breathing/${_voiceGender == 'male' ? 'male' : 'calm'}_$phase.mp3';
    final token = ++_voiceToken;
    try {
      await _voicePlayer.stop();
      if (!_voiceStillAllowed(token)) return;
      debugPrint('MINDMATE VOICE: $asset');
      await _voicePlayer.setAsset(asset);
      if (!_voiceStillAllowed(token)) return;
      await _voicePlayer.setVolume((_volume * 0.85).clamp(0.0, 1.0));
      await _voicePlayer.setSpeed(_voiceGender == 'male' ? 1.0 : 0.92);
      if (!_voiceStillAllowed(token)) return;
      await _voicePlayer.play();
    } catch (error) {
      debugPrint('MINDMATE VOICE ERROR: $error');
    }
  }

  bool _voiceStillAllowed(int token) =>
      mounted &&
      token == _voiceToken &&
      _soundEnabled &&
      !_isPaused &&
      !_isCompleted &&
      _activeTechnique != null;

  Future<void> _playMusicIfEnabled() async {
    if (!_soundEnabled ||
        _isPaused ||
        _isCompleted ||
        _activeTechnique == null ||
        !_audioAssetsChecked ||
        !_ambientReady) {
      return;
    }

    try {
      await _musicPlayer.setVolume(_volume * 0.65);
      unawaited(_musicPlayer.play());
    } catch (error) {
      debugPrint('Ambient audio unavailable: $error');
    }
  }

  Future<void> _playCue(String fileName) async {
    if (!_soundEnabled || !_audioAssetsChecked) return;

    final asset = 'assets/audio/breathing/$fileName';

    if (!_availableAudioAssets.contains(asset)) return;

    try {
      await _cuePlayer.setAsset(asset);
      await _cuePlayer.setVolume(_volume);
      unawaited(_cuePlayer.play());
    } catch (error) {
      debugPrint('Audio cue unavailable: $error');
    }
  }
}

// Scene-aware foreground; the parent animates this color on theme changes.
Color _sceneTextColor(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.color ?? _BreathingPalette.ink;

class _VoicePicker extends StatelessWidget {
  const _VoicePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        'Voice',
        style: TextStyle(
          color: _sceneTextColor(context),
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'female', label: Text('Female')),
            ButtonSegment(value: 'male', label: Text('Male')),
          ],
          selected: {value},
          onSelectionChanged: (values) => onChanged(values.first),
        ),
      ),
    ],
  );
}

class _QuickSoundPicker extends StatelessWidget {
  const _QuickSoundPicker({required this.track, required this.onChanged});
  final int track;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.music_note_rounded, size: 18),
      const SizedBox(width: 6),
      Text(
        'Relaxation sound',
        style: TextStyle(
          fontSize: 12,
          color: _sceneTextColor(context),
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButton<int>(
          value: track,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 0; i < _ambientTracks.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  _ambientTracks[i],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _BreathingPalette.ink,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    ],
  );
}

class _BreathingCustomizations extends StatelessWidget {
  const _BreathingCustomizations({
    required this.track,
    required this.theme,
    required this.onTrackChanged,
    required this.onThemeChanged,
  }) : compact = false;
  final int track;
  final int theme;
  final ValueChanged<int> onTrackChanged;
  final ValueChanged<int> onThemeChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.77),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: _BreathingPalette.ink,
            displayColor: _BreathingPalette.ink,
          ),
          iconTheme: const IconThemeData(color: _BreathingPalette.ink),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Relaxation sound',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              key: ValueKey('music-$track'),
              initialValue: track,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.music_note_rounded),
              ),
              items: [
                for (var i = 0; i < _ambientTracks.length; i++)
                  DropdownMenuItem(value: i, child: Text(_ambientTracks[i])),
              ],
              onChanged: (value) {
                if (value != null) onTrackChanged(value);
              },
            ),
            const SizedBox(height: 14),
            const Text(
              'Peaceful background',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _breathingThemes.length; i++) ...[
                    ChoiceChip(
                      label: Text(_breathingThemes[i]),
                      selected: theme == i,
                      onSelected: (_) => onThemeChanged(i),
                      selectedColor: _themeColors[i][1],
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _BreathingThemePainter extends CustomPainter {
  const _BreathingThemePainter(this.theme);
  final int theme;
  @override
  void paint(Canvas canvas, Size size) {
    final color = _themeColors[theme][1];
    for (var i = 0; i < 5; i++) {
      final center = Offset(
        size.width * (0.14 + (i * 0.19)),
        size.height * (0.14 + (i.isEven ? 0.11 : 0.65)),
      );
      final radius = size.width * (0.25 + i * 0.035);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.23), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BreathingThemePainter oldDelegate) =>
      oldDelegate.theme != theme;
}

// ============================================================
// BREATHING SETUP SCREEN
// ============================================================

class _BreathingSetup extends StatelessWidget {
  const _BreathingSetup({
    super.key,
    required this.selectedMood,
    required this.voiceGender,
    required this.onVoiceChanged,
    required this.selectedTrack,
    required this.selectedTheme,
    required this.onTrackChanged,
    required this.onThemeChanged,
    required this.animation,
    required this.onMoodChanged,
    required this.onStart,
  });

  final _BreathingMood selectedMood;
  final String voiceGender;
  final ValueChanged<String?> onVoiceChanged;
  final int selectedTrack;
  final int selectedTheme;
  final ValueChanged<int> onTrackChanged;
  final ValueChanged<int> onThemeChanged;
  final Animation<double> animation;
  final ValueChanged<_BreathingMood> onMoodChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final preview = selectedMood.toTechnique(
      minutes: _MindfulBreathingScreenState._fixedSessionMinutes,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sphereSize = math.min(constraints.maxWidth * .72, 300.0);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 46),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BreathingHeader(),
                  SizedBox(height: constraints.maxHeight < 720 ? 18 : 32),
                  Center(
                    child: _BreathingSphere(
                      size: sphereSize,
                      animation: animation,
                    ),
                  ),
                  SizedBox(height: constraints.maxHeight < 720 ? 24 : 42),
                  Text(
                    'Breath to reduce',
                    style: TextStyle(
                      color: _sceneTextColor(context),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MoodSelector(
                    selectedMood: selectedMood,
                    onMoodChanged: onMoodChanged,
                  ),
                  const SizedBox(height: 22),
                  _BreathingCustomizations(
                    track: selectedTrack,
                    theme: selectedTheme,
                    onTrackChanged: onTrackChanged,
                    onThemeChanged: onThemeChanged,
                  ),
                  const SizedBox(height: 20),
                  _ResearchBackedPattern(technique: preview),
                  const SizedBox(height: 20),
                  const Spacer(),
                  _VoicePicker(value: voiceGender, onChanged: onVoiceChanged),
                  const SizedBox(height: 12),
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

// ============================================================
// RESEARCH INFORMATION
// ============================================================

class _ResearchBackedPattern extends StatelessWidget {
  const _ResearchBackedPattern({required this.technique});

  final BreathingTechnique technique;

  @override
  Widget build(BuildContext context) {
    final evidence = BreathingPlan.evidenceFor(technique);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _BreathingPalette.mutedGreen.withValues(alpha: .30),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: _BreathingPalette.ink,
            displayColor: _BreathingPalette.ink,
          ),
          iconTheme: const IconThemeData(color: _BreathingPalette.ink),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your breathing pattern',
              style: TextStyle(
                color: _BreathingPalette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final step in technique.pattern.steps)
                  Chip(
                    label: Text('${step.label} ${step.seconds}s'),
                    backgroundColor: const Color(0xFFEAF5F0),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (technique.hasBreathHold)
              const Text(
                'Includes breath holds. If holding feels uncomfortable, '
                'choose Anxiety or Overwhelm for a pattern without holds.',
                style: TextStyle(color: _BreathingPalette.ink, fontSize: 12),
              ),
            const SizedBox(height: 6),
            Text(
              'Evidence: ${evidence.source}',
              style: const TextStyle(
                color: _BreathingPalette.mutedGreen,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showBreathingEvidence(context, technique),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Scientific basis & limitations'),
              ),
            ),
            const Text(
              'Breathe gently; never force a count. Stop if dizzy or '
              'uncomfortable. Wellness support only, not treatment.',
              style: TextStyle(color: _BreathingPalette.ink, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showBreathingEvidence(
  BuildContext context,
  BreathingTechnique technique,
) async {
  final evidence = BreathingPlan.evidenceFor(technique);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Scientific basis'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pattern: ${BreathingPlan.patternLabel(technique)}'),
            const SizedBox(height: 12),
            Text(
              evidence.source,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(evidence.title),
            const SizedBox(height: 10),
            Text(evidence.summary),
            const SizedBox(height: 10),
            Text('Evidence limits: ${evidence.limitations}'),
            const SizedBox(height: 10),
            SelectableText(evidence.url),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: evidence.url));

            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Source link copied')),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy source link'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

// ============================================================
// ACTIVE BREATHING PLAYER
// ============================================================

class _BreathingPlayer extends StatelessWidget {
  const _BreathingPlayer({
    super.key,
    required this.technique,
    required this.mood,
    required this.selectedTrack,
    required this.selectedTheme,
    required this.onTrackChanged,
    required this.onThemeChanged,
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
  final int selectedTrack;
  final int selectedTheme;
  final ValueChanged<int> onTrackChanged;
  final ValueChanged<int> onThemeChanged;
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
    final progress = (elapsedSeconds / technique.durationSeconds).clamp(
      0.0,
      1.0,
    );
    final phase = BreathingPlan.phaseFor(technique, elapsedSeconds);

    final previousIndex =
        (phase.stepIndex - 1) % technique.pattern.steps.length;
    final previousLabel = technique.pattern.steps[previousIndex].label
        .toLowerCase();
    final holdExpanded = previousLabel.contains('inhale');

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
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 42),
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  _BreathingHeader(
                    onClose: onExit,
                    trailing: _CircleIconButton(
                      icon: soundEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      tooltip: soundEnabled ? 'Mute sound' : 'Enable sound',
                      onPressed: onToggleSound,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _CircleIconButton(
                      icon: Icons.replay_rounded,
                      tooltip: 'Restart',
                      onPressed: onRestart,
                    ),
                  ),
                  _QuickSoundPicker(
                    track: selectedTrack,
                    onChanged: onTrackChanged,
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  _BreathingSphere(
                    size: sphereSize,
                    animation: gaugeAnimation,
                    progress: progress,
                    phase: _phaseTitle(phase.label),
                    holdExpanded: holdExpanded,
                  ),
                  const SizedBox(height: 8),
                  _BreathingWaveGuide(
                    animation: gaugeAnimation,
                    technique: technique,
                    elapsedSeconds: elapsedSeconds,
                    phase: _phaseTitle(phase.label),
                    holdExpanded: holdExpanded,
                    remainingSeconds: phase.remainingStepSeconds,
                    isPaused: isPaused,
                  ),
                  SizedBox(height: compact ? 8 : 12),

                  SizedBox(height: compact ? 12 : 18),
                  _MoodPill(mood: mood, selected: true, compact: true),
                  const SizedBox(height: 26),
                  _PhaseDots(
                    count: technique.pattern.steps.length,
                    activeIndex: phase.stepIndex,
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
                      value: volume.clamp(0.0, 1.0),
                      onChanged: soundEnabled ? onVolumeChanged : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Sound choice moved above breathing sphere.
                  // Background selection remains on setup screen.
                  const Spacer(),
                  Center(
                    child: SizedBox(
                      width: 185,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: onTogglePause,
                        icon: Icon(
                          isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 20,
                        ),
                        label: Text(isPaused ? 'Resume' : 'Pause'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _BreathingPalette.gold,
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: onExit,
                    child: Text(
                      'End session',
                      style: TextStyle(
                        color: _sceneTextColor(context),
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

  static String _phaseTitle(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('exhale')) return 'Exhale';
    if (lower.contains('hold') || lower.contains('pause')) return 'Hold';
    if (lower.contains('inhale')) return 'Inhale';
    return 'Breathe';
  }
}

// ============================================================
// HEADER AND BUTTONS
// ============================================================

class _BreathingHeader extends StatelessWidget {
  const _BreathingHeader({this.onClose, this.trailing});

  final VoidCallback? onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _CircleIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'Back',
              onPressed: onClose ?? () => Navigator.of(context).pop(),
            ),
          ),
          Text(
            'Breathing',
            style: TextStyle(
              color: _sceneTextColor(context),
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing!),
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

// ============================================================
// MOOD SELECTOR
// ============================================================

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
    final foreground = selected ? Colors.black : _sceneTextColor(context);

    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 15,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: selected
            ? _BreathingPalette.gold
            : Colors.white.withValues(alpha: .24),
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

// ============================================================
// BREATHING SPHERE
// ============================================================

class _BreathingSphere extends StatelessWidget {
  const _BreathingSphere({
    required this.size,
    required this.animation,
    this.progress = 0,
    this.phase,
    this.holdExpanded = false,
  }) : subtitle = null;

  final double size;
  final Animation<double> animation;
  final double progress;
  final String? phase;
  final String? subtitle;
  final bool holdExpanded;

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
            final t = Curves.easeInOut.transform(animation.value);

            final scale = switch (phase) {
              'Inhale' => .89 + .17 * t,
              'Exhale' => 1.06 - .17 * t,
              'Hold' => holdExpanded ? 1.06 : .89,
              _ => 1.0,
            };

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

// ============================================================
// MINDMATE BREATHING WAVE GUIDE
// Original circle and screen design are preserved.
// ============================================================

// MINDMATE_CONTINUOUS_WAVE_V2
// Continuous horizontal wave synced to the existing BreathingPlan.
// The original circle, UI, timer and intervention are untouched.

class _BreathingWaveGuide extends StatelessWidget {
  const _BreathingWaveGuide({
    required this.animation,
    required this.technique,
    required this.elapsedSeconds,
    required this.phase,
    required this.holdExpanded,
    required this.remainingSeconds,
    required this.isPaused,
  });

  final Animation<double> animation;
  final BreathingTechnique technique;
  final int elapsedSeconds;
  final String phase;
  final bool holdExpanded;
  final int remainingSeconds;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 106,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final currentPhase = BreathingPlan.phaseFor(
                technique,
                elapsedSeconds,
              );

              final completedInPhase =
                  currentPhase.stepSeconds - currentPhase.remainingStepSeconds;

              // Convert the existing phase animation to
              // continuous session time.
              final currentTime =
                  elapsedSeconds -
                  completedInPhase +
                  currentPhase.stepSeconds * animation.value;

              return CustomPaint(
                painter: _BreathingWavePainter(
                  technique: technique,
                  sessionTime: currentTime,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BreathingWavePainter extends CustomPainter {
  const _BreathingWavePainter({
    required this.technique,
    required this.sessionTime,
  });

  final BreathingTechnique technique;
  final double sessionTime;

  static const double _pixelsPerSecond = 17.0;

  // A fixed ball position lets the waveform scroll
  // continuously underneath it.
  static const double _ballPosition = 0.35;

  double _heightAt(double time) {
    final steps = technique.pattern.steps;

    if (steps.isEmpty) return 0.5;

    final cycleSeconds = steps.fold<int>(0, (sum, step) => sum + step.seconds);

    if (cycleSeconds <= 0) return 0.5;

    // Dart's modulo handles negative sample times,
    // allowing the wave to extend to the left.
    var position = time % cycleSeconds;

    // Start at the bottom of the wave.
    var level = 0.0;

    for (final step in steps) {
      final duration = step.seconds.toDouble();

      if (duration <= 0) continue;

      final label = step.label.toLowerCase();

      final isInhale = label.contains('inhale') || label.contains('breathe in');

      final isExhale =
          label.contains('exhale') || label.contains('breathe out');

      final isHold = label.contains('hold') || label.contains('pause');

      // For normal breathing patterns:
      // inhale -> upper wave
      // hold -> flat line
      // exhale -> lower wave
      final target = isInhale
          ? 1.0
          : isExhale
          ? 0.0
          : level;

      if (position < duration) {
        final progress = (position / duration).clamp(0.0, 1.0);

        // Smooth slope at phase transitions.
        final eased = progress * progress * (3 - 2 * progress);

        if (isHold) return level;

        if (!isInhale && !isExhale) {
          // Gentle neutral movement for
          // non-counted mindfulness patterns.
          return 0.5;
        }

        return level + (target - level) * eased;
      }

      level = target;
      position -= duration;
    }

    return level;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final width = size.width;
    final height = size.height;

    final top = height * 0.18;
    final bottom = height * 0.82;

    final ballX = width * _ballPosition;

    double yAt(double x) {
      final secondsOffset = (x - ballX) / _pixelsPerSecond;

      // Future waveform is drawn to the right;
      // past waveform exits on the left.
      final sampleTime = sessionTime + secondsOffset;

      final level = _heightAt(sampleTime);

      return bottom - (bottom - top) * level;
    }

    final wave = Path();

    wave.moveTo(0, yAt(0));

    // Fine sampling creates a smooth moving curve.
    for (double x = 2; x <= width; x += 2) {
      wave.lineTo(x, yAt(x));
    }

    // Soft background glow.
    canvas.drawPath(
      wave,
      Paint()
        ..color = _BreathingPalette.mutedGreen.withValues(alpha: 0.17)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // Original MindMate green line.
    canvas.drawPath(
      wave,
      Paint()
        ..color = _BreathingPalette.green
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    final ballCenter = Offset(ballX, yAt(ballX));

    // Golden ball shadow.
    canvas.drawCircle(
      ballCenter + const Offset(0, 3),
      15,
      Paint()
        ..color = _BreathingPalette.ink.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Golden breathing ball.
    canvas.drawCircle(ballCenter, 13, Paint()..color = _BreathingPalette.gold);

    canvas.drawCircle(
      ballCenter - const Offset(4, 4),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(covariant _BreathingWavePainter oldDelegate) {
    return oldDelegate.sessionTime != sessionTime ||
        oldDelegate.technique != technique;
  }
}

// ============================================================
// SESSION PROGRESS
// ============================================================

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

// ============================================================
// GOLD ACTION BUTTON
// ============================================================

class _GoldActionButton extends StatelessWidget {
  const _GoldActionButton({required this.label, required this.onPressed})
    : icon = null;

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 26),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// COMPLETION SCREEN
// ============================================================

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
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: _BreathingPalette.ink,
            displayColor: _BreathingPalette.ink,
          ),
          iconTheme: const IconThemeData(color: _BreathingPalette.ink),
        ),
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
                    'Notice one thing that feels softer now. '
                    'Your body may need a few quiet seconds before moving on.',
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
      ),
    );
  }
}

// ============================================================
// BACKGROUND PAINTER
// ============================================================

// ignore: unused_element
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
      Offset(size.width * .14, size.height * .11),
      size.width * .42,
      const Color(0x66FFFFFF),
    );

    _drawGlow(
      canvas,
      Offset(size.width * .92, size.height * .22),
      size.width * .46,
      const Color(0x55FFD06A),
    );

    _drawGlow(
      canvas,
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
      ..color = const Color(0xFF9DBFAA).withValues(alpha: .23);

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

// ============================================================
// BREATHING SPHERE PAINTER
// ============================================================

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

    final shineCenter = Offset(
      size.width * (.32 + animation * .05),
      size.height * .32,
    );

    final shinePaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: .9),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(center: shineCenter, radius: radius * .22),
          );

    canvas.drawCircle(shineCenter, radius * .22, shinePaint);

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

// ============================================================
// MOOD MODELS AND BREATHING PATTERNS
// ============================================================

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

// ============================================================
// COLOR PALETTE
// ============================================================

class _BreathingPalette {
  const _BreathingPalette._();

  static const ink = Color(0xFF18233D);
  static const green = Color(0xFF8CB8AA);
  static const mutedGreen = Color(0xFF88A5A1);
  static const gold = Color(0xFFF7C85D);
}

// Five restrained, illustrated scenes. Pure Flutter Canvas: no image assets.
class _SimpleScenicBackdrop extends CustomPainter {
  const _SimpleScenicBackdrop(this.theme);
  final int theme;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    const skies = <List<Color>>[
      [Color(0xFFFFFAF2), Color(0xFFF4E4D5)], // Dawn mountains
      [Color(0xFFF1FAFC), Color(0xFFDCEFF0)], // Ocean
      [Color(0xFFF5FAF3), Color(0xFFE1EDDF)], // Garden
      [Color(0xFFF3F2FA), Color(0xFFE2E1F0)], // Quiet night
      [Color(0xFFFFF7F2), Color(0xFFF2E0DB)], // Sunset
    ];
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: skies[theme],
        ).createShader(bounds),
    );
    final w = size.width, h = size.height;
    final horizon = h * .76;

    void hill(double top, Color color, double depth) {
      final path = Path()
        ..moveTo(0, h)
        ..lineTo(0, top + 18)
        ..quadraticBezierTo(w * .23, top - depth, w * .47, top + 14)
        ..quadraticBezierTo(w * .75, top - depth * .55, w, top + 8)
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    if (theme == 0) {
      // Misty mountains: a sun and two overlapping mountain ranges.
      canvas.drawCircle(
        Offset(w * .79, h * .23),
        w * .075,
        Paint()..color = const Color(0xFFFFDDA6).withValues(alpha: .55),
      );
      hill(horizon - 18, const Color(0xFFBFC5C1).withValues(alpha: .25), 90);
      hill(horizon + 48, const Color(0xFF9DAFA6).withValues(alpha: .21), 55);
    } else if (theme == 1) {
      // Ocean: open horizon and gentle water ripples.
      canvas.drawCircle(
        Offset(w * .77, h * .25),
        w * .065,
        Paint()..color = const Color(0xFFFFE7B7).withValues(alpha: .62),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, horizon, w, h - horizon),
        Paint()..color = const Color(0xFFACD8DC).withValues(alpha: .34),
      );
      for (var i = 0; i < 6; i++) {
        final y = horizon + 18.0 + i * 27;
        final x = (i.isEven ? .12 : .34) * w;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + w * .37, y),
          Paint()
            ..color = Colors.white.withValues(alpha: .50)
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      }
    } else if (theme == 2) {
      // Zen garden: pale hill and simple botanical silhouettes at the edges.
      hill(horizon + 32, const Color(0xFFB8D1BC).withValues(alpha: .25), 42);
      final stemPaint = Paint()
        ..color = const Color(0xFF7EA88D).withValues(alpha: .25)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final leafPaint = Paint()
        ..color = const Color(0xFF9ABCA0).withValues(alpha: .26);
      for (final side in <double>[.06, .94]) {
        final x = w * side;
        canvas.drawLine(Offset(x, h), Offset(x, horizon - 65), stemPaint);
        for (var i = 0; i < 3; i++) {
          final y = horizon - 42.0 + i * 42;
          final dx = (i.isEven ? 20.0 : -20.0) * (side < .5 ? 1 : -1);
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x + dx, y), width: 48, height: 22),
            leafPaint,
          );
        }
      }
    } else if (theme == 3) {
      // Quiet night: crescent moon, tiny stars and distant hills.
      final moon = Offset(w * .78, h * .22);
      canvas.drawCircle(
        moon,
        w * .067,
        Paint()..color = Colors.white.withValues(alpha: .72),
      );
      canvas.drawCircle(
        moon + Offset(w * .028, -w * .018),
        w * .065,
        Paint()..color = const Color(0xFFF1F0FA),
      );
      for (final p in const <Offset>[
        Offset(.15, .18),
        Offset(.34, .12),
        Offset(.58, .30),
        Offset(.88, .37),
        Offset(.24, .43),
        Offset(.69, .48),
      ]) {
        canvas.drawCircle(
          Offset(p.dx * w, p.dy * h),
          1.8,
          Paint()..color = const Color(0xFF9B9DC6).withValues(alpha: .55),
        );
      }
      hill(horizon + 25, const Color(0xFFB8B6D1).withValues(alpha: .24), 58);
    } else {
      // Rose sunset: low setting sun and layered quiet landscape.
      canvas.drawCircle(
        Offset(w * .73, horizon - 38),
        w * .09,
        Paint()..color = const Color(0xFFF6C8A9).withValues(alpha: .55),
      );
      hill(horizon + 6, const Color(0xFFD6B8B5).withValues(alpha: .28), 55);
      hill(horizon + 68, const Color(0xFFBAAAA9).withValues(alpha: .20), 32);
    }
    // Subtle wash makes the content legible without hiding scenery.
    canvas.drawRect(
      bounds,
      Paint()..color = Colors.white.withValues(alpha: .09),
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleScenicBackdrop oldDelegate) =>
      oldDelegate.theme != theme;
}
