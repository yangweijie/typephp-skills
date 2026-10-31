<?php
// expect: PASS_WARN | NotNull is applied to nullable parameter
use \NotNull;
function f(#[NotNull] ?string $s): void { echo $s ?? "null"; }
function main(): void { f(null); }