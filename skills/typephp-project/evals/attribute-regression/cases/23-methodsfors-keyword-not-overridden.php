<?php
// expect: RUN | ^42$
use \MethodsFor;
#[MethodsFor(\Type::String)] final class P { public static function toInt(string $v): int { return 999; } }
function main(): void { $s = "42"; echo $s->toInt(), "\n"; }