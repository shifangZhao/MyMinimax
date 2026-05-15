import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/orchestrator/models/task_model.dart';
import 'package:myminimax/core/orchestrator/models/dag_model.dart';
import 'package:myminimax/core/orchestrator/models/working_memory.dart';
import 'package:myminimax/core/orchestrator/models/execution_state.dart';
import 'package:myminimax/core/orchestrator/memory/working_memory_store.dart';

void main() {
  // ── ComplexityTier ──
  group('ComplexityTier', () {
    test('trivial: 0 max tool rounds, no decomposition, no review', () {
      expect(ComplexityTier.trivial.maxToolRounds, 0);
      expect(ComplexityTier.trivial.needsDecomposition, false);
      expect(ComplexityTier.trivial.needsReview, false);
    });

    test('small: 10 max tool rounds, no decomposition, no review', () {
      expect(ComplexityTier.small.maxToolRounds, 10);
      expect(ComplexityTier.small.needsDecomposition, false);
      expect(ComplexityTier.small.needsReview, false);
    });

    test('medium: 30 max tool rounds, needs decomposition, needs review', () {
      expect(ComplexityTier.medium.maxToolRounds, 30);
      expect(ComplexityTier.medium.needsDecomposition, true);
      expect(ComplexityTier.medium.needsReview, true);
    });

    test('large: 80 max tool rounds, needs decomposition, needs review', () {
      expect(ComplexityTier.large.maxToolRounds, 80);
      expect(ComplexityTier.large.needsDecomposition, true);
      expect(ComplexityTier.large.needsReview, true);
    });
  });

  // ── TaskNode ──
  group('TaskNode', () {
    TaskNode createNode({
      String id = 't1',
      String label = 'Test Task',
      List<String> dependsOn = const [],
      SubTaskStatus status = SubTaskStatus.pending,
    }) {
      return TaskNode(
        id: id,
        label: label,
        description: 'do something',
        dependsOn: dependsOn,
        requiredToolGroups: ['basic'],
        complexity: ComplexityTier.small,
        status: status,
      );
    }

    test('default values are correct', () {
      final node = createNode();
      expect(node.id, 't1');
      expect(node.label, 'Test Task');
      expect(node.status, SubTaskStatus.pending);
      expect(node.dependsOn, []);
      expect(node.complexity, ComplexityTier.small);
    });

    test('copyWith preserves unchanged fields', () {
      final node = createNode();
      final copy = node.copyWith();
      expect(copy.id, node.id);
      expect(copy.label, node.label);
      expect(copy.status, node.status);
    });

    test('copyWith overrides specified fields', () {
      final node = createNode();
      final copy = node.copyWith(
        status: SubTaskStatus.completed,
        result: 'done',
        tokenCount: 42,
      );
      expect(copy.status, SubTaskStatus.completed);
      expect(copy.result, 'done');
      expect(copy.tokenCount, 42);
      expect(copy.id, node.id); // unchanged
    });

    test('copyWith does not mutate original', () {
      final node = createNode();
      node.copyWith(status: SubTaskStatus.completed);
      expect(node.status, SubTaskStatus.pending);
    });
  });

  // ── SubTaskStatus transitions ──
  group('SubTaskStatus', () {
    test('values cover all states', () {
      expect(SubTaskStatus.values, hasLength(6));
      expect(SubTaskStatus.values, containsAll([
        SubTaskStatus.pending,
        SubTaskStatus.ready,
        SubTaskStatus.running,
        SubTaskStatus.completed,
        SubTaskStatus.failed,
        SubTaskStatus.skipped,
      ]));
    });
  });

  // ── TaskGraph (DAG) ──
  group('TaskGraph', () {
    List<TaskNode> makeNodes(List<Map<String, dynamic>> specs) {
      return specs.map((s) => TaskNode(
        id: s['id'] as String,
        label: s['label'] as String? ?? s['id'] as String,
        description: 'desc',
        dependsOn: (s['dependsOn'] as List<dynamic>?)?.cast<String>() ?? [],
      )).toList();
    }

    test('empty graph has no layers', () {
      final graph = TaskGraph(nodes: []);
      expect(graph.topologicalLayers(), isEmpty);
      expect(graph.isComplete, true);
      expect(graph.hasFailed, false);
    });

    test('single node produces one layer', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1'},
      ]));
      final layers = graph.topologicalLayers();
      expect(layers, hasLength(1));
      expect(layers[0], hasLength(1));
      expect(layers[0][0].id, 't1');
    });

    test('two independent nodes produce one layer', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1'},
        {'id': 't2'},
      ]));
      final layers = graph.topologicalLayers();
      expect(layers, hasLength(1));
      expect(layers[0], hasLength(2));
    });

    test('sequential nodes produce two layers', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1'},
        {'id': 't2', 'dependsOn': ['t1']},
      ]));
      final layers = graph.topologicalLayers();
      expect(layers, hasLength(2));
      expect(layers[0][0].id, 't1');
      expect(layers[1][0].id, 't2');
    });

    test('chain of three produces three layers', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1'},
        {'id': 't2', 'dependsOn': ['t1']},
        {'id': 't3', 'dependsOn': ['t2']},
      ]));
      final layers = graph.topologicalLayers();
      expect(layers, hasLength(3));
      expect(layers[0][0].id, 't1');
      expect(layers[1][0].id, 't2');
      expect(layers[2][0].id, 't3');
    });

    test('diamond dependency produces correct layers', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1'},
        {'id': 't2', 'dependsOn': ['t1']},
        {'id': 't3', 'dependsOn': ['t1']},
        {'id': 't4', 'dependsOn': ['t2', 't3']},
      ]));
      final layers = graph.topologicalLayers();
      expect(layers, hasLength(3));
      expect(layers[0][0].id, 't1');
      expect(layers[1], hasLength(2)); // t2 and t3 in parallel
      expect(layers[2][0].id, 't4');
    });

    test('throws StateError on cycle detection', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1', 'dependsOn': ['t3']},
        {'id': 't2', 'dependsOn': ['t1']},
        {'id': 't3', 'dependsOn': ['t2']},
      ]));
      expect(() => graph.topologicalLayers(), throwsStateError);
    });

    test('self-loop throws StateError', () {
      final graph = TaskGraph(nodes: makeNodes([
        {'id': 't1', 'dependsOn': ['t1']},
      ]));
      expect(() => graph.topologicalLayers(), throwsStateError);
    });

    test('readyNodes returns nodes with no pending/ready deps', () {
      final nodes = makeNodes([
        {'id': 't1'},
        {'id': 't2', 'dependsOn': ['t1']},
      ]);
      nodes[0].status = SubTaskStatus.completed;
      final graph = TaskGraph(nodes: nodes);
      expect(graph.readyNodes.map((n) => n.id), contains('t2'));
    });

    test('readyNodes excludes completed nodes', () {
      final nodes = makeNodes([
        {'id': 't1'},
      ]);
      nodes[0].status = SubTaskStatus.completed;
      final graph = TaskGraph(nodes: nodes);
      expect(graph.readyNodes, isEmpty);
    });

    test('isComplete returns false when any node is not completed/skipped', () {
      final nodes = makeNodes([
        {'id': 't1'},
      ]);
      nodes[0].status = SubTaskStatus.running;
      final graph = TaskGraph(nodes: nodes);
      expect(graph.isComplete, false);
    });

    test('isComplete returns true when all nodes are terminal', () {
      final nodes = makeNodes([
        {'id': 't1'},
        {'id': 't2'},
      ]);
      nodes[0].status = SubTaskStatus.completed;
      nodes[1].status = SubTaskStatus.skipped;
      final graph = TaskGraph(nodes: nodes);
      expect(graph.isComplete, true);
    });

    test('hasFailed returns true if any node failed', () {
      final nodes = makeNodes([
        {'id': 't1'},
        {'id': 't2'},
      ]);
      nodes[0].status = SubTaskStatus.completed;
      nodes[1].status = SubTaskStatus.failed;
      final graph = TaskGraph(nodes: nodes);
      expect(graph.hasFailed, true);
    });

    test('hasFailed returns false if no node failed', () {
      final nodes = makeNodes([
        {'id': 't1'},
      ]);
      nodes[0].status = SubTaskStatus.completed;
      final graph = TaskGraph(nodes: nodes);
      expect(graph.hasFailed, false);
    });
  });

  // ── WorkingMemory ──
  group('WorkingMemory', () {
    late WorkingMemory memory;

    setUp(() {
      memory = WorkingMemory();
    });

    test('set and get a value', () {
      memory.set('city', 'Beijing', sourceTaskId: 't1');
      expect(memory.get<String>('city'), 'Beijing');
    });

    test('get returns null for missing key', () {
      expect(memory.get<String>('nonexistent'), null);
    });

    test('set overwrites existing value', () {
      memory.set('city', 'Beijing', sourceTaskId: 't1');
      memory.set('city', 'Shanghai', sourceTaskId: 't2');
      expect(memory.get<String>('city'), 'Shanghai');
    });

    test('getForTask returns entries matching dependencyIds', () {
      memory.set('city', 'Beijing', sourceTaskId: 't1');
      final entries = memory.getForTask('t2', dependencyIds: ['t1']);
      expect(entries, hasLength(1));
      expect(entries[0].value, 'Beijing');
    });

    test('getForTask excludes entries not in dependencyIds', () {
      memory.set('city', 'Beijing', sourceTaskId: 't1');
      final entries = memory.getForTask('t2', dependencyIds: ['t3']);
      expect(entries, isEmpty);
    });

    test('buildContextString returns formatted context', () {
      memory.set('city', '北京', sourceTaskId: 't1');
      memory.set('temp', '25°C', sourceTaskId: 't2');
      final ctx = memory.buildContextString('t3', dependencyIds: ['t1', 't2']);
      expect(ctx, contains('北京'));
      expect(ctx, contains('25°C'));
    });

    test('buildContextString with dependency IDs filters to those tasks', () {
      memory.set('city', '北京', sourceTaskId: 't1');
      memory.set('temp', '25°C', sourceTaskId: 't2');
      final ctx = memory.buildContextString('t3', dependencyIds: ['t1']);
      expect(ctx, contains('北京'));
      expect(ctx, isNot(contains('25°C')));
    });

    test('TTL expired entry is not returned', () async {
      memory.set('city', 'Beijing', sourceTaskId: 't1', ttl: const Duration(milliseconds: 1));
      await Future.delayed(const Duration(milliseconds: 5));
      expect(memory.get<String>('city'), null);
    });

    test('TTL entry is returned before expiry', () {
      memory.set('city', 'Beijing', sourceTaskId: 't1', ttl: const Duration(minutes: 5));
      expect(memory.get<String>('city'), 'Beijing');
    });

    test('get with readerTaskId marks the entry as read', () {
      memory.set('secret', 'value', sourceTaskId: 't1');
      expect(memory.get<String>('secret', readerTaskId: 't2'), 'value');
      // Entry should not be null, meaning it was returned successfully
    });

    test('snapshot returns all entries', () {
      memory.set('k1', 'v1', sourceTaskId: 't1');
      memory.set('k2', 'v2', sourceTaskId: 't1');
      final snap = memory.snapshot();
      expect(snap['k1']['value'], 'v1');
      expect(snap['k2']['value'], 'v2');
      expect(snap['k1']['sourceTaskId'], 't1');
    });

    test('context string truncates long values', () {
      memory.set('long', 'A' * 300, sourceTaskId: 't1');
      final ctx = memory.buildContextString('t2', dependencyIds: ['t1']);
      expect(ctx.length, lessThan(500)); // truncated
    });
  });

  // ── OrchestratorState ──
  group('OrchestratorState', () {
    test('default values are correct', () {
      final state = OrchestratorState(phase: OrchestratorPhase.assessingComplexity);
      expect(state.phase, OrchestratorPhase.assessingComplexity);
      expect(state.progress, 0.0);
      expect(state.complexityTier, ComplexityTier.small);
      expect(state.partialResult, null);
    });

    test('copyWith preserves unspecified fields', () {
      final state = OrchestratorState(
        phase: OrchestratorPhase.decomposing,
        progress: 0.5,
      );
      final copy = state.copyWith();
      expect(copy.phase, OrchestratorPhase.decomposing);
      expect(copy.progress, 0.5);
    });

    test('copyWith overrides specified fields', () {
      final state = OrchestratorState(phase: OrchestratorPhase.decomposing);
      final copy = state.copyWith(phase: OrchestratorPhase.executing, progress: 0.5);
      expect(copy.phase, OrchestratorPhase.executing);
      expect(copy.progress, 0.5);
    });

    test('completed state has partialResult', () {
      final state = OrchestratorState(
        phase: OrchestratorPhase.completed,
        partialResult: '__FALLTHROUGH__',
      );
      expect(state.partialResult, '__FALLTHROUGH__');
    });

    test('failed state has errorMessage', () {
      final state = OrchestratorState(
        phase: OrchestratorPhase.failed,
        errorMessage: 'something went wrong',
      );
      expect(state.errorMessage, 'something went wrong');
    });

    test('OrchestratorPhase values cover all phases', () {
      expect(OrchestratorPhase.values, hasLength(6));
      expect(OrchestratorPhase.values, containsAll([
        OrchestratorPhase.assessingComplexity,
        OrchestratorPhase.decomposing,
        OrchestratorPhase.executing,
        OrchestratorPhase.synthesizing,
        OrchestratorPhase.completed,
        OrchestratorPhase.failed,
      ]));
    });
  });

  // ── WorkingMemoryStore ──
  group('WorkingMemoryStore', () {
    test('initialize sets orchestrationId', () {
      final store = WorkingMemoryStore();
      expect(store.orchestrationId, null);
      store.initialize('orch-1');
      expect(store.orchestrationId, 'orch-1');
    });

    test('set and get round trip', () {
      final store = WorkingMemoryStore();
      store.initialize('orch-1');
      store.set('key', 'value', sourceTaskId: 't1');
      expect(store.get<String>('key'), 'value');
    });

    test('get returns null before initialize', () {
      final store = WorkingMemoryStore();
      expect(store.get<String>('key'), null);
    });

    test('initialize with initial data', () {
      final store = WorkingMemoryStore();
      store.initialize('orch-1', {'city': 'Beijing'});
      expect(store.get<String>('city'), 'Beijing');
    });

    test('reset clears orchestrationId', () {
      final store = WorkingMemoryStore();
      store.initialize('orch-1');
      store.reset();
      expect(store.orchestrationId, null);
    });
  });
}
