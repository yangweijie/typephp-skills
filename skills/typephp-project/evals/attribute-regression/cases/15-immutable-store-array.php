<?php
// expect: FAIL | cannot be stored in mutable state
use \Immutable;
class U { private int $n = 1; }
function g(#[Immutable] U $u): void { $a = []; $a[] = $u; }
function main(): void {}