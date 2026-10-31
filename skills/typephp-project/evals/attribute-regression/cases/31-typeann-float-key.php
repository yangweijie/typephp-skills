<?php
// expect: FAIL | key only supports
use \StdMap;
function f(#[StdMap(Type::Float, Type::Int)] $v): void { }
function main(): void {}