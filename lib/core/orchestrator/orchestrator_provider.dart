import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/chat/presentation/chat_page.dart';
import 'orchestrator_engine.dart';

/// Provider for the OrchestratorEngine singleton.
final orchestratorEngineProvider = Provider<OrchestratorEngine>((ref) {
  final client = ref.watch(minimaxClientProvider);
  return OrchestratorEngine(client: client);
});
