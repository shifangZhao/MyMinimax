import 'tool_groups.dart';

/// Per-conversation tool activation state.
///
/// basic group is always active — no activation needed.
/// Other groups are added/removed via activate_tools() with +/- prefix semantics:
///   ["trend"]  → add trend group
///   ["-trend"] → remove trend group
///   []         → reset to basic only
class ToolActivationState {
  Set<ToolGroup> _activeGroups = {};

  /// Currently active groups (basic is implied, always active)
  Set<ToolGroup> get activeGroups => Set.unmodifiable(_activeGroups);

  bool get hasActiveGroups => true; // basic is always available

  void addGroups(Set<ToolGroup> groups) => _activeGroups.addAll(groups);

  void removeGroups(Set<ToolGroup> groups) => _activeGroups.removeAll(groups);

  /// Replace current groups with [groups]. Used for reset (empty set).
  void activate(Set<ToolGroup> groups) {
    _activeGroups = Set.from(groups);
  }

  /// Get tool names that should currently be available.
  /// basic group tools are always included.
  Set<String> get activeToolNames {
    final names = ToolGroupRegistry.toolNamesInGroup(ToolGroup.basic);
    names.addAll(ToolGroupRegistry.toolNamesInGroups(_activeGroups));
    return names;
  }

  bool isToolActive(String toolName) {
    final group = ToolGroupRegistry.groupOf(toolName);
    if (group == null) return false;
    if (group == ToolGroup.basic) return true;
    return _activeGroups.contains(group);
  }

  static Set<ToolGroup> inferGroups(Set<String> toolNames) {
    return ToolGroupRegistry.groupsForToolNames(toolNames);
  }

  void reset() => _activeGroups.clear();
}
