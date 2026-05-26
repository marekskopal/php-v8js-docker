<?php
declare(strict_types=1);

// Exercises the v8js extension end-to-end: instantiation, executeString,
// JS → PHP value marshalling, and exception propagation. Run during image
// build so a broken extension fails the build rather than the deploy.

if (!class_exists('V8Js')) {
    fwrite(STDERR, "FAIL: V8Js class not loaded\n");
    exit(1);
}

$v8 = new V8Js();

$result = $v8->executeString('1 + 2', 'smoke');
if ($result !== 3) {
    fwrite(STDERR, "FAIL: expected 3, got " . var_export($result, true) . "\n");
    exit(1);
}

$obj = $v8->executeString('({ name: "v8js", ok: true, n: 42 })', 'smoke-object');
if (!is_object($obj) || $obj->name !== 'v8js' || $obj->ok !== true || $obj->n !== 42) {
    fwrite(STDERR, "FAIL: object round-trip\n");
    exit(1);
}

try {
    $v8->executeString('throw new Error("boom")', 'smoke-throw');
    fwrite(STDERR, "FAIL: expected exception\n");
    exit(1);
} catch (V8JsScriptException $e) {
    // expected
}

printf("smoke OK: PHP %s, V8 %s\n", PHP_VERSION, V8Js::V8_VERSION);
