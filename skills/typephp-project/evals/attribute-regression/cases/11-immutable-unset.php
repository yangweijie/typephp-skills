<?php
// expect: FAIL | Cannot modify immutable value
use \Immutable;
class U { private int $n = 1; }
function g(#[Immutable] U $u): void { unset($u); }
function main(): void {}