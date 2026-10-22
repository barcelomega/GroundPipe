import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'player/ng_audio_handler.dart';
import 'ui/screens/discover_screen_new.dart';
import 'ui/screens/library_screen_new.dart';
import 'ui/screens/timeline_screen.dart';
import 'ui/screens/recommended_screen.dart';
import 'ui/widgets/mini_player.dart';
import 'viewmodel/authors_viewmodel.dart';

import 'viewmodel/ng_viewmodel.dart';
import 'viewmodel/library_viewmodel.dart';
import 'viewmodel/recommendations_viewmodel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap Flutter's decoded image cache; metadata LRUs in NgRepository have
  // separate small entry limits.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 384 * 1024 * 1024;
  runApp(NgMusicApp(handler: NgAudioHandler()));
}

class NgMusicApp extends StatelessWidget {
  final NgAudioHandler handler;
  const NgMusicApp({super.key, required this.handler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthorsViewModel()),
        ChangeNotifierProvider(
            create: (context) => NgViewModel(handler,
                authors: context.read<AuthorsViewModel>())),
        ChangeNotifierProvider(create: (_) => LibraryViewModel()),
        ChangeNotifierProvider(create: (_) => TimelineProgress()),
        ChangeNotifierProvider(
          create: (context) => RecommendationsViewModel(
            context.read<LibraryViewModel>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'GroundPipe',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.dark,
        home: const RootShell(),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _currentIndex = 0;

  static const _screens = [
    DiscoverScreen(),
    RecommendedScreen(),
    TimelineScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer<RecommendationsViewModel>(
            builder: (context, recommendations, _) {
              if (!recommendations.isGathering) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Gathering statistics, please wait',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Consumer<TimelineProgress>(
            builder: (context, progress, _) {
              if (!progress.isLoading) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            progress.isAssembling
                                ? 'Loading timeline... Sorting tracks'
                                : 'Loading timeline...',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const MiniPlayer(),

          // Navigation
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Discover',
              ),
              NavigationDestination(
                icon: Icon(Icons.star_border),
                selectedIcon: Icon(Icons.star),
                label: 'Recommended',
              ),
              NavigationDestination(
                icon: Icon(Icons.dynamic_feed_outlined),
                selectedIcon: Icon(Icons.dynamic_feed),
                label: 'Timeline',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
