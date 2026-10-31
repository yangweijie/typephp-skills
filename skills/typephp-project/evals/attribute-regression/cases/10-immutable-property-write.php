<?php
// expect: FAIL | Cannot modify immutable value
use \Immutable;
class U { private string $n = "a";
#[Immutable] public function f(): string { $this->n = "b"; return "x"; } }
function main(): void {}