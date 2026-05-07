# Language notes

## Composition-first model

New Lang avoids inheritance as the main reuse mechanism. The primary reuse primitive is composition with `+`.

Composition may be applied to:

- classes: extend fields, override methods, extend methods;
- functions: append instructions or handlers;
- objects: override field values and extend field sets;
- interfaces: extend contracts.

## No return values

Functions and methods do not return values with `return`.

A function may produce externally visible results by:

- emitting an event;
- mutating explicit reference parameters;
- mutating object state.

This pushes the language toward event-first and asynchronous-style programming by default.

## Output parameters

An `out` parameter is declared in the function signature:

```newlang
current(out Token token) {
    token = tokens.items[position];
}
```

At the call site, `out` is not written:

```newlang
let token = Token {};
current(token);
```

The compiler resolves argument passing mode by the callee signature and argument position.

All `out` parameters are passed by reference, not by value. Assigning to an `out` parameter mutates the caller-provided variable.

This keeps call sites clean while preserving explicitness in API definitions.
