<?php
// expect: FAIL | cannot also be declared unless it is box
use \StdVector;
function f(#[StdVector(Type::Int)] mixed $v): void { }
function main(): void {}