<?php
// expect: FAIL | readonly properties are not supported
use \Native;
#[Native] class P { public readonly int $x = 0; }
function main(): void {}