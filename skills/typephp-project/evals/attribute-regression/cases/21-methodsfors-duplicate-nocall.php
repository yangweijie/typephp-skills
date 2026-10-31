<?php
// expect: PASS
use \MethodsFor;
#[MethodsFor(\Type::String)] final class A { public static function dup(string $v): string { return "A"; } }
#[MethodsFor(\Type::String)] final class B { public static function dup(string $v): string { return "B"; } }
function main(): void { echo "no call\n"; }