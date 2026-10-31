<?php
// expect: FAIL | cannot be converted to mixed
use \Native;
#[Native] class P { public int $x = 0; }
function main(): void { $p = new P(); $m = std::any($p); }