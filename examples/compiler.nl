import std.io;
import std.fs;
import std.events;
import std.thread;
import newlang.lexer;
import newlang.parser;
import newlang.types;
import newlang.codegen;

interface CompilerStage {
    run(context) -> context;
}

interface DiagnosticSink {
    emit(diagnostic);
}

class SourceFile {
    path;
    text;

    event loaded(file);
    event failed(path, reason);

    static load(path) {
        let text = fs.readText(path);
        let file = SourceFile { path, text };

        file.loaded(file);
        events.emit("source.loaded", file);

        return file;
    }
}

class Diagnostic {
    level;
    message;
    span;
}

class CompilerContext {
    source;
    tokens = [];
    ast;
    symbols;
    typedAst;
    objectCode;
    diagnostics = [];

    event diagnostic(diagnostic);

    addDiagnostic(level, message, span) {
        let diagnostic = Diagnostic { level, message, span };

        diagnostics.push(diagnostic);
        this.diagnostic(diagnostic);
        events.emit("compiler.diagnostic", diagnostic);
    }
}

class LexingStage : CompilerStage {
    run(context) {
        context.tokens = lexer.scan(context.source.text);
        return context;
    }
}

class ParsingStage : CompilerStage {
    run(context) {
        context.ast = parser.parse(context.tokens);
        return context;
    }
}

class TypeCheckingStage : CompilerStage {
    run(context) {
        context.symbols = types.collectSymbols(context.ast);
        context.typedAst = types.infer(context.ast, context.symbols);
        return context;
    }
}

class CodegenStage : CompilerStage {
    target = "native";

    run(context) {
        context.objectCode = codegen.emit(context.typedAst, target);
        return context;
    }
}

class TimedStage {
    name;

    run(context) {
        let startedAt = time.now();
        let result = super.run(context);
        let elapsed = time.now() - startedAt;

        io.println(name + " finished in " + elapsed);
        events.emit("stage.finished", { name, elapsed });

        return result;
    }
}

// Композиция классов: расширяем поведение без наследования.
let TimedLexingStage = LexingStage + TimedStage { name = "lexing" };
let TimedParsingStage = ParsingStage + TimedStage { name = "parsing" };
let TimedTypeCheckingStage = TypeCheckingStage + TimedStage { name = "type-checking" };
let TimedCodegenStage = CodegenStage + TimedStage { name = "codegen" };

fn compile(sourcePath, outputPath) {
    let source = SourceFile.load(sourcePath);
    let context = CompilerContext { source };

    context.diagnostic += fn(diagnostic) {
        io.println("[" + diagnostic.level + "] " + diagnostic.message);
    };

    let pipeline = [
        TimedLexingStage {},
        TimedParsingStage {},
        TimedTypeCheckingStage {},
        TimedCodegenStage { target = "native" },
    ];

    for stage in pipeline {
        context = stage.run(context);
    }

    fs.writeBytes(outputPath, context.objectCode);
    events.emit("compiler.finished", { input = sourcePath, output = outputPath });

    return context;
}

// Композиция функций: добавляем инструкцию в конец существующей функции.
let compileAndReport = compile + fn(context) {
    io.println("compiled with " + context.diagnostics.len() + " diagnostics");
};

fn compileAsync(sourcePath, outputPath) {
    let worker = thread.spawn(fn() {
        return compileAndReport(sourcePath, outputPath);
    });

    return worker.join();
}

fn main(args) {
    events.on("source.loaded", fn(file) {
        io.println("loaded " + file.path);
    });

    events.on("stage.finished", fn(stage) {
        io.println("event: stage " + stage.name + " done");
    });

    if args.len() < 3 {
        io.println("usage: newlangc <input.nl> <output>");
        return 1;
    }

    let result = compileAsync(args[1], args[2]);

    if result.diagnostics.any(fn(d) { d.level == "error" }) {
        return 1;
    }

    return 0;
}
