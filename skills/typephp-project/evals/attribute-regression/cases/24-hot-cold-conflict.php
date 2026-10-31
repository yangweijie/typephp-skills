<?php
// expect: FAIL | cannot be applied to the same
#[Hot]
#[Cold]
function f(int $n): int { return $n; }
function main(): void {}