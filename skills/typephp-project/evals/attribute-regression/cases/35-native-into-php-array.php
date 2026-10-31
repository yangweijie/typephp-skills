<?php
// expect: FAIL | cannot be stored in PHP arrays
use \Native;
#[Native] class P { public int $x = 0; }
function main(): void { $p = new P(); $a = [$p]; }