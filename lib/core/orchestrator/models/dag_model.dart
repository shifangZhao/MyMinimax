import 'task_model.dart';

/// A directed acyclic graph of sub-tasks.
class TaskGraph {
  TaskGraph({required this.nodes});

  final List<TaskNode> nodes;

  /// Nodes whose dependencies are all satisfied and ready to run.
  List<TaskNode> get readyNodes {
    return nodes.where((n) {
      if (n.status != SubTaskStatus.pending && n.status != SubTaskStatus.ready) {
        return false;
      }
      return n.dependsOn.every((depId) {
        final dep = nodes.firstWhere((n) => n.id == depId);
        return dep.status == SubTaskStatus.completed;
      });
    }).toList();
  }

  bool get isComplete {
    return nodes.every((n) =>
        n.status == SubTaskStatus.completed || n.status == SubTaskStatus.skipped);
  }

  bool get hasFailed => nodes.any((n) => n.status == SubTaskStatus.failed);

  /// Topological sort using Kahn's algorithm.
  /// Returns layers where each layer's nodes can run in parallel.
  /// Throws [StateError] if a cycle is detected.
  List<List<TaskNode>> topologicalLayers() {
    final inDegree = <String, int>{};
    final adj = <String, List<String>>{};

    for (final n in nodes) {
      inDegree[n.id] = n.dependsOn.length;
      adj[n.id] = [];
    }
    for (final n in nodes) {
      for (final dep in n.dependsOn) {
        adj[dep]!.add(n.id);
      }
    }

    final layers = <List<TaskNode>>[];
    var queue = <String>[];
    for (final n in nodes) {
      if (inDegree[n.id] == 0) queue.add(n.id);
    }

    while (queue.isNotEmpty) {
      final layer = <TaskNode>[];
      final nextQueue = <String>[];
      for (final id in queue) {
        layer.add(nodes.firstWhere((n) => n.id == id));
        for (final neighbor in adj[id]!) {
          inDegree[neighbor] = inDegree[neighbor]! - 1;
          if (inDegree[neighbor] == 0) nextQueue.add(neighbor);
        }
      }
      layers.add(layer);
      queue = nextQueue;
    }

    final totalNodes = layers.fold<int>(0, (s, l) => s + l.length);
    if (totalNodes != nodes.length) {
      throw StateError('Cycle detected in task graph');
    }

    return layers;
  }
}
