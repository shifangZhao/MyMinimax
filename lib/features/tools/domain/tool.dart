import 'package:equatable/equatable.dart';

enum ToolCategory { file, search, system, custom, memory, phone, map, cron }

class Tool extends Equatable {

  const Tool({
    required this.name,
    required this.description,
    required this.category,
    this.isEnabled = true,
  });
  final String name;
  final String description;
  final ToolCategory category;
  final bool isEnabled;

  @override
  List<Object?> get props => [name, description, category, isEnabled];
}

class InteractivePrompt {
  final String question;
  final List<String> options;
  final bool multiSelect;

  const InteractivePrompt({
    required this.question,
    required this.options,
    this.multiSelect = false,
  });
}

class ToolResult extends Equatable {

  const ToolResult({
    required this.toolName,
    required this.success,
    required this.output,
    this.error,
    this.data,
    this.interactive,
  });
  final String toolName;
  final bool success;
  final String output;
  final String? error;
  final String? data;
  final InteractivePrompt? interactive;

  @override
  List<Object?> get props => [toolName, success, output, error, data, interactive];
}