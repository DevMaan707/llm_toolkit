import 'dart:convert';

/// A small JSON Schema subset: enough to describe model output, render it in
/// a prompt and validate parsed values.
class JsonSchema {
  final String? type; // null for enumerations of mixed values
  final String? description;
  final Map<String, JsonSchema> properties;
  final List<String> required;
  final bool additionalProperties;
  final JsonSchema? items;
  final int? minItems;
  final int? maxItems;
  final List<Object?>? enumValues;
  final num? minimum;
  final num? maximum;
  final int? minLength;
  final int? maxLength;

  const JsonSchema._({
    this.type,
    this.description,
    this.properties = const {},
    this.required = const [],
    this.additionalProperties = true,
    this.items,
    this.minItems,
    this.maxItems,
    this.enumValues,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
  });

  const JsonSchema.object({
    Map<String, JsonSchema> properties = const {},
    List<String> required = const [],
    String? description,
    bool additionalProperties = true,
  }) : this._(
         type: 'object',
         properties: properties,
         required: required,
         description: description,
         additionalProperties: additionalProperties,
       );

  const JsonSchema.array(
    JsonSchema items, {
    String? description,
    int? minItems,
    int? maxItems,
  }) : this._(
         type: 'array',
         items: items,
         description: description,
         minItems: minItems,
         maxItems: maxItems,
       );

  const JsonSchema.string({String? description, int? minLength, int? maxLength})
    : this._(
        type: 'string',
        description: description,
        minLength: minLength,
        maxLength: maxLength,
      );

  const JsonSchema.number({String? description, num? minimum, num? maximum})
    : this._(
        type: 'number',
        description: description,
        minimum: minimum,
        maximum: maximum,
      );

  const JsonSchema.integer({String? description, num? minimum, num? maximum})
    : this._(
        type: 'integer',
        description: description,
        minimum: minimum,
        maximum: maximum,
      );

  const JsonSchema.boolean({String? description})
    : this._(type: 'boolean', description: description);

  /// One of a fixed set of values (usually strings).
  const JsonSchema.enumeration(List<Object?> values, {String? description})
    : this._(enumValues: values, description: description);

  /// Standard JSON Schema map.
  Map<String, dynamic> toJson() => {
    if (type != null) 'type': type,
    if (description != null) 'description': description,
    if (enumValues != null) 'enum': enumValues,
    if (type == 'object') ...{
      'properties': {
        for (final e in properties.entries) e.key: e.value.toJson(),
      },
      if (required.isNotEmpty) 'required': required,
      if (!additionalProperties) 'additionalProperties': false,
    },
    if (items != null) 'items': items!.toJson(),
    if (minItems != null) 'minItems': minItems,
    if (maxItems != null) 'maxItems': maxItems,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (minLength != null) 'minLength': minLength,
    if (maxLength != null) 'maxLength': maxLength,
  };

  /// Pretty-printed schema for embedding in prompts.
  String toPrettyString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  /// Prompt text asking a model to answer with JSON matching this schema.
  String promptInstructions() =>
      'Respond with a single valid JSON value that conforms to this JSON '
      'Schema. Output only the JSON, with no explanation and no markdown.\n'
      '${toPrettyString()}';

  /// Returns human-readable violations of [value]; empty means valid.
  List<String> validate(Object? value, {String path = r'$'}) {
    final errors = <String>[];
    _validate(value, path, errors);
    return errors;
  }

  void _validate(Object? v, String path, List<String> errors) {
    final enums = enumValues;
    if (enums != null && !enums.contains(v)) {
      errors.add('$path must be one of ${jsonEncode(enums)}');
      return;
    }
    switch (type) {
      case null:
        return;
      case 'object':
        if (v is! Map) return errors.add('$path must be an object');
        for (final key in required) {
          if (!v.containsKey(key)) errors.add('$path.$key is required');
        }
        for (final e in v.entries) {
          final sub = properties[e.key];
          if (sub != null) {
            sub._validate(e.value, '$path.${e.key}', errors);
          } else if (!additionalProperties) {
            errors.add('$path.${e.key} is not allowed');
          }
        }
      case 'array':
        if (v is! List) return errors.add('$path must be an array');
        if (minItems != null && v.length < minItems!) {
          errors.add('$path must have at least $minItems items');
        }
        if (maxItems != null && v.length > maxItems!) {
          errors.add('$path must have at most $maxItems items');
        }
        for (var i = 0; i < v.length; i++) {
          items?._validate(v[i], '$path[$i]', errors);
        }
      case 'string':
        if (v is! String) return errors.add('$path must be a string');
        if (minLength != null && v.length < minLength!) {
          errors.add('$path must be at least $minLength characters');
        }
        if (maxLength != null && v.length > maxLength!) {
          errors.add('$path must be at most $maxLength characters');
        }
      case 'number' || 'integer':
        if (v is! num) return errors.add('$path must be a $type');
        if (type == 'integer' && v is double && v != v.truncateToDouble()) {
          return errors.add('$path must be an integer');
        }
        if (minimum != null && v < minimum!) {
          errors.add('$path must be >= $minimum');
        }
        if (maximum != null && v > maximum!) {
          errors.add('$path must be <= $maximum');
        }
      case 'boolean':
        if (v is! bool) errors.add('$path must be a boolean');
    }
  }
}
