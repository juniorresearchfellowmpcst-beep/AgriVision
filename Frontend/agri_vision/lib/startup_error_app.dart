import 'package:flutter/material.dart';

/// Rendered in place of `App` when `bootstrap()` fails.
///
/// Deliberately standalone: it pulls in nothing from `src/`, because the
/// failure it reports may be in the very initialisation the rest of the app is
/// built on (env asset, plugins, repositories). The colours are literals for
/// the same reason - AppColors sits behind that same barrel.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, this.stackTrace, super.key});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriVision',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F6F4),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Color(0xFFE64848),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'AgriVision could not start',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F4D38),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Startup stopped before the app could load. What went '
                      'wrong is shown below.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFF4A4A4A),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD4D6DD)),
                      ),
                      child: SelectableText(
                        '$error',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFF1F1F1F),
                        ),
                      ),
                    ),
                    if (stackTrace != null) ...[
                      const SizedBox(height: 8),
                      Theme(
                        data: ThemeData(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            'Technical details',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF569150),
                            ),
                          ),
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 220,
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  '$stackTrace',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    height: 1.35,
                                    color: Color(0xFF6B6B6B),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
