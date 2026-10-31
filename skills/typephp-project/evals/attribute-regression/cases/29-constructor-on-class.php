<?php
// expect: FAIL | can only be applied to instance properties
use \Constructor;
#[Constructor]
class U { private int $id = 0; }
function main(): void {}