import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

import 'audioplayers.dart';

import 'package:ffi/ffi.dart' as ffi;

final _lib = Platform.isWindows ? DynamicLibrary.open("bass.dll") : null;

/// http://www.un4seen.com/doc/#bass/BASS_Init.html
/// BOOL BASS_Init(
///     int device,
///     DWORD freq,
///     DWORD flags,
///     HWND win,
///     GUID *clsid
/// );
final _BASS_Init = _lib.lookupFunction<
    Int32 Function(Int32, Uint32, Uint32, Uint32, Pointer),
    int Function(int, int, int, int, Pointer)>("BASS_Init");

/// http://www.un4seen.com/doc/#bass/BASS_StreamCreateURL.html
///
/// HSTREAM BASS_StreamCreateURL(
///     char *url,
///     DWORD offset,
///     DWORD flags,
///     DOWNLOADPROC *proc,
///     void *user
/// );
final _BASS_StreamCreateURL = _lib.lookupFunction<
    Uint32 Function(Pointer<ffi.Utf8>, Uint32, Uint32, Pointer, Pointer<Void>),
    int Function(
        Pointer<ffi.Utf8>, int, int, Pointer, Pointer<Void>)>("BASS_StreamCreateURL");

/// http://www.un4seen.com/doc/#bass/BASS_ChannelPlay.html
/// BOOL BASS_ChannelPlay(
///     DWORD handle,
///     BOOL restart
/// );
final _BASS_ChannelPlay = _lib.lookupFunction<
    Int32 Function(Uint32 handle, Int32 restart),
    int Function(int handle, int restart)>("BASS_ChannelPlay");

/// http://www.un4seen.com/doc/#bass/BASS_ChannelPause.html
///
/// BOOL BASS_ChannelPause(
///     DWORD handle
/// );
final _BASS_ChannelPause =
    _lib.lookupFunction<Int32 Function(Uint32 handle), int Function(int handle)>(
        "BASS_ChannelPause");

/// http://www.un4seen.com/doc/#bass/BASS_ChannelStop.html
///
/// BOOL BASS_ChannelStop(
///     DWORD handle
/// );
final _BASS_ChannelStop =
    _lib.lookupFunction<Int32 Function(Uint32 handle), int Function(int handle)>(
        "BASS_ChannelStop");

/// http://www.un4seen.com/doc/#bass/BASS_ChannelGetLength.html
///
/// QWORD BASS_ChannelGetLength(
///     DWORD handle,
///     DWORD mode
/// );
final _BASS_ChannelGetLength =
    _lib.lookupFunction<Int64 Function(Uint32, Uint32), int Function(int, int)>(
        "BASS_ChannelGetLength");

/// http://www.un4seen.com/doc/#bass/BASS_ChannelBytes2Seconds.html
/// double BASS_ChannelBytes2Seconds(
///     DWORD handle,
///     QWORD pos
/// );
final _BASS_ChannelBytes2Seconds =
    _lib.lookupFunction<Double Function(Uint32, Int64), double Function(int, int)>(
        "BASS_ChannelBytes2Seconds");

const int BASS_MUSIC_RAMPS = 0x400;
const int BASS_POS_BYTE = 0;
bool _isInit = false;

class WrappedPlayer {
  double pausedAt;
  double currentVolume = 1.0;
  ReleaseMode currentReleaseMode = ReleaseMode.RELEASE;
  String currentUrl;
  bool isPlaying = false;

  int player;

  bool ensureInit() {
    if (!_isInit) {
      _isInit = _BASS_Init(-1, 44100, 0, 0, nullptr) == 1;
      if (!_isInit) {
        throw "error BASS_Init";
      }
    }
    return _isInit;
  }

  void setUrl(String url, bool isLocal) {
    currentUrl = url;

    stop();
    recreateNode();
    if (isPlaying) {
      resume();
    }
  }

  void setVolume(double volume) {
    currentVolume = volume;
    // player?.volume = volume;
  }

