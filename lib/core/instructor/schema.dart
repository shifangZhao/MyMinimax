/// Schema definition for structured LLM output.
///
/// A hand-written descriptor that wraps a JSON Schema [inputSchema],
/// a [fromJson] decoder, and an optional [toJson] encoder.
///
/// The JSON Schema format is identical to [ToolDefinition.inputSchema]
/// in ToolRegistry — no new conventions to learn.
library;

import 'dart:convert';

/// Describes what structured data to extract from the LLM.
///
/// ```dart
/// final userSchema = SchemaDefinition(
///   name: 'extract_user',
///   description: 'Extract user profile from text',
///   inputSchema: {
///     'type': 'object',
///     'properties': {
///       'name': {'type': 'string', 'description': 'Full name'},
///       'age':  {'type': 'integer'},
///     },
///     'required': ['name', 'age'],
///   },
///   fromJson: (json) => UserProfile.fromJson(json),
/// );
/// ```
class SchemaDefinition {

  const SchemaDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.fromJson,
    this.toJson,
  });
  /// Unique tool name sent to the LLM. Must be a valid identifier
  /// (letters, numbers, underscores).
  final String name;

  /// Human-readable description of what this schema extracts.
  final String description;

  /// JSON Schema object (hand-written). Follows JSON Schema spec.
  /// This is the SAME format used in ToolRegistry.inputSchema.
  final Map<String, dynamic> inputSchema;

  /// Decoder: converts the LLM's JSON output into a typed Dart object.
  final dynamic Function(Map<String, dynamic> json) fromJson;

  /// Optional encoder: converts a typed Dart object back to JSON.
  final Map<String, dynamic> Function(dynamic obj)? toJson;

  /// Convert to Anthropic Messages API tool format.
  /// Mirrors ToolDefinition.toAnthropicSchema().
  Map<String, dynamic> toAnthropicTool() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };

  /// Build a tool_choice map that forces the LLM to call this schema's tool.
  Map<String, dynamic> get forceToolChoice => {
        'type': 'tool',
        'name': name,
      };

  /// The list of required field names from the schema.
  List<String> get requiredFields {
    final req = inputSchema['required'];
    if (req is List) return req.cast<String>();
    return const [];
  }

  /// The property definitions from the schema.
  Map<String, dynamic> get properties {
    final props = inputSchema['properties'];
    if (props is Map<String, dynamic>) return props;
    return {};
  }

  /// Parse a raw JSON string through [fromJson].
  dynamic parseJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return fromJson(json);
  }

  /// Try to parse a JSON string, returning null on failure.
  dynamic tryParseJson(String raw) {
    try {
      return parseJson(raw);
    } catch (_) {
      return null;
    }
  }
}
