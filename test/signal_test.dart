import 'dart:async';
import 'dart:io';

import 'package:cli_script/cli_script.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  test('interrupts a long-running program with default signal', () async {
    var script =
        mainScript('await Future<void>.delayed(Duration(seconds: 100));');

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await script.signal(), true);

    expect(script.done, throwsScriptException(-15));
  });

  test('interrupts a long-running program with custom signal', () async {
    var script =
        mainScript('await Future<void>.delayed(Duration(seconds: 100));');

    await Future<void>.delayed(Duration(seconds: 1));
    var ack = await script.signal(ProcessSignal.sigint);
    expect(ack, true);

    expect(script.done, throwsScriptException(-2));
  });

  test("can't interrupt a program that has already exited", () async {
    var script =
        mainScript('await Future<void>.delayed(Duration(seconds: 1));');

    await Future<void>.delayed(Duration(seconds: 2));
    expect(await script.signal(), false);

    expect(script.done, completes);
  });

  test("doesn't interrupt program that traps signals", () async {
    var script = _watchSignalsAndExit();
    var output = script.output;

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await script.signal(), true);

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await script.signal(), false);

    expect(await output, 'SIGTERM\nbye!');
  });

  test("can't interrupt Script.capture", () async {
    var script = Script.capture((_) async {
      await Future<void>.delayed(Duration(seconds: 2));
      print('done!');
    });
    var output = script.output;

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await script.signal(), true);

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await script.signal(), false);

    expect(await output, 'done!');
  });

  test("doesn't forward signal via Script.capture", () async {
    var script = Script.capture((_) async => _watchSignalsAndExit().done);
    var output = script.output;

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await script.signal(), true);

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await script.signal(), false);

    expect(await output, 'bye!');
  });

  test("can't interrupt BufferedScript.capture", () async {
    var script = BufferedScript.capture((_) async {
      await Future<void>.delayed(Duration(seconds: 2));
      print('done!');
    });
    var done = false;
    var output = script.output.then((v) {
      done = true;
      return v;
    });

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await script.signal(), true);

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await script.signal(), false);

    expect(done, false);
    await script.release();

    expect(await output, 'done!');
  });

  test("doesn't forward signal via BufferedScript.capture", () async {
    var script =
        BufferedScript.capture((_) async => _watchSignalsAndExit().done);
    var done = false;
    var output = script.output.then((v) {
      done = true;
      return v;
    });

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await script.signal(), true);

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await script.signal(), false);

    expect(done, false);
    await script.release();

    expect(await output, 'bye!');
  });

  test("can't interrupt Script.fromByteTransformer", () async {
    var script = Script.fromByteTransformer(zlib.decoder);

    expect(await script.signal(), true);

    await script.stdin.close();

    expect(await script.signal(), false);
  });

  test("sends signal to script currently running in a pipe chain", () async {
    var pipeline = _watchSignalsAndExit() | mainScript(r'''
      var signalStream = ProcessSignal.sigterm.watch().listen((event) {
        print('b: $event');
      });
      while(true) {
        var line = stdin.readLineSync();
        if (line == null) break;
        print('from a: $line');
      }
      await Future<void>.delayed(Duration(seconds: 2));
      print('b: bye!');
      await signalStream.cancel();
    ''');
    var lines = pipeline.lines;

    await Future<void>.delayed(Duration(seconds: 1));
    expect(await pipeline.signal(), true);

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await pipeline.signal(), true);

    expect(
        lines,
        emitsInOrder([
          'from a: SIGTERM',
          'from a: bye!',
          'b: SIGTERM',
          'b: bye!',
        ]));

    await Future<void>.delayed(Duration(seconds: 3));
    expect(await pipeline.signal(), false);
  });
}

Script _watchSignalsAndExit() => mainScript(r'''
  var signalStream = ProcessSignal.sigterm.watch().listen(print);
  await Future<void>.delayed(Duration(seconds: 2));
  await signalStream.cancel();
  print('bye!');
''');
