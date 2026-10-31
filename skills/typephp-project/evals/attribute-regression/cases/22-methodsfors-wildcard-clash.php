<?php
// expect: FAIL | conflicts with keyword extension method
use \MethodsFor;
#[MethodsFor("*")] final class S { public static function dup(any $v, string $l = ""): any { return "star"; } }
#[MethodsFor(\Type::Int)] final class I { public static function dup(int $v): string { return "int"; } }
function main(): void { $n = 1; echo $n->dup(), "\n"; }