<?php
// expect: FAIL | Only typed lists support append
function main(): void { $d = std::dict(Type::Str, Type::Int); $d[] = 1; }