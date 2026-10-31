<?php
// expect: FAIL | cannot be stored in mutable state
use \Immutable;
class U { private int $n = 1; }
class Box { public ?U $u = null; }
function g(#[Immutable] U $u, Box $b): void { $b->u = $u; }
function main(): void {}