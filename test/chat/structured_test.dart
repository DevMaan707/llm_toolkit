import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/json_extraction.dart';
import 'package:llm_toolkit/src/chat/json_schema.dart';
import 'package:llm_toolkit/src/chat/structured_output.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

import 'fakes.dart';

const personSchema = JsonSchema.object(
  properties: {
    'name': JsonSchema.string(description: 'Full name'),
    'age': JsonSchema.integer(minimum: 0),
    'role': JsonSchema.enumeration(['admin', 'user']),
    'tags': JsonSchema.array(JsonSchema.string()),
  },
  required: ['name', 'age'],
);

void main() {
  group('extraction', () {
    test('plain, fenced and prose-wrapped', () {
      expect(extractJson('{"a":1}'), {'a': 1});
      expect(extractJson('Sure!\n```json\n{"a": 2}\n```\nDone'), {'a': 2});
      expect(extractJson('Here you go: {"a": 3} hope it helps'), {'a': 3});
    });

    test('repairs trailing commas and single quotes', () {
      expect(extractJson("{'a': 'it\\'s', 'b': [1, 2,],}"), {
        'a': "it's",
        'b': [1, 2],
      });
    });

    test('repairs raw newlines inside strings', () {
      expect(extractJson('{"a": "x\ny"}'), {'a': 'x\ny'});
    });

    test('ignores brackets in prose and returns null when none', () {
      expect(extractJsonValues('see [note] and {x}'), isEmpty);
      expect(extractJson('nothing here'), isNull);
    });

    test('braces inside strings do not confuse matching', () {
      expect(extractJson('x {"a": "}{"} y'), {'a': '}{'});
    });
  });

  group('schema', () {
    test('toJson', () {
      expect(personSchema.toJson()['required'], ['name', 'age']);
      expect((personSchema.toJson()['properties'] as Map)['name'], {
        'type': 'string',
        'description': 'Full name',
      });
    });

    test('validation messages', () {
      expect(personSchema.validate({'name': 'A', 'age': 3}), isEmpty);
      expect(
        personSchema.validate({
          'age': -1,
          'role': 'x',
          'tags': [1],
        }),
        unorderedEquals([
          r'$.name is required',
          r'$.age must be >= 0',
          r'$.role must be one of ["admin","user"]',
          r'$.tags[0] must be a string',
        ]),
      );
      expect(const JsonSchema.integer().validate(1.5), isNotEmpty);
      expect(const JsonSchema.integer().validate(2.0), isEmpty);
      expect(const JsonSchema.boolean().validate('t'), isNotEmpty);
      expect(
        const JsonSchema.object(additionalProperties: false).validate({'z': 1}),
        [r'$.z is not allowed'],
      );
    });

    test('prompt instructions embed the schema', () {
      expect(personSchema.promptInstructions(), contains('"required"'));
    });
  });

  group('generateStructured', () {
    test('returns value from fenced reply', () async {
      final engine = FakeTextGenerator([
        'Result:\n```json\n{"name": "Ada", "age": 36,}\n```',
      ]);
      final v = await generateStructured<Map<String, dynamic>>(
        engine,
        prompt: 'Extract',
        schema: personSchema,
      );
      expect(v, {'name': 'Ada', 'age': 36});
      expect(engine.prompts.single, contains('JSON Schema'));
    });

    test('retries with error feedback', () async {
      final engine = FakeTextGenerator([
        'not json',
        '{"name": "Ada"}',
        '{"name":"Ada","age":1}',
      ]);
      final v = await generateStructured<Object?>(
        engine,
        prompt: 'Extract',
        schema: personSchema,
      );
      expect(v, {'name': 'Ada', 'age': 1});
      expect(engine.prompts[1], contains('the reply contained no JSON'));
      expect(engine.prompts[2], contains(r'$.age is required'));
    });

    test('throws StructuredOutputException with raw output', () async {
      final engine = FakeTextGenerator(['bad1', 'bad2']);
      await expectLater(
        generateStructured<Object?>(
          engine,
          prompt: 'x',
          schema: personSchema,
          maxRetries: 1,
        ),
        throwsA(
          isA<StructuredOutputException>().having(
            (e) => e.rawOutput,
            'rawOutput',
            'bad2',
          ),
        ),
      );
    });

    test('fromJson conversion', () async {
      final engine = FakeTextGenerator(['{"name":"Ada","age":1}']);
      final name = await generateStructured<String>(
        engine,
        prompt: 'x',
        schema: personSchema,
        fromJson: (j) => (j as Map)['name'] as String,
      );
      expect(name, 'Ada');
    });
  });
}
