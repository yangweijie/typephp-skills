<?php
// expect: FAIL | not supported on arrow function
use \NotEmpty;
$arrow = fn(#[NotEmpty] string $n): string => $n;
function main(): void { echo $arrow("x"); }