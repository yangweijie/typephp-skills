<?php
// expect: FAIL | can only be applied to instance properties
use \Getter;
class U { #[Getter] public function f(): int { return 1; } }
function main(): void {}