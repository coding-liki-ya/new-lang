import std.io;
import std.string;
import std.events;

class Token {
    String kind;
    String text;
    Number value = 0;
}

class TokenList {
    List<Token> items = [];
}

class Lexer {
    String input;
    Number position = 0;
    TokenList output = TokenList {};

    event scanned(TokenList tokens);
    event token(Token token);
    event failed(String message, Number position);

    current(out Char ch) {
        if position >= input.len() {
            ch = '\0';
        } else {
            ch = input[position];
        }
    }

    advance() {
        position = position + 1;
    }

    scanNumber(out Token token) {
        let start = position;
        let ch = '\0';

        current(ch);

        while ch.isDigit() || ch == '.' {
            advance();
            current(ch);
        }

        let text = input.slice(start, position);
        token = Token { kind = "number", text, value = text.toFloat() };
    }

    scan() {
        let ch = '\0';

        while position < input.len() {
            current(ch);

            if ch.isWhitespace() {
                advance();
                continue;
            }

            if ch.isDigit() {
                let number = Token {};
                scanNumber(number);
                output.items.push(number);
                this.token(number);
                continue;
            }

            if ch == '+' || ch == '-' || ch == '*' || ch == '/' || ch == '(' || ch == ')' {
                let operator = Token { kind = ch.toString(), text = ch.toString() };
                output.items.push(operator);
                this.token(operator);
                advance();
                continue;
            }

            let message = "unexpected character '" + ch + "'";
            this.failed(message, position);
            events.emit("calculator.failed", { message, position });
            advance();
        }

        output.items.push(Token { kind = "eof", text = "" });
        this.scanned(output);
    }
}

interface Expr {
    event evaluated(Number value);
    evaluate();
}

class NumberExpr : Expr {
    Number value;

    evaluate() {
        this.evaluated(value);
    }
}

class UnaryExpr : Expr {
    String operator;
    Expr right;

    event evaluated(Number value);

    evaluate() {
        right.evaluated += fn(Number value) {
            if operator == "-" {
                this.evaluated(-value);
            } else {
                this.evaluated(value);
            }
        } once;

        right.evaluate();
    }
}

class BinaryExpr : Expr {
    Expr left;
    String operator;
    Expr right;

    event evaluated(Number value);
    event failed(String message);

    evaluate() {
        left.evaluated += fn(Number a) {
            right.evaluated += fn(Number b) {
                if operator == "+" {
                    this.evaluated(a + b);
                } else if operator == "-" {
                    this.evaluated(a - b);
                } else if operator == "*" {
                    this.evaluated(a * b);
                } else if operator == "/" {
                    if b == 0 {
                        this.failed("division by zero");
                        events.emit("calculator.failed", { message = "division by zero" });
                    } else {
                        this.evaluated(a / b);
                    }
                } else {
                    this.failed("unknown binary operator");
                }
            } once;

            right.evaluate();
        } once;

        left.evaluate();
    }
}

class Parser {
    TokenList tokens;
    Number position = 0;

    event parsed(Expr expression);
    event failed(String message, Token token);

    current(out Token token) {
        token = tokens.items[position];
    }

    match(String kind, out Bool matched) {
        let token = Token {};
        current(token);

        if token.kind == kind {
            position = position + 1;
            matched = true;
        } else {
            matched = false;
        }
    }

    expect(String kind, out Bool ok) {
        match(kind, ok);

        if !ok {
            let token = Token {};
            current(token);
            let message = "expected '" + kind + "', got '" + token.text + "'";
            this.failed(message, token);
        }
    }

    parse() {
        let expression = NumberExpr { value = 0 };
        parseExpression(expression);

        let ok = false;
        expect("eof", ok);

        if ok {
            this.parsed(expression);
        }
    }

    parseExpression(out Expr expression) {
        parseAdditive(expression);
    }

    parseAdditive(out Expr expression) {
        parseMultiplicative(expression);

        let token = Token {};
        current(token);

        while token.kind == "+" || token.kind == "-" {
            let operator = token.kind;
            position = position + 1;

            let right = NumberExpr { value = 0 };
            parseMultiplicative(right);

            expression = BinaryExpr { left = expression, operator, right };
            current(token);
        }
    }

    parseMultiplicative(out Expr expression) {
        parseUnary(expression);

        let token = Token {};
        current(token);

        while token.kind == "*" || token.kind == "/" {
            let operator = token.kind;
            position = position + 1;

            let right = NumberExpr { value = 0 };
            parseUnary(right);

            expression = BinaryExpr { left = expression, operator, right };
            current(token);
        }
    }

    parseUnary(out Expr expression) {
        let matched = false;

        match("+", matched);
        if matched {
            parseUnary(expression);
        } else {
            match("-", matched);
            if matched {
                let right = NumberExpr { value = 0 };
                parseUnary(right);
                expression = UnaryExpr { operator = "-", right };
            } else {
                parsePrimary(expression);
            }
        }
    }

    parsePrimary(out Expr expression) {
        let token = Token {};
        current(token);

        if token.kind == "number" {
            position = position + 1;
            expression = NumberExpr { value = token.value };
        } else {
            let matched = false;
            match("(", matched);

            if matched {
                parseExpression(expression);
                let ok = false;
                expect(")", ok);
            } else {
                this.failed("expected number or '('", token);
            }
        }
    }
}

class Calculator {
    event calculated(String input, Number result);
    event failed(String input, String message);

    evaluate(String input) {
        let lexer = Lexer { input };

        lexer.failed += fn(String message, Number position) {
            this.failed(input, message);
        } once;

        lexer.scanned += fn(TokenList tokens) {
            let parser = Parser { tokens };

            parser.failed += fn(String message, Token token) {
                this.failed(input, message);
            } once;

            parser.parsed += fn(Expr ast) {
                ast.evaluated += fn(Number result) {
                    this.calculated(input, result);
                    events.emit("calculator.calculated", { input, result });
                } once;

                ast.evaluate();
            } once;

            parser.parse();
        } once;

        lexer.scan();
    }
}

class ConsoleCalculator {
    Calculator calculator;
    String prompt = "> ";
    Bool running = true;

    run() {
        io.println("New Lang calculator");
        io.println("Type an expression and press Enter. Type 'exit' to quit.");

        calculator.calculated += fn(String input, Number result) {
            io.println(result.toString());
        };

        calculator.failed += fn(String input, String message) {
            io.println("error: " + message);
        };

        while running {
            io.print(prompt);

            let line = io.readLine();

            if line == null {
                running = false;
                continue;
            }

            let input = line.trim();

            if input == "" {
                continue;
            }

            if input == "exit" || input == "quit" {
                running = false;
                continue;
            }

            calculator.evaluate(input);
        }
    }
}

class CalculatorLogging {
    attach(Calculator calculator) {
        calculator.calculated += fn(String input, Number result) {
            events.emit("log", "calculated: " + input + " = " + result);
        };

        calculator.failed += fn(String input, String message) {
            events.emit("log", "failed: " + input + ": " + message);
        };
    }
}

let defaultCalculator = Calculator {};
let console = ConsoleCalculator { calculator = defaultCalculator } + CalculatorLogging {};

fn main(List<String> args) {
    events.on("log", fn(String message) {
        // io.println("log: " + message);
    });

    console.attach(defaultCalculator);
    console.run();
}