  void recreateNode() {
    if (currentUrl == null) {
      return;
    }
    ensureInit();
    player = _BASS_StreamCreateURL(
        ffi.Utf8.toUtf8(currentUrl), 0, BASS_MUSIC_RAMPS, nullptr, nullptr);
    // player.loop = shouldLoop();
    // player.volume = currentVolume;
  }

  bool shouldLoop() => currentReleaseMode == ReleaseMode.LOOP;

  void setReleaseMode(ReleaseMode releaseMode) {
    currentReleaseMode = releaseMode;
    // player?.loop = shouldLoop();
  }

  void release() {
    player = null;
  }

  void play() {
    isPlaying = true;
    if (currentUrl == null) {
      return; // nothing to play yet
    }
    if (player == null) {
      recreateNode();
    } 
    _BASS_ChannelPlay(player, pausedAt == null || player == null ? 1 : 0);
    // player.play();
    // player.currentTime = position;
  }

  void resume() {
    play();
  }

  void pause() {
    // pausedAt = player.currentTime;
    if (player != null) _BASS_ChannelPause(player);
    isPlaying = false;
  }

  void stop() {
    pausedAt = 0;
    if (player != null) _BASS_ChannelStop(player);
    if (currentReleaseMode == ReleaseMode.RELEASE) {
      player = null;
    }
  }


  void setPlaybackRate(double playbackRate) {}

  int getDuration() {
    ensureInit();
    if (currentUrl == null) {
      return 0; // nothing to play yet
    }
    if (player == null) {
      recreateNode();
    }

    return (_BASS_ChannelBytes2Seconds(
                player, _BASS_ChannelGetLength(player, BASS_POS_BYTE)) *
            1000)
        .toInt();
  }
}

class AudioplayersWindows {
  // players by playerId
  static Map<String, WrappedPlayer> players = {};

  static WrappedPlayer getOrCreatePlayer(String playerId) {
    return players.putIfAbsent(playerId, () => WrappedPlayer());
  }

  static Future<WrappedPlayer> setUrl(String playerId, String url, bool isLocal) async {
    final WrappedPlayer player = getOrCreatePlayer(playerId);

    if (player.currentUrl == url) {
      return player;
    }

    player.setUrl(url, isLocal);
    return player;
  }

  static ReleaseMode parseReleaseMode(String value) {
    return ReleaseMode.values.firstWhere((e) => e.toString() == value);
  }

  static Future<int> invokeMethod(String method, Map<String, dynamic> arguments) async {
    final playerId = arguments['playerId'];
    switch (method) {
      case 'setUrl':
        final String url = arguments['url'];
        final bool isLocal = arguments['isLocal'];
        await setUrl(playerId, url, isLocal);
        return 1;
      case 'play':
        final String url = arguments['url'];
        final bool isLocal = arguments['isLocal'];
        final double volume = arguments['volume'] ?? 1.0;

        // 暂时不管 `stayAwake` 参数

        final player = await setUrl(playerId, url, isLocal);
        player.setVolume(volume);
        player.play();

        return 1;
      case 'pause':
        getOrCreatePlayer(playerId).pause();
        return 1;
      case 'stop':
        getOrCreatePlayer(playerId).stop();
        return 1;
      case 'resume':
        getOrCreatePlayer(playerId).resume();
        return 1;
      case 'setVolume':
        double volume = arguments['volume'] ?? 1.0;
        getOrCreatePlayer(playerId).setVolume(volume);
        return 1;
      case 'setReleaseMode':
        ReleaseMode releaseMode = parseReleaseMode(arguments['releaseMode']);
        getOrCreatePlayer(playerId).setReleaseMode(releaseMode);
        return 1;
      case 'release':
        getOrCreatePlayer(playerId).release();
        return 1;
      case 'getDuration':
        return getOrCreatePlayer(playerId).getDuration();
      case 'setPlaybackRate':
        getOrCreatePlayer(playerId).setPlaybackRate(arguments['playbackRate']);
        return 1;
      case 'seek':
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              "The audioplayers plugin for windows doesn't implement the method '$method'",
        );
    }
  }
}
