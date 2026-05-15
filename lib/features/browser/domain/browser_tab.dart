import 'package:uuid/uuid.dart';
import '../../../core/browser/browser_constants.dart';

class BrowserTab {

  const BrowserTab({
    required this.id,
    this.title = '',
    this.url = '',
    this.initialUrl,
    this.isLoading = false,
    this.scrollY = 0,
    this.canGoBack = false,
    this.canGoForward = false,
  });

  factory BrowserTab.createNew({String? url}) => BrowserTab(
        id: const Uuid().v4(),
        initialUrl: url ?? BrowserConstants.homeUrl,
        url: url ?? BrowserConstants.homeUrl,
      );
  final String id;
  final String title;
  final String url;
  final String? initialUrl;
  final bool isLoading;
  final double scrollY;
  final bool canGoBack;
  final bool canGoForward;

  BrowserTab copyWith({
    String? id,
    String? title,
    String? url,
    String? initialUrl,
    bool? isLoading,
    double? scrollY,
    bool? canGoBack,
    bool? canGoForward,
  }) =>
      BrowserTab(
        id: id ?? this.id,
        title: title ?? this.title,
        url: url ?? this.url,
        initialUrl: initialUrl ?? this.initialUrl,
        isLoading: isLoading ?? this.isLoading,
        scrollY: scrollY ?? this.scrollY,
        canGoBack: canGoBack ?? this.canGoBack,
        canGoForward: canGoForward ?? this.canGoForward,
      );
}
