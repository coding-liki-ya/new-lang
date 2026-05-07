import std.io;
import std.string;
import std.events;

class Token {
    kind;
    text;
    value = 0;
}

class Lexer {
    input;
    position = 0;
    tokens = [];

    event token(token);
    event error(message, position);

    current() {
        if position >= input.len() {
            return '\0';
        }

        return input[position];
    }

    advance() {
        position = position + 1;
    }

    scanNumber() {
        let start = position;

        while current().isDigit() || current() == '.' {
            advance();
        }

        let text = input.slice(start, position);
        return Token { kind = "number", text, value = text.toFloat() };
    }

    scan() {
        while position < input.len() {
            let ch = current();

            if ch.isWhitespace() {
                advance();
                continue;
            }

            if ch.isDigit() {
                let number = scanNumber();
                tokens.push(number);
                this.token(number);
                continue;
            }

            if ch == '+' || ch == '-' || ch == '*' || ch == '/' || ch == '(' || ch == ')' {
                let operator = Token { kind = ch.toString(), text = ch.toString() };
                tokens.push(operator);
                this.token(operator);
                advance();
                continue;
            }

            let message = "unexpected character '" + ch + "'";
            this.error(message, position);
            events.emit("calculator.error", { message, position });
            advance();
        }

        tokens.push(Token { kind = "eof", text = "" });
        return tokens;
    }
}

interface Expr {
    eval() -> number;
}

class NumberExpr : Expr {
    value;

    eval() {
        return value;
    }
}

class UnaryExpr : Expr {
    operator;
    right;

    eval() {
        let value = right.eval();

        if operator == "-" {
            return -value;
        }

        return value;
    }
}

class BinaryExpr : Expr {
    left;
    operator;
    right;

    eval() {
        let a = left.eval();
        let b = right.eval();

        if operator == "+" {
            return a + b;
        }

        if operator == "-" {
            return a - b;
        }

        if operator == "*" {
            return a * b;
        }

        if operator == "/" {
            if b == 0 {
                events.emit("calculator.error", { message = "division by zero", position = 0 });
                fail "division by zero";
            }

            return a / b;
        }

        fail "unknown binary operator";
    }
}

class Parser {
    tokens;
    position = 0;

    event error(message, token);

    current() {
        return tokens[position];
    }

    match(kind) {
        if current().kind == kind {
            position = position + 1;
            return true;
        }

        return false;
    }

    expect(kind) {
        if match(kind) {
            return;
        }

        let message = "expected '" + kind + "', got '" + current().text + "'";
        this.error(message, current());
        fail message;
    }

    parse() {
        let expression = parseExpression();
        expect("eof");
        return expression;
    }

    parseExpression() {
        return parseAdditive();
    }

    parseAdditive() {
        let expression = parseMultiplicative();

        while current().kind == "+" || current().kind == "-" {
            let operator = current().kind;
            position = position + 1;
            let right = parseMultiplicative();
            expression = BinaryExpr { left = expression, operator, right };
        }

        return expression;
    }

    parseMultiplicative() {
        let expression = parseUnary();

        while current().kind == "*" || current().kind == "/" {
            let operator = current().kind;
            position = position + 1;
            let right = parseUnary();
            expression = BinaryExpr { left = expression, operator, right };
        }

        return expression;
    }

    parseUnary() {
        if match("+") {
            return parseUnary();
        }

        if match("-") {
            return UnaryExpr { operator = "-", right = parseUnary() };
        }

        return parsePrimary();
    }

    parsePrimary() {
        if current().kind == "number" {
            let value = current().value;
            position = position + 1;
            return NumberExpr { value };
        }

        if match("(") {
            let expression = parseExpression();
            expect(")");
            return expression;
        }

        let message = "expected number or '('";
        this.error(message, current());
        fail message;
    }
}

class Calculator {
    event calculated(input, result);
    event failed(input, message);

    evaluate(input) {
        let lexer = Lexer { input };
        let tokens = lexer.scan();

        let parser = Parser { tokens };
        let ast = parser.parse();
        let result = ast.eval();

        this.calculated(input, result);
        events.emit("calculator.calculated", { input, result });

        return result;
    }
}

class ConsoleCalculator {
    calculator;
    prompt = "> ";

    run() {
        io.println("New Lang calculator");
        io.println("Type an expression and press Enter. Type 'exit' to quit.");

        while true {
            io.print(prompt);

            let line = io.readLine();

            if line == null {
                break;
            }

            let input = line.trim();

            if input == "" {
                continue;
            }

            if input == "exit" || input == "quit" {
                break;
            }

            try {
                let result = calculator.evaluate(input);
                io.println(result.toString());
            } catch error {
                calculator.failed(input, error.message);
                events.emit("calculator.failed", { input, message = error.message });
                io.println("error: " + error.message);
            }
        }
    }
}

class CalculatorLogging {
    attach(calculator) {
        calculator.calculated += fn(input, result) {
            events.emit("log", "calculated: " + input + " = " + result);
        };

        calculator.failed += fn(input, message) {
            events.emit("log", "failed: " + input + ": " + message);
        };
    }
}

// Композиция объектов: базовый объект расширяется настройками консольного режима.
let defaultCalculator = Calculator {};
let console = ConsoleCalculator { calculator = defaultCalculator } + CalculatorLogging {};

fn main(args) {
    events.on("log", fn(message) {
        // Для обычного калькулятора лог можно оставить отключенным.
        // io.println("log: " + message);
    });

    console.attach(defaultCalculator);
    console.run();

    return 0;
}
