<?php
// expect: FAIL | is incompatible with parameter
use \Validate;
function reg(#[Validate(FILTER_VALIDATE_EMAIL)] int $e): void { echo $e; }
function main(): void { reg(1); }