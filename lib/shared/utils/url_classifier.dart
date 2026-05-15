/// URL classification utilities ported from @steipete/summarize-core.
///
/// Sources:
/// - packages/core/src/content/url.ts
/// - packages/core/src/content/direct-media.ts
library;

final _youTubeIdPattern = RegExp(r'^[a-zA-Z0-9_-]{11}$');

const directVideoExtensions = [
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', 'wmv', 'flv', '3gp', 'ogv',
];

const directAudioExtensions = [
  'mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg', 'oga', 'wma', 'opus', 'weba',
];

const directMediaExtensions = [
  ...directVideoExtensions,
  ...directAudioExtensions,
];

const _podcastHosts = {
  'podcasts.apple.com',
  'open.spotify.com',
  'pca.st',
  'overcast.fm',
  'castro.fm',
  'pocketcasts.com',
  'breaker.audio',
  'radiopublic.com',
  'music.amazon.com',
  'podbean.com',
};

bool isYouTubeUrl(String rawUrl) {
  try {
    final host = Uri.parse(rawUrl).host.toLowerCase();
    return host == 'youtube.com' || host.endsWith('.youtube.com') || host == 'youtu.be';
  } catch (_) {
    final lower = rawUrl.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }
}

bool isYouTubeVideoUrl(String rawUrl) {
  try {
    final uri = Uri.parse(rawUrl);
    final host = uri.host.toLowerCase();

    if (host == 'youtu.be') {
      return uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty;
    }

    if (host != 'youtube.com' && !host.endsWith('.youtube.com')) {
      return false;
    }

    if (uri.path == '/watch') {
      return (uri.queryParameters['v']?.trim().isNotEmpty ?? false);
    }

    return uri.path.startsWith('/shorts/') ||
        uri.path.startsWith('/live/') ||
        uri.path.startsWith('/embed/') ||
        uri.path.startsWith('/v/');
  } catch (_) {
    return false;
  }
}

String? extractYouTubeVideoId(String rawUrl) {
  try {
    final uri = Uri.parse(rawUrl);
    final host = uri.host.toLowerCase();
    String? candidate;

    if (host == 'youtu.be') {
      candidate = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      if (uri.path.startsWith('/watch')) {
        candidate = uri.queryParameters['v'];
      } else if (uri.path.startsWith('/shorts/')) {
        candidate = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      } else if (uri.path.startsWith('/embed/')) {
        candidate = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      } else if (uri.path.startsWith('/v/')) {
        candidate = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      }
    }

    final trimmed = candidate?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _youTubeIdPattern.hasMatch(trimmed) ? trimmed : null;
  } catch (_) {
    return null;
  }
}

bool isDirectMediaUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    return directMediaExtensions.any((ext) => path.endsWith('.$ext'));
  } catch (_) {
    return false;
  }
}

bool isDirectMediaExtension(String ext) {
  return directMediaExtensions.contains(ext.toLowerCase());
}

String? inferDirectMediaKind(String value) {
  final lower = value.toLowerCase();
  for (final ext in directVideoExtensions) {
    if (lower.endsWith('.$ext')) return 'video';
  }
  for (final ext in directAudioExtensions) {
    if (lower.endsWith('.$ext')) return 'audio';
  }
  return null;
}

bool isDirectVideoInput(String value) {
  return inferDirectMediaKind(value) == 'video';
}

bool isPodcastHost(String url) {
  try {
    final host = Uri.parse(url).host.toLowerCase();
    return _podcastHosts.any((h) => host == h || host.endsWith('.$h'));
  } catch (_) {
    return false;
  }
}

bool isTwitterStatusUrl(String rawUrl) {
  try {
    final host = Uri.parse(rawUrl).host.toLowerCase();
    if (host != 'twitter.com' && host != 'x.com' && !host.endsWith('.twitter.com') && !host.endsWith('.x.com')) {
      return false;
    }
    return rawUrl.contains('/status/');
  } catch (_) {
    return rawUrl.toLowerCase().contains('/status/');
  }
}

bool shouldPreferUrlMode(String url) {
  return isYouTubeVideoUrl(url) ||
      isTwitterStatusUrl(url) ||
      isDirectMediaUrl(url) ||
      isPodcastHost(url);
}
