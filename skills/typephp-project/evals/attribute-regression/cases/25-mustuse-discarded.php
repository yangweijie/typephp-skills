<?php
// expect: FAIL | must be used
use \MustUse;
#[MustUse]
function openFile(string $f): string { return $f; }
function main(): void { openFile("a.txt"); }