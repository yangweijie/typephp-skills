<?php
// expect: FAIL | Immutable can only be applied to methods
use \Immutable;
#[Immutable] function f(): int { return 1; }
function main(): void {}