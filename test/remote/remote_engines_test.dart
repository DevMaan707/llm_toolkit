import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/core/inference/remote/remote.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

class Captured {
  final String method;
  final String path;
  final HttpHeaders headers;
  final String body;
  Captured(this.method, this.path, this.headers, this.body);
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

typedef Handler = Future<void> Function(HttpRequest req, Captured captured);

late HttpServer server;
late String base;
final requests = <Captured>[];
Handler handler = (req, _) async => req.response.close();

Future<void> sse(HttpResponse r, List<String> events) async {
  r.headers.contentType = ContentType('text', 'event-stream');
  for (final e in events) {
    r.write('data: $e\n\n');
    await r.flush();
  }
}

String delta(String text) => jsonEncode({
  'choices': [
    {
      'delta': {'content': text},
    },
  ],
});

/// Raw TCP server that streams [chunk] every 20 ms and completes
/// [disconnected] when the client closes the socket.
Future<(ServerSocket, Completer<void>)> rawStreamingServer(
  String contentType,
  String Function(int i) chunk,
) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final disconnected = Completer<void>();
  socket.listen((client) async {
    client.listen(
      (_) {},
      onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      },
      onError: (Object _) {
        if (!disconnected.isCompleted) disconnected.complete();
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      client.write(
        'HTTP/1.1 200 OK\r\nContent-Type: $contentType\r\n'
        'Connection: close\r\n\r\n',
      );
      for (var i = 0; i < 300; i++) {
        client.write(chunk(i));
        await client.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } on Object {
      if (!disconnected.isCompleted) disconnected.complete();
    }
  });
  return (socket, disconnected);
}

const config = InferenceConfig();

void main() {
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final body = latin1.decode(
        await req.fold<List<int>>([], (a, b) => a..addAll(b)),
      );
      final captured = Captured(req.method, req.uri.path, req.headers, body);
      requests.add(captured);
      req.response.bufferOutput = false;
      await handler(req, captured);
    });
  });

  tearDown(() => server.close(force: true));

  group('OpenAiCompatibleEngine', () {
    test('streams deltas, sends auth and mapped params', () async {
      handler = (req, c) async {
        if (c.path == '/v1/models') {
          req.response.write('{"data":[]}');
          return req.response.close();
        }
        await sse(req.response, [
          delta('Hel'),
          jsonEncode({'choices': []}),
          delta('lo'),
          '[DONE]',
        ]);
        await req.response.close();
      };
      final engine = OpenAiCompatibleEngine(
        baseUrl: '$base/v1/',
        apiKey: 'sk-test',
        sendExtendedSampling: true,
        headers: {'X-Title': 'app'},
      );
      await engine.loadModel('gpt-x', config);
      expect(engine.isModelLoaded, isTrue);

      final out =
          await engine
              .generateText(
                'hi',
                const GenerationParams(
                  maxTokens: 10,
                  temperature: 0.1,
                  stopSequences: ['END'],
                  seed: 7,
                ),
              )
              .join();
      expect(out, 'Hello');

      final chat = requests.last;
      expect(chat.path, '/v1/chat/completions');
      expect(chat.headers.value('authorization'), 'Bearer sk-test');
      expect(chat.headers.value('x-title'), 'app');
      expect(chat.json['model'], 'gpt-x');
      expect(chat.json['stream'], true);
      expect(chat.json['max_tokens'], 10);
      expect(chat.json['stop'], ['END']);
      expect(chat.json['seed'], 7);
      expect(chat.json['top_k'], 40);
      expect(chat.json['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('omits extended sampling by default and surfaces reasoning', () async {
      handler = (req, c) async {
        await sse(req.response, [
          jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': 'think'},
              },
            ],
          }),
          delta('ok'),
          '[DONE]',
        ]);
        await req.response.close();
      };
      final reasoning = <String>[];
      final engine = OpenAiCompatibleEngine(
        baseUrl: base,
        model: 'm',
        onReasoning: reasoning.add,
      );
      final out =
          await engine.generateText('x', const GenerationParams()).join();
      expect(out, 'ok');
      expect(reasoning, ['think']);
      expect(requests.single.json.containsKey('top_k'), isFalse);
      expect(requests.single.headers.value('authorization'), isNull);
    });

    test('vision payload uses image_url data URIs', () async {
      handler = (req, c) async {
        await sse(req.response, [delta('a cat'), '[DONE]']);
        await req.response.close();
      };
      final engine = OpenAiCompatibleEngine(baseUrl: base, model: 'v');
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2]);
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]);
      await engine.generateWithImages('what?', [
        png,
        jpg,
      ], const GenerationParams()).join();
      final content =
          (requests.single.json['messages'] as List).single['content'] as List;
      expect(content[0], {'type': 'text', 'text': 'what?'});
      expect(content[1]['type'], 'image_url');
      expect(
        content[1]['image_url']['url'],
        'data:image/png;base64,${base64Encode(png)}',
      );
      expect(
        content[2]['image_url']['url'],
        startsWith('data:image/jpeg;base64,'),
      );
    });

    test('cancelling mid-stream closes the connection', () async {
      final (raw, disconnected) = await rawStreamingServer(
        'text/event-stream',
        (i) => 'data: ${delta('t$i')}\n\n',
      );
      addTearDown(() => raw.close());
      final engine = OpenAiCompatibleEngine(
        baseUrl: 'http://127.0.0.1:${raw.port}',
        model: 'm',
      );
      final first =
          await engine.generateText('x', const GenerationParams()).first;
      expect(first, 't0');
      await disconnected.future.timeout(const Duration(seconds: 3));
    });

    test('maps HTTP errors to helpful InferenceExceptions', () async {
      Future<InferenceException> failWith(int status, {String? retry}) async {
        handler = (req, c) async {
          req.response.statusCode = status;
          if (retry != null) req.response.headers.set('retry-after', retry);
          req.response.write(
            jsonEncode({
              'error': {'message': 'boom'},
            }),
          );
          await req.response.close();
        };
        final engine = OpenAiCompatibleEngine(
          baseUrl: base,
          model: 'm',
          apiKey: 'sk-secret',
        );
        try {
          await engine.generateText('x', const GenerationParams()).join();
        } on InferenceException catch (e) {
          return e;
        }
        fail('expected exception');
      }

      expect((await failWith(401)).message, contains('API key'));
      final rate = await failWith(429, retry: '17');
      expect(rate.message, contains('retry after 17s'));
      expect((await failWith(503)).message, contains('server error'));
      expect((await failWith(500)).message, isNot(contains('sk-secret')));
    });

    test('idle stream times out', () async {
      handler = (req, c) async {
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write(': ping\n\n');
        await req.response.flush();
        await Future<void>.delayed(const Duration(seconds: 2));
        await req.response.close();
      };
      final engine = OpenAiCompatibleEngine(
        baseUrl: base,
        model: 'm',
        streamIdleTimeout: const Duration(milliseconds: 200),
      );
      await expectLater(
        engine.generateText('x', const GenerationParams()).join(),
        throwsA(isA<InferenceException>()),
      );
    });

    test('unreachable server maps to InferenceException', () async {
      final port = server.port;
      await server.close(force: true);
      final engine = OpenAiCompatibleEngine(
        baseUrl: 'http://127.0.0.1:$port',
        model: 'm',
      );
      await expectLater(
        engine.generateText('x', const GenerationParams()).join(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains('Cannot reach'),
          ),
        ),
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    test('embeddings are batched and ordered by index', () async {
      handler = (req, c) async {
        req.response.write(
          jsonEncode({
            'data': [
              {
                'index': 1,
                'embedding': [3, 4],
              },
              {
                'index': 0,
                'embedding': [1.5, 2],
              },
            ],
          }),
        );
        await req.response.close();
      };
      final engine = OpenAiCompatibleEngine(
        baseUrl: base,
        model: 'chat',
        embeddingModel: 'emb',
      );
      final vectors = await engine.embedBatch(['a', 'b']);
      expect(vectors, [
        [1.5, 2.0],
        [3.0, 4.0],
      ]);
      expect(engine.embeddingDimensions, 2);
      expect(requests.single.json['model'], 'emb');
      expect(requests.single.json['input'], ['a', 'b']);
    });

    test(
      'loadModel rejects bad credentials but tolerates missing /models',
      () async {
        handler = (req, c) async {
          req.response.statusCode = 401;
          await req.response.close();
        };
        final engine = OpenAiCompatibleEngine(baseUrl: base, apiKey: 'bad');
        await expectLater(
          engine.loadModel('m', config),
          throwsA(isA<InferenceException>()),
        );
        expect(engine.isModelLoaded, isFalse);

        handler = (req, c) async {
          req.response.statusCode = 404;
          await req.response.close();
        };
        await engine.loadModel('m', config);
        expect(engine.currentModelPath, 'm');
      },
    );

    test('capabilities follow flags; disabled features throw', () async {
      final plain = OpenAiCompatibleEngine(baseUrl: base, model: 'm');
      expect(plain.capabilities, {
        ModelCapability.textGeneration,
        ModelCapability.vision,
        ModelCapability.embeddings,
      });
      await expectLater(
        plain.transcribe(Uint8List(4)),
        throwsA(isA<UnsupportedCapabilityException>()),
      );
      final full = OpenAiCompatibleEngine(
        baseUrl: base,
        model: 'm',
        enableSpeech: true,
        enableImages: true,
      );
      expect(
        full.capabilities,
        containsAll([
          ModelCapability.speechToText,
          ModelCapability.textToSpeech,
          ModelCapability.imageGeneration,
        ]),
      );
    });

    test(
      'transcribe uploads multipart WAV and synthesize returns bytes',
      () async {
        handler = (req, c) async {
          if (c.path == '/audio/transcriptions') {
            req.response.write('{"text":" hello "}');
          } else {
            req.response.add([1, 2, 3]);
          }
          await req.response.close();
        };
        final engine = OpenAiCompatibleEngine(
          baseUrl: base,
          model: 'm',
          enableSpeech: true,
        );
        expect(await engine.transcribe(Uint8List(100)), 'hello');
        final upload = requests.single;
        expect(upload.headers.contentType?.mimeType, 'multipart/form-data');
        expect(upload.body, contains('name="model"'));
        expect(upload.body, contains('RIFF'));
        expect(await engine.synthesize('hi', voice: 'nova'), [1, 2, 3]);
        expect(requests.last.json['voice'], 'nova');
      },
    );

    test('image generation handles b64_json and url', () async {
      final png = base64Encode([9, 8, 7]);
      handler = (req, c) async {
        if (c.path == '/img.png') {
          req.response.add([5, 5]);
        } else {
          final useUrl = c.json['prompt'] == 'url';
          req.response.write(
            jsonEncode({
              'data': [
                useUrl ? {'url': '$base/img.png'} : {'b64_json': png},
              ],
            }),
          );
        }
        await req.response.close();
      };
      final engine = OpenAiCompatibleEngine(
        baseUrl: base,
        model: 'm',
        enableImages: true,
      );
      expect(
        await engine.generateImage(const ImageGenerationRequest(prompt: 'b64')),
        [9, 8, 7],
      );
      expect(requests.single.json['size'], '512x512');
      expect(
        await engine.generateImage(const ImageGenerationRequest(prompt: 'url')),
        [5, 5],
      );
    });

    test('fromPreset configures URL and sampling flag', () {
      final engine = OpenAiCompatibleEngine.fromPreset(
        RemoteModelPresets.lmStudio,
      );
      expect(engine.id, 'lm-studio');
      expect(engine.sendExtendedSampling, isTrue);
      expect(
        RemoteModelPresets.all
            .map((p) => p.baseUrl)
            .every((u) => u.startsWith('http')),
        isTrue,
      );
    });
  });

  group('OllamaEngine', () {
    test('streams NDJSON with options, keep_alive and images', () async {
      handler = (req, c) async {
        if (c.path == '/api/tags') {
          req.response.write('{"models":[{"name":"llava"}]}');
        } else {
          for (final line in [
            {
              'message': {'role': 'assistant', 'content': 'Hi'},
              'done': false,
            },
            {
              'message': {'content': ' there'},
              'done': false,
            },
            {
              'message': {'content': ''},
              'done': true,
            },
          ]) {
            req.response.write('${jsonEncode(line)}\n');
            await req.response.flush();
          }
        }
        await req.response.close();
      };
      final engine = OllamaEngine(
        baseUrl: base,
        keepAlive: '10m',
        contextSize: 4096,
      );
      await engine.loadModel('llava', config);
      final img = Uint8List.fromList([1, 2, 3]);
      final out =
          await engine.generateWithImages(
            'see',
            [img],
            const GenerationParams(
              maxTokens: 64,
              seed: 3,
              stopSequences: ['x'],
            ),
          ).join();
      expect(out, 'Hi there');
      final body = requests.last.json;
      expect(requests.last.path, '/api/chat');
      expect(body['keep_alive'], '10m');
      expect(body['messages'][0]['images'], [base64Encode(img)]);
      final options = body['options'] as Map;
      expect(options['num_ctx'], 4096);
      expect(options['num_predict'], 64);
      expect(options['seed'], 3);
      expect(options['stop'], ['x']);
      expect(
        options.keys,
        containsAll(['temperature', 'top_k', 'top_p', 'repeat_penalty']),
      );
    });

    test('mid-stream error line throws; embed uses /api/embed', () async {
      handler = (req, c) async {
        if (c.path == '/api/embed') {
          req.response.write('{"embeddings":[[1,2,3]]}');
        } else {
          req.response.write('${jsonEncode({'error': 'model crashed'})}\n');
        }
        await req.response.close();
      };
      final engine = OllamaEngine(baseUrl: base, model: 'm');
      await expectLater(
        engine.generateText('x', const GenerationParams()).join(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'm',
            contains('model crashed'),
          ),
        ),
      );
      expect(await engine.embed('x'), [1.0, 2.0, 3.0]);
      expect(engine.embeddingDimensions, 3);
    });

    test('cancel mid-stream aborts and 404 maps to a helpful error', () async {
      final (raw, disconnected) = await rawStreamingServer(
        'application/x-ndjson',
        (i) => '{"message":{"content":"a"},"done":false}\n',
      );
      addTearDown(() => raw.close());
      final streaming = OllamaEngine(
        baseUrl: 'http://127.0.0.1:${raw.port}',
        model: 'm',
      );
      await streaming.generateText('x', const GenerationParams()).first;
      await disconnected.future.timeout(const Duration(seconds: 3));

      final engine = OllamaEngine(baseUrl: base, model: 'm');
      handler = (req, c) async {
        req.response.statusCode = 404;
        req.response.write('{"error":"model \'m\' not found"}');
        await req.response.close();
      };
      await expectLater(
        engine.generateText('x', const GenerationParams()).join(),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'm',
            contains('not found'),
          ),
        ),
      );
    });
  });
}
