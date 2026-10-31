<?php
// expect: FAIL | Cannot call mutable method
use \Immutable;
class U { private string $n = "a"; public function rename(string $s): void { $this->n = $s; }
#[Immutable] public function bad(): void { $this->rename("b"); } }
function main(): void {}