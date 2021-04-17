## Dart CLI Scripting

This package is designed to make it easy to write scripts that call out to
subprocesses with the ease of shell scripting and the power of Dart. It captures
the core virtues of shell scripting: terseness, pipelining, and composability.
At the same time, it uses standard Dart idioms like exceptions, `Stream`s, and
`Future`s, with a few extensions to make them extra easy to work with in a
scripting context.

* [Terseness](#terseness)
  * [The `Script` Class](#the-script-class)
  * [Do The Right Thing](#do-the-right-thing)
* [Pipelining](#pipelining)
* [Composability](#composability)
* [Dartiness](#dartiness)

While `cli_script` can be used as a library in any Dart application, its primary
goal is to support stand-alone scripts that serve the same purpose as shell
scripts. Because they're just normal Dart code, with static types and data
structures and the entire Dart ecosystem at your fingertips, these scripts will
be much more maintainable than their Shell counterparts without sacrificing ease
of use.

Here's an example of a simple Hello World script:

```dart
import 'package:cli_script/cli_script.dart';

Future<void> main() async {
  await run('echo "Hello, world!");
}
```

Many programming environments have tried to make themselves suitable for shell
scripting, but in the end they all fall far short of the ease of calling out to
subprocesseses in Bash. As such, a principal design goal of `cli_pkg` is to
identify the core virtues that make shell scripting so appealing and reproduce
them as closely as possible in Dart:

### Terseness

Shell scripts make it very easy to write code that calls out to child processes
*tersely*, without needing to write a bunch of boilerplate. Running a child
process is as simple as calling [`run()`]:

[`run()`]: https://pub.dev/documentation/cli_script/latest/cli_script/run.html

```dart
import 'package:cli_script/cli_script.dart';

Future<void> main() async {
  await run("mkdir -p path/to/dir");
  await run("touch path/to/dir/foo");
}
```

Similarly, it's easy to get the output of a command just like you would using
`"$(command)"` in a shell, using either [`output()`] to get a single string or
[`lines()`] to get a stream of lines:

[`output()`]: https://pub.dev/documentation/cli_script/latest/cli_script/output.html
[`lines()`]: https://pub.dev/documentation/cli_script/latest/cli_script/output.html

```dart
import 'package:cli_script/cli_script.dart';

Future<void> main() async {
  await for (var file in lines("find . -type f -maxdepth 1")) {
    var contents = await output("cat", args: [file]);
    if (contents.contains("needle")) print(file);
  }
}
```

You can also use [`check()`] to test whether a script returns exit code 0 or
not:

[`check()`]: https://pub.dev/documentation/cli_script/latest/cli_script/check.html

```dart
import 'package:cli_script/cli_script.dart';

Future<void> main() async {
  await for (var file in lines("find . -type f -maxdepth 1")) {
    if (await check("grep -q needle", args: [file])) print(file);
  }
}
```

#### The `Script` Class

All of these top-level functions are just thin wrappers around the [`Script`]
class at the heart of `cli_script`. This class represents a subprocess (or
[something process-like](#composability)) and provides access to its [`stdin`],
[`stdout`], [`stderr`], and [`exitCode`].

[`Script`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script.html
[`stdin`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/stdin.html
[`stdout`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/stdout.html
[`stderr`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/stderr.html
[`exitCode`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/exitCode.html

Although `stdout` and `stderr` are just simple `Stream<List<int>>`s,
representing raw binary data, they're still easy to work with thanks to
`cli_script`'s [extension methods]. These make it easy to transform byte streams
into [line streams] or just [plain strings].

[extension methods]: https://pub.dev/documentation/cli_script/latest/cli_script/ByteStreamExtensions.html
[line streams]: https://pub.dev/documentation/cli_script/latest/cli_script/ByteStreamExtensions/lines.html
[plain strings]: https://pub.dev/documentation/cli_script/latest/cli_script/ByteStreamExtensions/text.html

#### Do The Right Thing

Terseness also means that you don't need any extra boilerplate to ensure that
the right thing happens when something goes wrong. In a shell script, if you
don't redirect a subprocess's output it will automatically print it for the user
to see, so you can automatically see any errors it prints. In `cli_script`, if
you don't listen to a `Script`'s [`stdout`] or [`stderr`] streams immediately
after creating it, they'll be redirected to the parent script's stdout or
stderr, respectively.

Similarly, in a shell script with `set -e` the script will abort as soon as a
child process fails unless that process is in an `if` statement or similar. In
`cli_script`, a `Script` will throw an exception if it exits with a failing exit
code unless the [`exitCode`] or [`success`] fields are accessed.

[`success`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/success.html

### Pipelining

TODO: add pipelining

### Composability

In shell scripts, everything is a process. Obviously child processes are
processes, but functions also have input/output streams and exit codes so that
they work like processes to. You can even group a block of code into a virtual
process using `{}`!

In `cli_script`, anything can be a `Script`. The most common way to make a
script that's not a subprocess is using [`Script.capture()`]. This factory
constructor runs a block of code and captures all stdout and stderr produced by
child scripts (or calls to `print()`) into that `Script`'s [`stdout`] and
[`stderr`]:

[`Script.capture()`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/capture.html

```dart
import 'package:cli_script/cli_script.dart';

Future<void> main() async {
  var script = Script.capture((_) async {
    await run("find . -type f -maxdepth 1");
    print("subdir/extra-file");
  });

  await for (var file in script.stdout.lines) {
    if (await check("grep -q needle", args: [file])) print(file);
  }
}
```

If an exception is thrown within `Script.capture()`, including by a child
process returning an unhandled non-zero exit code, the entire capture block will
fail—but it'll fail like a process: by printing error messages to its stderr and
emitting a non-zero exit code that can be handled like any other `Script`'s.

`Script.capture()` also provides access to the script's [`stdin`], as a stream
that's passed into the callback. The capture block can ignore this completely,
it can use it as input to a child process or, it can do really whatever it
wants!
