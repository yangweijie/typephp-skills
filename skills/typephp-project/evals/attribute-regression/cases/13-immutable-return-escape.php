<?php
// expect: FAIL | cannot escape through a return value
use \Immutable;
class U { private int $n = 1; }
function leak(#[Immutable] U $u): U { return $u; }
function main(): void {}