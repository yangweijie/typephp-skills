<?php
// expect: FAIL | must declare a type
use \Native;
#[Native] class P { public $x; }
function main(): void {}